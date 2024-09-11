// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {AutomationCompatibleInterface} from "@forks/chainlink/AutomationCompatibleInterface.sol";

interface IALM is AutomationCompatibleInterface {
    error ZeroLiquidity();
    error NotHookDeployer();
    error AddLiquidityThroughHook();
    error NoRebalanceNeeded();

    struct ALMInfo {
        uint256 amount;
        uint256 sqrtPrice;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
    }

    function sqrtPriceCurrent() external view returns (uint160);

    function getALMInfo(uint256 almId) external view returns (ALMInfo memory);

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

    function getSwapFees() external returns (uint256);
}
