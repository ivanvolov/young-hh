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
import {BaseStrategyHook} from "@src/core/BaseStrategyHook.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

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

contract SRebalanceAdapter is Ownable {
    error NoRebalanceNeeded();

    ILendingAdapter public lendingAdapter;
    IALM public alm;

    uint160 public sqrtPriceLastRebalance;

    int24 public tickDeltaThreshold = 2000;

    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // aavev2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

    constructor() Ownable(msg.sender) {
        USDC.approve(lendingPool, type(uint256).max);
        WETH.approve(lendingPool, type(uint256).max);
    }

    function setALM(address _alm) external onlyOwner {
        alm = IALM(_alm);
    }

    function setSqrtPriceLastRebalance(
        uint160 _sqrtPriceLastRebalance
    ) external onlyOwner {
        sqrtPriceLastRebalance = _sqrtPriceLastRebalance;
    }

    function setLendingAdapter(address _lendingAdapter) external onlyOwner {
        lendingAdapter = ILendingAdapter(_lendingAdapter);
    }

    function setTickDeltaThreshold(
        int24 _tickDeltaThreshold
    ) external onlyOwner {
        tickDeltaThreshold = _tickDeltaThreshold;
    }

    function isPriceRebalanceNeeded() public view returns (bool) {
        int24 tickLastRebalance = ALMMathLib.getTickFromSqrtPrice(
            sqrtPriceLastRebalance
        );
        int24 tickCurrent = ALMMathLib.getTickFromSqrtPrice(
            alm.sqrtPriceCurrent()
        );

        int24 tickDelta = tickCurrent - tickLastRebalance;
        tickDelta = tickDelta > 0 ? tickDelta : -tickDelta;

        return tickDelta > tickDeltaThreshold;
    }

    function rebalance() public onlyOwner {
        if (!isPriceRebalanceNeeded()) revert NoRebalanceNeeded();

        lendingAdapter.syncBorrow();
        lendingAdapter.syncDeposit();

        // TLDR: we have two cases: have usdc; have usdc debt;
        uint256 usdcToRepay = lendingAdapter.getBorrowed();
        if (usdcToRepay > 0) {
            // USDC debt. Borrow usdc to repay, repay. Swap ETH to USDC. Return back.
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            uint256[] memory modes = new uint256[](1);
            (assets[0], amounts[0], modes[0]) = (address(USDC), usdcToRepay, 0);
            LENDING_POOL.flashLoan(
                address(this),
                assets,
                amounts,
                modes,
                address(this),
                "",
                0
            );
        } else {
            // USDC supplied: just swap USDC to ETH
            uint256 usdcSupplied = lendingAdapter.getSupplied();
            if (usdcSupplied > 0) {
                lendingAdapter.withdraw(usdcSupplied);
                uint256 ethOut = ALMBaseLib.swapExactInput(
                    address(USDC),
                    address(WETH),
                    usdcSupplied
                );
                lendingAdapter.addCollateral(ethOut);
            }
        }

        sqrtPriceLastRebalance = alm.sqrtPriceCurrent();
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == lendingPool, "M0");
        lendingAdapter.replay(amounts[0]);
        lendingAdapter.removeCollateral(lendingAdapter.getCollateral());

        ALMBaseLib.swapExactOutput(
            address(WETH),
            address(USDC),
            amounts[0] + premiums[0]
        );
        lendingAdapter.addCollateral(WETH.balanceOf(address(this)));
        return true;
    }
}
