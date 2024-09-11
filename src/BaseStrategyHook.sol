// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH} from "@forks/IWETH.sol";
import {IMorpho, Id, Position as MorphoPosition} from "@forks/morpho/IMorpho.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

abstract contract BaseStrategyHook is BaseHook, IALM {
    using CurrencySettler for Currency;

    IWETH WETH = IWETH(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    Id public immutable bWETHmId;
    Id public immutable bUSDCmId;

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    uint160 public sqrtPriceLastRebalance;
    int24 public tickLower;
    int24 public tickUpper;

    // aavev2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

    function setBoundaries(
        uint160 initialSQRTPrice,
        int24 _tickUpper,
        int24 _tickLower
    ) external onlyHookDeployer {
        tickUpper = _tickUpper;
        tickLower = _tickLower;
        sqrtPriceCurrent = initialSQRTPrice;
        sqrtPriceLastRebalance = initialSQRTPrice;
    }

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    bytes internal constant ZERO_BYTES = bytes("");
    address public immutable hookDeployer;

    uint256 public almIdCounter = 0;
    mapping(uint256 => ALMInfo) almInfo;

    function getALMInfo(
        uint256 almId
    ) external view override returns (ALMInfo memory) {
        return almInfo[almId];
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        hookDeployer = msg.sender;
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
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    //TODO: remove in production
    function logBalances() internal view {
        console.log("> hook balances");
        if (USDC.balanceOf(address(this)) > 0)
            console.log("USDC  ", USDC.balanceOf(address(this)));
        if (WETH.balanceOf(address(this)) > 0)
            console.log("WETH  ", WETH.balanceOf(address(this)));
    }

    // --- Morpho Wrappers ---

    function morphoBorrow(
        Id morphoMarketId,
        uint256 amount,
        uint256 shares
    ) internal {
        morpho.borrow(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            address(this)
        );
    }

    function morphoReplay(
        Id morphoMarketId,
        uint256 amount,
        uint256 shares
    ) internal {
        morpho.repay(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            shares,
            address(this),
            ZERO_BYTES
        );
    }

    function morphoWithdrawCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            address(this)
        );
    }

    function morphoSupplyCollateral(
        Id morphoMarketId,
        uint256 amount
    ) internal {
        morpho.supplyCollateral(
            morpho.idToMarketParams(morphoMarketId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    function suppliedAssets(
        Id morphoMarketId,
        address owner
    ) internal view returns (uint256) {
        return
            MorphoBalancesLib.expectedSupplyAssets(
                morpho,
                morpho.idToMarketParams(morphoMarketId),
                owner
            );
    }

    function borrowAssets(
        Id morphoMarketId,
        address owner
    ) internal view returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(
                morpho,
                morpho.idToMarketParams(morphoMarketId),
                owner
            );
    }

    function suppliedCollateral(
        Id morphoMarketId,
        address owner
    ) internal view returns (uint256) {
        MorphoPosition memory p = morpho.position(morphoMarketId, owner);
        return p.collateral;
    }

    function morphoSync(Id morphoMarketId) internal {
        morpho.accrueInterest(morpho.idToMarketParams(morphoMarketId));
    }

    /// @dev Only the hook deployer may call this function
    modifier onlyHookDeployer() {
        if (msg.sender != hookDeployer) revert NotHookDeployer();
        _;
    }
}
