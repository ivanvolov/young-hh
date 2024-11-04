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
    uint256 numberOfSwaps = 1;

    function test_simulation_start() public {
        console.log("Simulation started");
        console.log(block.timestamp);
        console.log(block.number);

        uint256 randomAmount;

        // ** First deposit to allow swapping
        approve_actor(alice.addr);
        deposit(1000 ether, alice.addr);

        for (uint i = 0; i < numberOfSwaps; i++) {
            // **  Always do swaps
            {
                randomAmount = random(10);
                bool zeroForOne = (random(2) == 1);
                bool _in = (random(2) == 1);

                // Perform the swap with the random amount and flags
                swap(randomAmount * 1e18, zeroForOne, _in);
            }

            // ** Do random deposits
            randomAmount = random(100);
            if (randomAmount <= 20) {
                randomAmount = random(10);
                deposit(randomAmount * 1e18, getRandomAddress());
            }

            // ** Roll block after each iteration
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);
        }
    }

    function swap(uint256 amount, bool zeroForOne, bool _in) internal {
        //TODO: maybe make here all in out cases sometimes
        if (zeroForOne == true && _in == true) _in = false;
        if (zeroForOne == false && _in == false) _in = true;

        console.log(">> do swap", amount, zeroForOne, _in);
        if (zeroForOne) {
            // USDC => WETH
            if (_in) {
                _swap(true, -int256(amount), key);
                // _swap(true, -int256(amount), keyControl);
            } else {
                _swap(true, int256(amount), key);
                // _swap(true, int256(amount), keyControl);
            }
        } else {
            // WETH => USDC
            if (_in) {
                _swap(false, -int256(amount), key);
                // _swap(false, -int256(amount), keyControl);
            } else {
                _swap(false, int256(amount), key);
                // _swap(false, int256(amount), keyControl);
            }
        }

        save_swap_data(amount, zeroForOne, _in, block.number);
    }

    function save_swap_data(
        uint256 amount,
        bool zeroForOne,
        bool _in,
        uint256 blockNumber
    ) internal {
        bytes memory packedData = abi.encodePacked(
            amount,
            zeroForOne,
            _in,
            blockNumber
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

        {
            deal(address(WETH), actor, amount);
            vm.prank(actor);
            hook.deposit(actor, amount);
        }

        // {
        //     uint128 _liquidity = ALMMathLib.getLiquidityFromAmount1SqrtPriceX96(
        //         ALMMathLib.getSqrtPriceAtTick(hook.tickUpper()),
        //         hook.sqrtPriceCurrent(),
        //         amount
        //     );
        //     (uint256 amount0, uint256 amount1) = ALMMathLib
        //         .getAmountsFromLiquiditySqrtPriceX96(
        //             hook.sqrtPriceCurrent(),
        //             ALMMathLib.getSqrtPriceAtTick(hook.tickUpper()),
        //             ALMMathLib.getSqrtPriceAtTick(hook.tickLower()),
        //             _liquidity
        //         );

        //     console.log("> amount0", amount0);
        //     console.log("> amount1", amount1);
        //     deal(address(USDC), actor, amount0 + 100);
        //     deal(address(WETH), actor, amount1 + 100);

        //     console.log(
        //         "> modifyLiquidityRouter",
        //         address(modifyLiquidityRouter)
        //     );

        //     console.log(address(this));
        //     console.log(address(manager));
        //     console.log(address(USDC));

        //     // deployMintAndApprove2Currencies();

        //     // vm.prank(actor);
        //     modifyLiquidityRouter.modifyLiquidity(
        //         keyControl,
        //         IPoolManager.ModifyLiquidityParams({
        //             tickLower: hook.tickUpper(),
        //             tickUpper: hook.tickLower(),
        //             liquidityDelta: int256(uint256(_liquidity)),
        //             salt: bytes32(0)
        //         }),
        //         ""
        //     );
        // }

        // vm.prank(actor);
        // WETH.transfer(deployer.addr, WETH.balanceOf(actor));
    }

    // -- Simulation helpers --

    function toHexString(
        bytes memory input
    ) public pure returns (string memory) {
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

    function random(uint256 randomCap) public view returns (uint) {
        uint randomHash = uint(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)
            )
        );
        return (randomHash % randomCap) + 1;
    }

    // -- Helpers --

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
        initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228
        rebalanceAdapter.setSqrtPriceLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setTickDeltaThreshold(250);

        // MARK: Pool deployment
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
        hook.setAuthorizedPool(key);
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
        deployCodeTo("ALMControl.sol", abi.encode(manager), hookAddress);
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

        borrowUSDCmId = create_morpho_market(
            address(USDC),
            address(WETH),
            915000000000000000,
            oracle
        );

        provideLiquidityToMorpho(borrowUSDCmId, 1000 ether); // Providing some ETH

        depositUSDCmId = create_morpho_market(
            address(USDC),
            address(WETH),
            945000000000000000,
            oracle
        );
    }

    function presetChainlinkOracles() internal {
        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_7_DAYS_VOL),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                18446744073709563265,
                60444,
                1725059436,
                1725059436,
                18446744073709563265
            )
        );

        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_30_DAYS_VOL),
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                18446744073709563266,
                86480,
                1725059412,
                1725059412,
                18446744073709563266
            )
        );
    }
}
