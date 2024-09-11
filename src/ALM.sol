// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {ERC721} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseStrategyHook} from "@src/BaseStrategyHook.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {AutomationCompatibleInterface} from "@forks/chainlink/AutomationCompatibleInterface.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager,
        Id _bWETHmId,
        Id _bUSDCmId
    ) BaseStrategyHook(manager) ERC721("ALM", "ALM") {
        bWETHmId = _bWETHmId;
        bUSDCmId = _bUSDCmId;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        USDC.approve(lendingPool, type(uint256).max);
        WETH.approve(lendingPool, type(uint256).max);
        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);

        return ALM.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        PoolKey calldata key,
        uint256 amount,
        address to
    ) external override returns (uint256 almId) {
        console.log(">> deposit");
        if (amount == 0) revert ZeroLiquidity();

        liquidity = ALMMathLib.getLiquidityFromAmount1SqrtPriceX96(
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            sqrtPriceCurrent,
            amount
        );
        (, uint256 amount1) = ALMMathLib.getAmountsFromLiquiditySqrtPriceX96(
            sqrtPriceCurrent,
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            ALMMathLib.getSqrtPriceAtTick(tickLower),
            liquidity
        );

        WETH.transferFrom(msg.sender, address(this), amount1);
        morphoSupplyCollateral(bUSDCmId, WETH.balanceOf(address(this)));

        almId = almIdCounter;
        almInfo[almId] = ALMInfo({
            amount: amount,
            sqrtPrice: sqrtPriceCurrent,
            tickLower: tickLower,
            tickUpper: tickUpper,
            created: block.timestamp
        });

        _mint(to, almId);
        almIdCounter++;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    // --- Rebalance

    function isPriceRebalanceNeeded() public view returns (bool) {
        int24 tickLastRebalance = ALMMathLib.getTickFromSqrtPrice(
            sqrtPriceLastRebalance
        );
        int24 tickCurrent = ALMMathLib.getTickFromSqrtPrice(sqrtPriceCurrent);

        int24 tickDelta = tickCurrent - tickLastRebalance;
        tickDelta = tickDelta > 0 ? tickDelta : -tickDelta;

        return tickDelta > 2000;
    }

    function rebalance() public {
        if (!isPriceRebalanceNeeded()) revert NoRebalanceNeeded();

        morphoSync(bUSDCmId);
        morphoSync(bWETHmId);

        uint256 usdcToRepay = borrowAssets(bUSDCmId, address(this));
        uint256 usdcSupplied = suppliedAssets(bWETHmId, address(this));
        if (usdcSupplied > 0) {
            uint256 deltaUSDC = usdcSupplied >= usdcToRepay
                ? usdcToRepay
                : usdcSupplied;
            morphoWithdrawCollateral(bWETHmId, deltaUSDC);
            usdcToRepay -= deltaUSDC;
        }
        if (usdcToRepay > 0) {
            address[] memory assets = new address[](1);
            uint256[] memory modes = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            modes[0] = 0;
            assets[0] = address(USDC);
            amounts[0] = usdcToRepay;

            LENDING_POOL.flashLoan(
                address(this),
                assets,
                amounts,
                modes,
                address(this),
                abi.encode(""),
                0
            );
        }

        sqrtPriceLastRebalance = sqrtPriceCurrent;
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == lendingPool, "M0");
        logBalances();
        uint256 usdcBorrowed = borrowAssets(bUSDCmId, address(this));
        morphoReplay(bUSDCmId, usdcBorrowed, 0);

        uint256 wethCollateral = suppliedCollateral(bUSDCmId, address(this));
        console.log("wethCollateral", wethCollateral);
        morphoWithdrawCollateral(bUSDCmId, wethCollateral - 1e12);

        ALMBaseLib.swapExactOutput(
            address(WETH),
            address(USDC),
            amounts[0] + premiums[0]
        );
        morphoSupplyCollateral(bUSDCmId, WETH.balanceOf(address(this)));
        return true;
    }

    // --- Chainlink Automation

    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return (isPriceRebalanceNeeded(), checkData);
    }

    function performUpkeep(bytes calldata) external override {
        rebalance();
    }

    // ---  Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        morphoSync(bWETHmId);
        morphoSync(bUSDCmId);

        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), usdcIn, false);
            morphoSupplyCollateral(bWETHmId, usdcIn);

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            morphoWithdrawCollateral(bUSDCmId, wethOut);
            key.currency1.settle(poolManager, address(this), wethOut, false);

            sqrtPriceCurrent = sqrtPriceNext;
            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        } else {
            console.log("> WETH price go down...");
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // TLDR: Here we borrow USDC at Morpho and give it back.

            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethIn,
                uint256 usdcOut,
                uint160 sqrtPriceNext
            ) = getOneForZeroDeltas(params.amountSpecified);

            // Put extra ETH to Morpho
            key.currency1.take(poolManager, address(this), wethIn, false);
            morphoSupplyCollateral(bUSDCmId, wethIn);

            // Ensure we have enough USDC. Redeem from reserves and borrow if needed.
            redeemAndBorrow(usdcOut);
            key.currency0.settle(poolManager, address(this), usdcOut, false);

            sqrtPriceCurrent = sqrtPriceNext;
            return (this.beforeSwap.selector, beforeSwapDelta, 0);
        }
    }

    function getZeroForOneDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 wethOut,
            uint256 usdcIn,
            uint160 sqrtPriceNext
        )
    {
        if (amountSpecified > 0) {
            console.log("> amount specified positive");
            wethOut = uint256(amountSpecified);

            (usdcIn, , sqrtPriceNext) = ALMMathLib.getSwapAmountsFromAmount1(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(wethOut)
            );
            usdcIn = adjustForFeesUp(usdcIn);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(wethOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            console.log("> amount specified negative");

            usdcIn = uint256(-amountSpecified);

            (, wethOut, sqrtPriceNext) = ALMMathLib.getSwapAmountsFromAmount0(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(usdcIn)
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdcIn)), // specified token = token0
                -int128(uint128(wethOut)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 wethIn,
            uint256 usdcOut,
            uint160 sqrtPriceNext
        )
    {
        if (amountSpecified > 0) {
            console.log("> amount specified positive");

            usdcOut = uint256(amountSpecified);

            (, wethIn, sqrtPriceNext) = ALMMathLib.getSwapAmountsFromAmount0(
                sqrtPriceCurrent,
                liquidity,
                usdcOut
            );
            wethIn = adjustForFeesUp(wethIn);
            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(wethIn)) // unspecified token = token1
            );
        } else {
            console.log("> amount specified negative");
            wethIn = uint256(-amountSpecified);

            (usdcOut, , sqrtPriceNext) = ALMMathLib.getSwapAmountsFromAmount1(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(wethIn)
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(wethIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    function redeemAndBorrow(uint256 usdcOut) internal {
        uint256 usdcSupplied = suppliedAssets(bWETHmId, address(this));
        if (usdcSupplied > 0) {
            if (usdcSupplied > usdcOut) {
                morphoWithdrawCollateral(bWETHmId, usdcOut);
            } else {
                morphoWithdrawCollateral(bWETHmId, usdcSupplied);
                morphoBorrow(bUSDCmId, usdcOut - usdcSupplied, 0);
            }
        } else {
            morphoBorrow(bUSDCmId, usdcOut, 0);
        }
    }

    function adjustForFeesDown(
        uint256 amount
    ) public view returns (uint256 amountAdjusted) {
        console.log("> amount specified", amount);
        amountAdjusted = amount - (amount * getSwapFees()) / 1e18;
        console.log("> amount adjusted ", amountAdjusted);
    }

    function adjustForFeesUp(
        uint256 amount
    ) public view returns (uint256 amountAdjusted) {
        console.log("> amount specified", amount);
        amountAdjusted = amount + (amount * getSwapFees()) / 1e18;
        console.log("> amount adjusted ", amountAdjusted);
    }

    function getSwapFees() public view returns (uint256) {
        (, int256 RV7, , , ) = AggregatorV3Interface(
            ALMBaseLib.CHAINLINK_7_DAYS_VOL
        ).latestRoundData();
        (, int256 RV30, , , ) = AggregatorV3Interface(
            ALMBaseLib.CHAINLINK_30_DAYS_VOL
        ).latestRoundData();
        return ALMMathLib.calculateSwapFee(RV7 * 1e18, RV30 * 1e18);
    }
}
