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
import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

import {IALM} from "@src/interfaces/IALM.sol";

/// @title ALM Control hook for simulation
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALMControl is BaseHook, ERC20 {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IALM hook;

    PoolKey key;

    constructor(IPoolManager _manager, address _hook) BaseHook(_manager) ERC20("ALMControl", "hhALMControl") {
        hook = IALM(_hook);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
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

    function deposit(uint256 amount) external {
        require(amount != 0);

        (uint160 sqrtPriceX96, ) = getTick();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(hook.tickUpper()),
            sqrtPriceX96,
            amount
        );

        uint256 TVL1 = TVL();
        uint256 _sharePrice = sharePrice();

        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (key, int128(liquidity), hook.tickUpper(), hook.tickLower(), msg.sender)
            )
        );

        if (_sharePrice == 0) {
            _mint(msg.sender, TVL());
        } else {
            uint256 shares = ((TVL() - TVL1) * 1e18) / _sharePrice;
            _mint(msg.sender, shares);
        }
    }

    function withdraw(uint256 shares) external {
        require(balanceOf(msg.sender) >= shares);

        //TODO: better do some poke here
        uint256 ratio = (shares * 1e18) / totalSupply();
        console.log("ratio", ratio);

        _burn(msg.sender, shares);

        (uint128 totalLiquidity, , ) = getPositionInfo();

        uint256 liquidityToBurn = (uint256(totalLiquidity) * (ratio)) / 1e18;
        console.log("liquidity", liquidityToBurn);
        console.log("totalLiquidity", totalLiquidity);

        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (key, -int128(uint128(liquidityToBurn)), hook.tickUpper(), hook.tickLower(), msg.sender)
            )
        );
    }

    function sharePrice() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (TVL() * 1e18) / totalSupply();
    }

    function getTick() public view returns (uint160 sqrtPriceX96, int24 currentTick) {
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
            key.currency0.settle(poolManager, sender, uint256(uint128(-delta.amount0())), false);
        }

        if (delta.amount0() > 0) {
            key.currency0.take(poolManager, sender, uint256(uint128(delta.amount0())), false);
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(poolManager, sender, uint256(uint128(-delta.amount1())), false);
        }

        if (delta.amount1() > 0) {
            key.currency1.take(poolManager, sender, uint256(uint128(delta.amount1())), false);
        }
        return "";
    }

    function TVL() public view returns (uint256) {
        uint256 price = _calcCurrentPrice();
        (uint256 amount0, uint256 amount1) = getUniswapPositionAmounts();
        // console.log("amount0", amount0);
        // console.log("amount1", amount1);
        return amount1 + (amount0 * 1e30) / price;
    }

    function getUniswapPositionAmounts() public view returns (uint256, uint256) {
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = getPositionInfo();

        (uint160 sqrtPriceX96, ) = getTick();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(hook.tickUpper()),
            TickMath.getSqrtPriceAtTick(hook.tickLower()),
            liquidity
        );

        uint256 owed0 = FullMath.mulDiv(feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);

        uint256 owed1 = FullMath.mulDiv(feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
        //TODO: check if this fee calculation is working good
        return (amount0 + owed0, amount1 + owed1);
    }

    function getPositionInfo() public view returns (uint128, uint256, uint256) {
        return poolManager.getPositionInfo(key.toId(), address(this), hook.tickUpper(), hook.tickLower(), bytes32(""));
    }

    function _calcCurrentPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96, ) = getTick();
        return ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96);
    }

    function afterInitialize(
        address,
        PoolKey calldata _key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        key = _key;
        return ALMControl.afterInitialize.selector;
    }
}
