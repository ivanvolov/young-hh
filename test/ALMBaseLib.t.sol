// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ALMBaseLib} from "../src/libraries/ALMBaseLib.sol";

contract ALMBaseLibTest is Test {
    address WETH;
    address USDC;

    function setUp() public {
        WETH = ALMBaseLib.WETH;
        vm.label(WETH, "WETH");
        USDC = ALMBaseLib.USDC;
        vm.label(USDC, "USDC");
    }

    function test_getFee() public view {
        assertEq(ALMBaseLib.getFee(USDC, WETH), ALMBaseLib.ETH_USDC_POOL_FEE);
        assertEq(ALMBaseLib.getFee(WETH, USDC), ALMBaseLib.ETH_USDC_POOL_FEE);
    }
}
