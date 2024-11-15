// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestSimBase} from "@test/core/ALMTestSimBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {ALM} from "@src/ALM.sol";
import {ALMControl} from "@test/core/ALMControl.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ALMSimulationTest is ALMTestSimBase {
    using PoolIdLibrary for PoolId;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        clear_snapshots();

        initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228

        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        create_and_seed_morpho_markets();
        init_hook();
        init_control_hook();
        approve_accounts();
        presetChainlinkOracles();

        deal(address(USDC), address(swapper.addr), 100_000_000 * 1e6);
        deal(address(WETH), address(swapper.addr), 100_000 * 1e18);
    }

    function test_simulation_start() public {
        maxDepositors = 3;
        maxDeposits = 0;
        numberOfSwaps = 10;
        expectedPoolPriceForConversion = 4500;

        uint256 depositsRemained = maxDeposits;
        console.log("Simulation started");
        console.log(block.timestamp);
        console.log(block.number);

        uint256 randomAmount;

        // ** First deposit to allow swapping
        approve_actor(alice.addr);
        deposit(1000 ether, alice.addr);

        save_pool_state();

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);

        for (uint i = 0; i < numberOfSwaps; i++) {
            // **  Always do swaps
            {
                randomAmount = random(10) * 1e18;
                bool zeroForOne = (random(2) == 1);
                bool _in = (random(2) == 1);

                // Now will adjust amount if it's USDC goes In
                if ((zeroForOne && _in) || (!zeroForOne && !_in)) {
                    console.log("> randomAmount before", randomAmount);
                    randomAmount = (randomAmount * expectedPoolPriceForConversion) / 1e12;
                } else {
                    console.log("> randomAmount", randomAmount);
                }

                swap(randomAmount, zeroForOne, _in);
            }

            save_pool_state();

            // ** Do random deposits
            if (depositsRemained > 0) {
                randomAmount = random(100);
                if (randomAmount <= 20) {
                    randomAmount = random(10);
                    address actor = getRandomAddress();
                    deposit(randomAmount * 1e18, actor);
                    save_pool_state();
                    depositsRemained--;
                }
            }

            // ** Roll block after each iteration
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);
        }

        // withdraw(hook
    }

    function swap(uint256 amount, bool zeroForOne, bool _in) internal {
        console.log(">> do swap", amount, zeroForOne, _in);
        int256 delta0;
        int256 delta1;
        int256 delta0c;
        int256 delta1c;
        if (zeroForOne) {
            // USDC => WETH
            if (_in) {
                (delta0, delta1) = __swap(true, -int256(amount), key);
                (delta0c, delta1c) = __swap(true, -int256(amount), keyControl);
            } else {
                (delta0, delta1) = __swap(true, int256(amount), key);
                (delta0c, delta1c) = __swap(true, int256(amount), keyControl);
            }
        } else {
            // WETH => USDC
            if (_in) {
                (delta0, delta1) = __swap(false, -int256(amount), key);
                (delta0c, delta1c) = __swap(false, -int256(amount), keyControl);
            } else {
                (delta0, delta1) = __swap(false, int256(amount), key);
                (delta0c, delta1c) = __swap(false, int256(amount), keyControl);
            }
        }

        save_swap_data(amount, zeroForOne, _in, delta0, delta1, delta0c, delta1c);
    }

    function deposit(uint256 amount, address actor) internal {
        console.log(">> do deposit:", actor, amount);
        vm.startPrank(actor);

        uint256 balanceWETHcontrol;
        uint256 balanceUSDCcontrol;
        uint256 delSharesControl;

        {
            deal(address(WETH), actor, amount);
            deal(address(USDC), actor, amount / 1e8); // should be 1e12 but gor 4 zeros to be sure
            delSharesControl = hookControl.balanceOf(actor);
            hookControl.deposit(amount);
            balanceWETHcontrol = amount - WETH.balanceOf(actor);
            balanceUSDCcontrol = amount / 1e8 - USDC.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));

            delSharesControl = hookControl.balanceOf(actor) - delSharesControl;
        }

        uint256 balanceWETH;
        uint256 delShares;
        {
            deal(address(WETH), actor, amount);
            delShares = hook.balanceOf(actor);
            hook.deposit(actor, amount);
            balanceWETH = amount - WETH.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));

            delShares = hook.balanceOf(actor) - delShares;
        }

        save_deposit_data(
            amount,
            actor,
            balanceWETH,
            balanceWETHcontrol,
            balanceUSDCcontrol,
            delShares,
            delSharesControl
        );
        vm.stopPrank();
    }

    function withdraw(uint256 shares1, uint256 shares2, address actor) internal {
        console.log(">> do withdraw:", actor, shares1, shares2);
        vm.startPrank(actor);

        uint256 balanceWETHcontrol;
        uint256 balanceUSDCcontrol;

        {
            uint256 sharesBefore = hookControl.balanceOf(actor);
            hookControl.withdraw(shares2);
            assertEq(sharesBefore - hookControl.balanceOf(actor), shares2);

            balanceWETHcontrol = WETH.balanceOf(actor);
            balanceUSDCcontrol = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));
        }

        uint256 balanceWETH;
        uint256 balanceUSDC;
        {
            uint256 sharesBefore = hookControl.balanceOf(actor);
            hook.withdraw(actor, shares1);
            assertEq(sharesBefore - hookControl.balanceOf(actor), shares1);

            balanceWETH = WETH.balanceOf(actor);
            balanceUSDC = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));
        }

        save_withdraw_data(shares1, shares2, actor, balanceWETH, balanceUSDC, balanceWETHcontrol, balanceUSDCcontrol);
        vm.stopPrank();
    }
}
