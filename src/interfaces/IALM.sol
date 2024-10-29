// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

interface IALM {
    error ZeroLiquidity();
    error NotHookDeployer();
    error NotRebalanceAdapter();
    error AddLiquidityThroughHook();
    error ContractPaused();
    error ContractShutdown();
    error NotEnoughSharesToWithdraw();

    error UnauthorizedPool();

    struct ALMInfo {
        uint256 amount;
        uint256 sqrtPrice;
        int24 tickLower;
        int24 tickUpper;
        uint256 created;
    }

    function sqrtPriceCurrent() external view returns (uint160);

    function refreshReserves() external;
}
