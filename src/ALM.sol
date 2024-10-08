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
import {BaseStrategyHook} from "@src/core/BaseStrategyHook.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager
    ) BaseStrategyHook(manager) ERC721("ALM", "ALM") {}

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160 sqrtPrice,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries();
        return ALM.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyAuthorizedPool(key) returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function deposit(
        uint256 amount,
        address to
    ) external notPaused notShutdown returns (uint256 almId) {
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
        lendingAdapter.addCollateral(WETH.balanceOf(address(this)));

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

    function withdraw(uint256 almId) external notPaused {}

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    // ---  Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    )
        external
        override
        notPaused
        notShutdown
        onlyAuthorizedPool(key)
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        lendingAdapter.syncDeposit();
        lendingAdapter.syncBorrow();

        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // wethOut, usdcIn
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.

            SwapData memory swapData = getZeroForOneDeltas(
                params.amountSpecified
            );

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(
                poolManager,
                address(this),
                swapData.usdcAmount,
                false
            );
            repayAndSupply(swapData.usdcAmount); // Notice: repaying if needed to reduce lending interest.

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            lendingAdapter.removeCollateral(swapData.wethAmount);
            key.currency1.settle(
                poolManager,
                address(this),
                swapData.wethAmount,
                false
            );

            sqrtPriceCurrent = swapData.sqrtPriceNext;
            return (this.beforeSwap.selector, swapData.beforeSwapDelta, 0);
        } else {
            console.log("> WETH price go down...");
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // wethIn, usdcOut
            // TLDR: Here we borrow USDC at Morpho and give it back.

            SwapData memory swapData = getOneForZeroDeltas(
                params.amountSpecified
            );

            // Put extra WETH to Morpho
            key.currency1.take(
                poolManager,
                address(this),
                swapData.wethAmount,
                false
            );
            lendingAdapter.addCollateral(swapData.wethAmount);

            // Ensure we have enough USDC. Redeem from reserves and borrow if needed.
            redeemAndBorrow(swapData.usdcAmount);
            key.currency0.settle(
                poolManager,
                address(this),
                swapData.usdcAmount,
                false
            );

            sqrtPriceCurrent = swapData.sqrtPriceNext;
            return (this.beforeSwap.selector, swapData.beforeSwapDelta, 0);
        }
    }

    // Notice: This is to avoid stuck to deep
    struct SwapData {
        BeforeSwapDelta beforeSwapDelta;
        uint256 wethAmount;
        uint256 usdcAmount;
        uint160 sqrtPriceNext;
    }

    function getZeroForOneDeltas(
        int256 amountSpecified
    ) internal view returns (SwapData memory swapData) {
        if (amountSpecified > 0) {
            console.log("> amount specified positive");
            swapData.wethAmount = uint256(amountSpecified);

            //TODO: this sqrtPriceNext is not always correct, especially when we are doing reverse swaps. Use another method to calculate it
            (uint256 usdcIn, , uint160 sqrtPriceNext) = ALMMathLib
                .getSwapAmountsFromAmount1(
                    sqrtPriceCurrent,
                    liquidity,
                    adjustForFeesDown(swapData.wethAmount)
                );
            swapData.usdcAmount = adjustForFeesUp(usdcIn);
            swapData.sqrtPriceNext = sqrtPriceNext;

            swapData.beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(swapData.wethAmount)), // specified token = token1
                int128(uint128(swapData.usdcAmount)) // unspecified token = token0
            );
        } else {
            console.log("> amount specified negative");

            swapData.usdcAmount = uint256(-amountSpecified);

            (, uint256 wethOut, uint160 sqrtPriceNext) = ALMMathLib
                .getSwapAmountsFromAmount0(
                    sqrtPriceCurrent,
                    liquidity,
                    adjustForFeesDown(swapData.usdcAmount)
                );

            swapData.wethAmount = wethOut;
            swapData.sqrtPriceNext = sqrtPriceNext;

            swapData.beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(swapData.usdcAmount)), // specified token = token0
                -int128(uint128(swapData.wethAmount)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    ) internal view returns (SwapData memory swapData) {
        if (amountSpecified > 0) {
            console.log("> amount specified positive");

            swapData.usdcAmount = uint256(amountSpecified);

            (, uint256 wethIn, uint160 sqrtPriceNext) = ALMMathLib
                .getSwapAmountsFromAmount0(
                    sqrtPriceCurrent,
                    liquidity,
                    swapData.usdcAmount
                );
            swapData.wethAmount = adjustForFeesUp(wethIn);
            swapData.sqrtPriceNext = sqrtPriceNext;

            swapData.beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(swapData.usdcAmount)), // specified token = token0
                int128(uint128(swapData.wethAmount)) // unspecified token = token1
            );
        } else {
            console.log("> amount specified negative");
            swapData.wethAmount = uint256(-amountSpecified);

            (uint256 usdcAmount, , uint160 sqrtPriceNext) = ALMMathLib
                .getSwapAmountsFromAmount1(
                    sqrtPriceCurrent,
                    liquidity,
                    adjustForFeesDown(swapData.wethAmount)
                );
            swapData.usdcAmount = usdcAmount;
            swapData.sqrtPriceNext = sqrtPriceNext;

            swapData.beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(swapData.wethAmount)), // specified token = token1
                -int128(uint128(swapData.usdcAmount)) // unspecified token = token0
            );
        }
    }

    function redeemAndBorrow(uint256 usdcOut) internal {
        uint256 withdrawAmount = ALMMathLib.min(
            lendingAdapter.getSupplied(),
            usdcOut
        );
        if (withdrawAmount > 0) lendingAdapter.withdraw(withdrawAmount);

        if (usdcOut > withdrawAmount)
            lendingAdapter.borrow(usdcOut - withdrawAmount);
    }

    function repayAndSupply(uint256 amountUSDC) internal {
        uint256 repayAmount = ALMMathLib.min(
            lendingAdapter.getBorrowed(),
            amountUSDC
        );
        if (repayAmount > 0) lendingAdapter.repay(repayAmount);
        if (amountUSDC > repayAmount)
            lendingAdapter.supply(amountUSDC - repayAmount);
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
