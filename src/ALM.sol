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
        /**
        BalanceDelta is a packed value of (currency0Amount, currency1Amount)

        BeforeSwapDelta varies such that it is not sorted by token0 and token1
        Instead, it is sorted by "specifiedCurrency" and "unspecifiedCurrency"

        Specified Currency => The currency in which the user is specifying the amount they're swapping for
        Unspecified Currency => The other currency

        For example, in an ETH/USDC pool, there are 4 possible swap cases:

        1. ETH for USDC with Exact Input for Output (amountSpecified = negative value representing ETH)
        2. ETH for USDC with Exact Output for Input (amountSpecified = positive value representing USDC)
        3. USDC for ETH with Exact Input for Output (amountSpecified = negative value representing USDC)
        4. USDC for ETH with Exact Output for Input (amountSpecified = positive value representing ETH)
    
        -------
        
        Assume zeroForOne = true (without loss of generality)
        Assume abs(amountSpecified) = 100

        For an exact input swap where amountSpecified is negative (-100)
            -> specified token = token0
            -> unspecified token = token1
            -> we set deltaSpecified = -(-100) = 100
            -> we set deltaUnspecified = -100
            -> i.e. hook is owed 100 specified token (token0) by PM (that comes from the user)
            -> and hook owes 100 unspecified token (token1) to PM (to go to the user)
    
        For an exact output swap where amountSpecified is positive (100)
            -> specified token = token1
            -> unspecified token = token0
            -> we set deltaSpecified = -100
            -> we set deltaUnspecified = 100
            -> i.e. hook owes 100 specified token (token1) to PM (to go to the user)
            -> and hook is owed 100 unspecified token (token0) by PM (that comes from the user)

        In either case, we can design BeforeSwapDelta as (-params.amountSpecified, params.amountSpecified)
    
    */

        //TODO: I will put here 1-1 ration, and not uniswap curve to simplify the code until I fix this.

        BeforeSwapDelta beforeSwapDelta = toBeforeSwapDelta(
            int128(-params.amountSpecified), // So `specifiedAmount` = +100
            int128(params.amountSpecified) // Unspecified amount (output delta) = -100
        );

        uint256 amountInOutPositive = params.amountSpecified > 0
            ? uint256(params.amountSpecified)
            : uint256(-params.amountSpecified);
        if (params.zeroForOne) {
            // If user is selling Token 0 and buying Token 1
            console.log("> ETH price go down..."); // we get more eth should return USDC

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook
            // and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );

            // We don't have token 1 on our account yet, so we need to borrow USDC from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            morphoBorrow(amountInOutPositive, 0);

            key.currency1.settle(
                poolManager,
                address(this),
                amountInOutPositive,
                false
            );

            // key.currency1.take(
            //     poolManager,
            //     address(this),
            //     amountInOutPositive,
            //     true
            // );

            // // They will be receiving Token 1 from the PM, creating a credit of Token 1 in the PM
            // // We will burn claim tokens for Token 1 from the hook so PM can pay the user
            // // and create an equivalent debit for Token 1 since it is ours!
            // key.currency1.settle(
            //     poolManager,
            //     address(this),
            //     amountInOutPositive,
            //     true
            // );
        } else {
            console.log("> ETH price go up..."); // we get USDC should return ETH
            revert("ETH price go up, it should not in this test");
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
}
