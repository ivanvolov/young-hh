// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

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

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
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
    }

    function test_simulation_start() public {}

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

        // ** Pool deployment
        (key, ) = initPool(
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
