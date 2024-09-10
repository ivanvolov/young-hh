// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

//TODO: move this into ALMMathLib
library CMathLib {
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

    function getLiquidityFromAmountsSqrtPriceX96(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceCurrentX96,
            sqrtPriceUpperX96,
            sqrtPriceLowerX96,
            amount0,
            amount1
        );
        return uint128(liquidity);
    }

    function getLiquidityFromAmount1SqrtPriceX96(
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                amount1
            );
    }

    //TODO: Not the right lib
    function getLiquidityForValue(
        uint256 v,
        uint256 p,
        uint256 pH,
        uint256 pL,
        uint256 digits
    ) external pure returns (uint128) {
        return
            toUint128(
                v.div((p.sqrt()).mul(2e18) - pL.sqrt() - p.div(pH.sqrt())).mul(
                    digits
                )
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

    // --- Helpers ---

    // function getSqrtPriceFromPrice(
    //     uint256 price
    // ) internal pure returns (uint160) {
    //     return getSqrtPriceAtTick(CMathLib.getTickFromPrice(price));
    // }

    // function getTickFromPrice(uint256 price) internal pure returns (int24) {
    //     return
    //         toInt24(
    //             (
    //                 (int256(PRBMathUD60x18.ln(price * 1e18)) -
    //                     int256(41446531673892820000))
    //             ) / 99995000333297
    //         );
    // }

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function toInt24(int256 value) internal pure returns (int24) {
        require(value >= type(int24).min && value <= type(int24).max, "MH1");
        return int24(value);
    }

    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "MH2");
        return uint160(value);
    }

    /// @dev Casts uint256 to uint128 with overflow check.
    function toUint128(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }
}
