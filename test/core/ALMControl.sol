// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

import {IALM} from "@src/interfaces/IALM.sol";

/// @title ALM Control hook for simulation
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALMControl is BaseHook {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IALM hook;

    constructor(IPoolManager _manager, address _hook) BaseHook(_manager) {
        hook = IALM(_hook);
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function deposit(PoolKey calldata key, uint256 amount) external {
        require(amount != 0);

        (uint160 sqrtPriceX96, ) = getTick(key);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(hook.tickUpper()),
            sqrtPriceX96,
            amount
        );

        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (
                    key,
                    int128(liquidity),
                    hook.tickUpper(),
                    hook.tickLower(),
                    msg.sender
                )
            )
        );
    }

    function getTick(
        PoolKey calldata key
    ) public view returns (uint160 sqrtPriceX96, int24 currentTick) {
        (sqrtPriceX96, currentTick, , ) = poolManager.getSlot0(key.toId());
    }

    function unlockModifyPosition(
        PoolKey calldata key,
        int128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        address sender
    ) external selfOnly returns (bytes memory) {
        // console.log("> unlockModifyPosition");
        // console.log(sender);

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidity,
                salt: bytes32("")
            }),
            ""
        );

        if (delta.amount0() < 0) {
            key.currency0.settle(
                poolManager,
                sender,
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount0() > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(
                poolManager,
                sender,
                uint256(uint128(-delta.amount1())),
                false
            );
        }

        if (delta.amount1() > 0) {
            key.currency1.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount1())),
                false
            );
        }
        return "";
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external view override onlyByPoolManager returns (bytes4) {
        return ALMControl.afterInitialize.selector;
    }

    function TVL(PoolKey calldata key) public view returns (uint256) {
        uint256 price = _calcCurrentPrice(key);
        (uint256 amount0, uint256 amount1) = getUniswapPositionAmounts(key);
        return amount1 + (amount0 * 1e30) / price;
    }

    function getUniswapPositionAmounts(
        PoolKey calldata key
    ) public view returns (uint256, uint256) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        ) = poolManager.getPositionInfo(
                key.toId(),
                address(this),
                hook.tickUpper(),
                hook.tickLower(),
                bytes32("")
            );

        (uint160 sqrtPriceX96, ) = getTick(key);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(hook.tickUpper()),
                TickMath.getSqrtPriceAtTick(hook.tickLower()),
                liquidity
            );
        return (
            amount0 + feeGrowthInside0LastX128,
            amount1 + feeGrowthInside1LastX128
        );
    }

    function _calcCurrentPrice(
        PoolKey calldata key
    ) public view returns (uint256) {
        (uint160 sqrtPriceX96, ) = getTick(key);
        return ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96);
    }
}
