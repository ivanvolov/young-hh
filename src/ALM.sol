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

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC721 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(
        IPoolManager manager,
        Id _morphoMarketId
    ) BaseStrategyHook(manager) ERC721("ALM", "ALM") {
        morphoMarketId = _morphoMarketId;
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log(">> afterInitialize");

        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);

        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);

        setTickLast(key.toId(), tick);

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
        WETH.transferFrom(msg.sender, address(this), amount);

        morphoSupplyCollateral(WETH.balanceOf(address(this)));
        almId = almIdCounter;

        // almInfo[almId] = ALMInfo({
        //     amount: amount,
        //     tick: getCurrentTick(key.toId()),
        //     tickLower: tickLower,
        //     tickUpper: tickUpper,
        //     created: block.timestamp,
        //     fee: getUserFee()
        // });

        // _mint(to, almId);
        // almIdCounter++;
    }

    // function withdraw(
    //     PoolKey calldata key,
    //     uint256 almId,
    //     address to
    // ) external override {
    //     console.log(">> withdraw");
    //     if (ownerOf(almId) != msg.sender) revert NotAnALMOwner();

    //     //** swap all OSQTH in WSTETH
    //     uint256 balanceOSQTH = OSQTH.balanceOf(address(this));
    //     if (balanceOSQTH != 0) {
    //         ALMBaseLib.swapOSQTH_WSTETH_In(uint256(int256(balanceOSQTH)));
    //     }

    //     //** close position into WSTETH & USDC
    //     {
    //         (
    //             uint128 liquidity,
    //             int24 tickLower,
    //             int24 tickUpper
    //         ) = getALMPosition(key, almId);

    //         poolManager.unlock(
    //             abi.encodeCall(
    //                 this.unlockModifyPosition,
    //                 (key, -int128(liquidity), tickLower, tickUpper)
    //             )
    //         );
    //     }

    //     //** if USDC is borrowed buy extra and close the position
    //     morphoSync();
    //     Market memory m = morpho.market(morphoMarketId);
    //     uint256 usdcToRepay = m.totalBorrowAssets;
    //     MorphoPosition memory p = morpho.position(
    //         morphoMarketId,
    //         address(this)
    //     );

    //     if (usdcToRepay != 0) {
    //         uint256 balanceUSDC = USDC.balanceOf(address(this));
    //         if (usdcToRepay > balanceUSDC) {
    //             ALMBaseLib.swapExactOutput(
    //                 address(WSTETH),
    //                 address(USDC),
    //                 usdcToRepay - balanceUSDC
    //             );
    //         } else {
    //             ALMBaseLib.swapExactOutput(
    //                 address(USDC),
    //                 address(WSTETH),
    //                 balanceUSDC
    //             );
    //         }

    //         morphoReplay(0, p.borrowShares);
    //     }

    //     morphoWithdrawCollateral(p.collateral);
    //     WSTETH.transfer(to, WSTETH.balanceOf(address(this)));

    //     delete almInfo[almId];
    // }

    // function afterSwap(
    //     address,
    //     PoolKey calldata key,
    //     IPoolManager.SwapParams calldata,
    //     BalanceDelta deltas,
    //     bytes calldata
    // ) external virtual override returns (bytes4, int128) {
    //     console.log(">> afterSwap");
    //     if (deltas.amount0() == 0 && deltas.amount1() == 0)
    //         revert NoSwapWillOccur();

    //     int24 tick = getCurrentTick(key.toId());

    //     if (tick > getTickLast(key.toId())) {
    //         console.log("> price go up...");

    //         morphoBorrow(uint256(int256(-deltas.amount1())), 0);
    //         ALMBaseLib.swapUSDC_OSQTH_In(uint256(int256(-deltas.amount1())));
    //     } else if (tick < getTickLast(key.toId())) {
    //         console.log("> price go down...");
    //         // get ETH => Morpho
    //         // borrow USDC => user

    //         MorphoPosition memory p = morpho.position(
    //             morphoMarketId,
    //             address(this)
    //         );
    //         if (p.borrowShares != 0) {
    //             ALMBaseLib.swapOSQTH_USDC_Out(
    //                 uint256(int256(deltas.amount1()))
    //             );

    //             morphoReplay(uint256(int256(deltas.amount1())), 0);
    //         }
    //     } else {
    //         console.log("> price not changing...");
    //     }

    //     setTickLast(key.toId(), tick);
    //     return (ALM.afterSwap.selector, 0);
    // }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    // Swapping
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        //TODO: I will put here 1-1 ration, and not uniswap curve to simplify the code until I fix this.
        //TODO: Maybe move smth into the afterSwap hook, you know

        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            int128(-params.amountSpecified), // So `specifiedAmount` = +100
            int128(params.amountSpecified) // Unspecified amount (output delta) = -100
        );

        uint256 amountInOutPositive = params.amountSpecified > 0
            ? uint256(params.amountSpecified)
            : uint256(-params.amountSpecified);
        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            morphoWithdrawCollateral(amountInOutPositive);
            console.log("> !");

            key.currency1.settle(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
            console.log("> !");
        } else {
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // TLDR: Here we borrow USDC at Morpho and give it back. And If we have USDC just also give it back before borrow.

            console.log("> ETH price go down..."); // we get WETH should return USDC
            revert("!");
            // key.currency0.settle(
            //     poolManager,
            //     address(this),
            //     amountInOutPositive,
            //     true
            // );
            // key.currency1.take(
            //     poolManager,
            //     address(this),
            //     amountInOutPositive,
            //     true
            // );
        }

        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        uint256 amountInOutPositive = params.amountSpecified > 0
            ? uint256(params.amountSpecified)
            : uint256(-params.amountSpecified);

        if (params.zeroForOne) {
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook
            // and create an equivalent credit for that Token 0 since it is ours!
            console.log("> !");
            console.log(USDC.balanceOf(address(poolManager)));
            console.log(USDC.balanceOf(address(address(this))));
            key.currency0.take(
                poolManager,
                address(this),
                amountInOutPositive,
                true
            );
            key.currency0.settle(
                poolManager,
                address(this),
                amountInOutPositive,
                true
            );
            key.currency0.take(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );
            // key.currency0.settle(
            //     poolManager,
            //     address(this),
            //     amountInOutPositive,
            //     false
            // );
            //TODO: make to put USDC to morpho to earn interest rates
            console.log("> !");
        } else {
            console.log("> ETH price go down...");
            revert("!");
        }
        return (this.afterSwap.selector, 0);
    }
}
