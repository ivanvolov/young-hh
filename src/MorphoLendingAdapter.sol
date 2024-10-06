// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import "@src/interfaces/ILendingAdapter.sol";
import {IMorpho, Id, Position} from "@forks/morpho/IMorpho.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

contract MorphoLendingAdapter is Ownable, ILendingAdapter {
    bytes internal constant ZERO_BYTES = bytes("");

    address public authorizedV4Pool;
    Id public depositUSDCmId;
    Id public borrowUSDCmId;

    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    constructor(address _authorizedV4Pool) Ownable(msg.sender) {
        authorizedV4Pool = _authorizedV4Pool;

        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);
    }

    function setDepositUSDCmId(Id _depositUSDCmId) external onlyOwner {
        depositUSDCmId = _depositUSDCmId;
    }

    function setBorrowUSDCmId(Id _borrowUSDCmId) external onlyOwner {
        borrowUSDCmId = _borrowUSDCmId;
    }

    function setAuthorizedV4Pool(address _authorizedV4Pool) external onlyOwner {
        authorizedV4Pool = _authorizedV4Pool;
    }

    // Borrow market

    function getBorrowed() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(
                morpho,
                morpho.idToMarketParams(borrowUSDCmId),
                authorizedV4Pool
            );
    }

    function borrow(uint256 amountUSDC) external onlyAuthorizedV4Pool {
        morpho.borrow(
            morpho.idToMarketParams(borrowUSDCmId),
            amountUSDC,
            0,
            address(this),
            authorizedV4Pool
        );
    }

    function replay(uint256 amountUSDC) external onlyAuthorizedV4Pool {
        USDC.transferFrom(authorizedV4Pool, address(this), amountUSDC);
        morpho.repay(
            morpho.idToMarketParams(borrowUSDCmId),
            amountUSDC,
            0,
            address(this),
            ZERO_BYTES
        );
    }

    function getCollateral() external view returns (uint256) {
        Position memory p = morpho.position(borrowUSDCmId, address(this));
        return p.collateral;
    }

    function removeCollateral(uint256 amount) external onlyAuthorizedV4Pool {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(borrowUSDCmId),
            amount,
            address(this),
            authorizedV4Pool
        );
    }

    function addCollateral(uint256 amount) external onlyAuthorizedV4Pool {
        WETH.transferFrom(authorizedV4Pool, address(this), amount);
        morpho.supplyCollateral(
            morpho.idToMarketParams(borrowUSDCmId),
            amount,
            address(this),
            ZERO_BYTES
        );
    }

    // Provide market

    function getSupplied() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedSupplyAssets(
                morpho,
                morpho.idToMarketParams(depositUSDCmId),
                authorizedV4Pool
            );
    }

    function supply(uint256 amountUsdc) external onlyAuthorizedV4Pool {
        console.log("> supply", amountUsdc);
        USDC.transferFrom(authorizedV4Pool, address(this), amountUsdc);
        console.log("USDC is taken away, nice");
        morpho.supply(
            morpho.idToMarketParams(depositUSDCmId),
            amountUsdc,
            0,
            address(this),
            ZERO_BYTES
        );
    }

    function withdraw(uint256 amountUsdc) external onlyAuthorizedV4Pool {
        morpho.withdraw(
            morpho.idToMarketParams(depositUSDCmId),
            amountUsdc,
            0,
            address(this),
            authorizedV4Pool
        );
    }

    function syncDeposit() external {
        morpho.accrueInterest(morpho.idToMarketParams(depositUSDCmId));
    }

    function syncBorrow() external {
        morpho.accrueInterest(morpho.idToMarketParams(borrowUSDCmId));
    }

    // Helpers

    modifier onlyAuthorizedV4Pool() {
        require(
            msg.sender == authorizedV4Pool,
            "Caller is not authorized V4 pool"
        );
        _;
    }
}
// TODO: remove in production
// LINKS: https://docs.morpho.org/morpho/tutorials/manage-positions
