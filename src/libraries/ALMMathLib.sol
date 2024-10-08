// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

library ALMMathLib {
    using FixedPointMathLib for uint256;

    function getSwapAmountsFromAmount0(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint256, uint256, uint160) {
        uint160 sqrtPriceNextX96 = toUint160(
            uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                uint256(liquidity) +
                    amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
            )
        );

        return (
            LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            sqrtPriceNextX96
        );
    }

    function getSwapAmountsFromAmount1(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint256, uint256, uint160) {
        uint160 sqrtPriceDeltaX96 = toUint160((amount1 * 2 ** 96) / liquidity);
        uint160 sqrtPriceNextX96 = sqrtPriceCurrentX96 + sqrtPriceDeltaX96;

        return (
            LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            ),
            sqrtPriceNextX96
        );
    }

    function getLiquidityFromAmount1SqrtPriceX96(
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount1(
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                amount1
            );
    }

    function getAmountsFromLiquiditySqrtPriceX96(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceCurrentX96,
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                liquidity
            );
    }

    function calculateSwapFee(
        int256 RV7,
        int256 RV30
    ) internal pure returns (uint256) {
        int256 F0 = 3000000000000000; // 0.003
        int256 alpha = 2049000000000000000; // 2.049
        int256 minFee = 500000000000000; //0.05%
        int256 maxFess = 5000000000000000; //0.5%

        int256 R = (alpha * (((RV7 * 1e18) / RV30) - 1e18)) / 1e18;
        return uint256(max(minFee, min(maxFess, (F0 * (1e18 + R)) / 1e18)));
    }

    // --- Helpers ---

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function getTickFromSqrtPrice(
        uint160 sqrtPriceX96
    ) internal pure returns (int24) {
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function toInt24(int256 value) internal pure returns (int24) {
        require(value >= type(int24).min && value <= type(int24).max, "MH1");
        return int24(value);
    }

    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "MH2");
        return uint160(value);
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
