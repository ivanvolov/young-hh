// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IALM {
    error ZeroLiquidity();

    error AddLiquidityThroughHook();

    error InRange();

    error NotAnALMOwner();

    error NoSwapWillOccur();

    struct ALMInfo {
        uint256 amount;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
        uint256 fee;
    }

    function sqrtPriceCurrent() external view returns (uint160);

    function getALMInfo(uint256 almId) external view returns (ALMInfo memory);

    function priceScalingFactor() external view returns (uint256);

    function cRatio() external view returns (uint256);

    function weight() external view returns (uint256);

    function getTickLast(PoolId poolId) external view returns (int24);

    function deposit(
        PoolKey calldata key,
        uint256 amount,
        address to
    ) external returns (uint256 almId);

    function setBoundaries(
        uint160 initialSQRTPrice,
        int24 _tickUpper,
        int24 _tickLower
    ) external;
}
