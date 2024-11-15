// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {ALM} from "@src/ALM.sol";
import {ALMControl} from "@test/core/ALMControl.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {MorphoLendingAdapter} from "@src/core/MorphoLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ALMSimulationTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    ALMControl hookControl;
    PoolKey keyControl;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        clear_snapshots();

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

    uint256 maxDepositors = 3;
    uint256 maxDeposits = 0;
    uint256 numberOfSwaps = 10;
    uint256 expectedPoolPriceForConversion = 4500;

    function test_simulation_start() public {
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

        withdraw(hook
    }

    function save_pool_state() internal {
        uint128 liquidity = hook.liquidity();
        uint160 sqrtPriceX96 = hook.sqrtPriceCurrent();
        int24 tickLower = hook.tickLower();
        int24 tickUpper = hook.tickUpper();
        uint256 borrowed = lendingAdapter.getBorrowed();
        uint256 supplied = lendingAdapter.getSupplied();
        uint256 collateral = lendingAdapter.getCollateral();
        uint256 tvl = hook.TVL();
        uint256 tvlControl = hookControl.TVL();
        // console.log("tvl", tvl);
        // console.log("tvlControl", tvlControl);
        uint256 sharePrice = hook.sharePrice();
        uint256 sharePriceControl = hookControl.sharePrice();

        (uint160 sqrtPriceX96Control, ) = hookControl.getTick();

        bytes memory packedData = abi.encodePacked(
            liquidity,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            borrowed,
            supplied,
            collateral,
            block.number,
            sqrtPriceX96Control,
            tvl,
            tvlControl,
            sharePrice,
            sharePriceControl
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/logState.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
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

        save_swap_data(amount, zeroForOne, _in, block.number, delta0, delta1, delta0c, delta1c);
    }

    function save_swap_data(
        uint256 amount,
        bool zeroForOne,
        bool _in,
        uint256 blockNumber,
        int256 delta0,
        int256 delta1,
        int256 delta0c,
        int256 delta1c
    ) internal {
        bytes memory packedData = abi.encodePacked(
            amount,
            zeroForOne,
            _in,
            blockNumber,
            delta0,
            delta1,
            delta0c,
            delta1c
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/logSwap.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function clear_snapshots() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/clear.js";
        vm.ffi(inputs);
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

    function save_deposit_data(
        uint256 amount,
        address actor,
        uint256 balanceWETH,
        uint256 balanceWETHcontrol,
        uint256 balanceUSDCcontrol,
        uint256 delShares,
        uint256 delSharesControl
    ) internal {
        bytes memory packedData = abi.encodePacked(
            amount,
            address(actor),
            block.number,
            balanceWETH,
            balanceWETHcontrol,
            balanceUSDCcontrol,
            delShares,
            delSharesControl
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/logDeposits.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function withdraw(uint256 shares1, uint256 shares2, address actor) internal {
        console.log(">> do withdraw:", actor, shares1, shares2);
        vm.startPrank(actor);

        uint256 balanceWETHcontrol;
        uint256 balanceUSDCcontrol;
        uint256 delSharesControl;

        {
            delSharesControl = hookControl.balanceOf(actor);
            hookControl.withdraw(shares2);
            balanceWETHcontrol = WETH.balanceOf(actor);
            balanceUSDCcontrol = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));

            delSharesControl = delSharesControl - hookControl.balanceOf(actor);
        }

        uint256 balanceWETH;
        uint256 balanceUSDC;
        uint256 delShares;
        {
            delShares = hook.balanceOf(actor);
            hook.withdraw(actor, shares1);
            balanceWETH = WETH.balanceOf(actor);
            balanceUSDC = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.transfer(zero.addr, WETH.balanceOf(actor));
            USDC.transfer(zero.addr, USDC.balanceOf(actor));

            delShares = delShares - hook.balanceOf(actor);
        }

        save_withdraw_data(
            shares1,
            shares2,,
            actor,
            balanceWETH,
            balanceUSDC,
            balanceWETHcontrol,
            balanceUSDCcontrol,
            delShares,
            delSharesControl
        );
        vm.stopPrank();
    }

    function save_withdraw_data(
        uint256 shares1,
        uint256 shares2,
        address actor,
        uint256 balanceWETH,
        uint256 balanceUSDC,
        uint256 balanceWETHcontrol,
        uint256 balanceUSDCcontrol,
        uint256 delShares,
        uint256 delSharesControl
    ) internal {
        bytes memory packedData = abi.encodePacked(
            shares1,
            shares2,
            address(actor),
            block.number,
            balanceWETH,
            balanceUSDC,
            balanceWETHcontrol,
            balanceUSDCcontrol,
            delShares,
            delSharesControl
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/logWithdraws.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    // -- Simulation helpers --

    function toHexString(bytes memory input) public pure returns (string memory) {
        require(input.length < type(uint256).max / 2 - 1);
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(2 * input.length + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint pos = 2;
        uint256 length = input.length;
        for (uint i = 0; i < length; ++i) {
            uint _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }

    uint256 lastGeneratedAddress = 0;

    function getRandomAddress() public returns (address) {
        uint256 offset = 100;
        uint256 _random = random(maxDepositors);
        if (_random > lastGeneratedAddress) {
            lastGeneratedAddress = lastGeneratedAddress + 1;
            address newActor = generateAddress(lastGeneratedAddress + offset);
            approve_actor(newActor);
            return newActor;
        } else return generateAddress(_random + offset);
    }

    function approve_actor(address actor) internal {
        vm.startPrank(actor);
        WETH.approve(address(hook), type(uint256).max);
        WETH.approve(address(hook), type(uint256).max);

        WETH.approve(address(hookControl), type(uint256).max);
        USDC.approve(address(hookControl), type(uint256).max);
        vm.stopPrank();
    }

    function generateAddress(uint256 seed) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
    }

    function random(uint256 randomCap) public returns (uint) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/snapshots/random.js";
        inputs[2] = toHexString(abi.encodePacked(randomCap));

        bytes memory result = vm.ffi(inputs);
        return abi.decode(result, (uint256));
    }

    // -- Helpers --

    uint160 initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228

    function init_hook() internal {
        vm.startPrank(deployer.addr);

        // MARK: Usual UniV4 hook deployment process
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("ALM.sol", abi.encode(manager), hookAddress);
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
        assertEq(hook.hookDeployer(), deployer.addr);
        // MARK END

        rebalanceAdapter = new SRebalanceAdapter();
        lendingAdapter = new MorphoLendingAdapter();

        lendingAdapter.setDepositUSDCmId(depositUSDCmId);
        lendingAdapter.setBorrowUSDCmId(borrowUSDCmId);
        lendingAdapter.addAuthorizedCaller(address(hook));
        lendingAdapter.addAuthorizedCaller(address(rebalanceAdapter));

        rebalanceAdapter.setALM(address(hook));
        rebalanceAdapter.setLendingAdapter(address(lendingAdapter));
        rebalanceAdapter.setSqrtPriceLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setTickDeltaThreshold(250);

        // MARK: Pool deployment
        PoolKey memory _key = PoolKey(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            poolFee,
            int24((poolFee / 100) * 2),
            hook
        ); // pre-compute key in order to restrict hook to this pool

        hook.setAuthorizedPool(_key);
        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hook,
            poolFee,
            initialSQRTPrice,
            ""
        );

        hook.setLendingAdapter(address(lendingAdapter));
        hook.setRebalanceAdapter(address(rebalanceAdapter));
        assertEq(hook.tickLower(), 192230 + 3000);
        assertEq(hook.tickUpper(), 192230 - 3000);
        // MARK END

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
        vm.stopPrank();
    }

    function init_control_hook() internal {
        vm.startPrank(deployer.addr);

        // MARK: Usual UniV4 hook deployment process
        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG));
        deployCodeTo("ALMControl.sol", abi.encode(manager, address(hook)), hookAddress);
        hookControl = ALMControl(hookAddress);
        vm.label(address(hookControl), "hookControl");

        // ** Pool deployment
        (keyControl, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hookControl,
            poolFee,
            initialSQRTPrice,
            ""
        );
        // MARK END

        vm.stopPrank();
    }

    function create_and_seed_morpho_markets() internal {
        address oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        modifyMockOracle(oracle, 4487851340816804029821232973); //4487 usdc for eth

        borrowUSDCmId = create_morpho_market(address(USDC), address(WETH), 915000000000000000, oracle);

        provideLiquidityToMorpho(borrowUSDCmId, 1000 ether); // Providing some ETH

        depositUSDCmId = create_morpho_market(address(USDC), address(WETH), 945000000000000000, oracle);
    }

    function presetChainlinkOracles() internal {
        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_7_DAYS_VOL),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(18446744073709563265, 60444, 1725059436, 1725059436, 18446744073709563265)
        );

        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_30_DAYS_VOL),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(18446744073709563266, 86480, 1725059412, 1725059412, 18446744073709563266)
        );
    }
}
