// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestBase} from "@test/libraries/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {ALM} from "@src/ALM.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {MorphoLendingAdapter} from "@src/core/MorphoLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

contract ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        deployFreshManagerAndRouters();

        labelTokens();
        create_and_seed_morpho_markets();
        init_hook();
        create_and_approve_accounts();

        presetChainlinkOracles();
    }

    function test_morpho_blue_markets() public {
        vm.startPrank(alice.addr);

        // ** Supply collateral
        deal(address(WETH), address(alice.addr), 1 ether);
        morpho.supplyCollateral(
            morpho.idToMarketParams(borrowUSDCmId),
            1 ether,
            alice.addr,
            ""
        );

        assertEqMorphoS(borrowUSDCmId, alice.addr, 0, 0, 1 ether);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 borrowUSDC = 4000 * 1e6;
        (, uint256 shares) = morpho.borrow(
            morpho.idToMarketParams(borrowUSDCmId),
            borrowUSDC,
            0,
            alice.addr,
            alice.addr
        );

        assertEqMorphoS(borrowUSDCmId, alice.addr, 0, shares, 1 ether);
        assertEqBalanceState(alice.addr, 0, borrowUSDC);
        vm.stopPrank();
    }

    function test_volatility_fees() public {
        assertEq(hook.getSwapFees(), 1149360638297872);
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        almId = hook.deposit(key, amountToDep, alice.addr);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), 1182773400228691521900860642689024);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 4487 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 997461875710891611, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, usdcToSwap, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep - deltaWETH);

        assertEq(hook.sqrtPriceCurrent(), 1181128917371009610520611806230478);
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 4480755527; // this should be get from quoter
        uint256 wethToGetFSwap = 1 ether;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 1 ether, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, usdcToSwapQ, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep - deltaWETH);

        assertEq(hook.sqrtPriceCurrent(), 1184420172695703616430662028218963);
    }

    function test_swap_price_down_in() public {
        uint256 wethToSwap = 1 ether;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 4475611436);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, deltaUSDC, amountToDep + wethToSwap);

        assertEq(hook.sqrtPriceCurrent(), 1184420172695703616430662028218963);
    }

    function test_swap_price_down_out() public {
        uint256 wethToSwapQ = 999755757362062341;
        uint256 usdcToGetFSwap = 4486999802;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, deltaUSDC, amountToDep + wethToSwapQ);

        assertEq(hook.sqrtPriceCurrent(), 1181127027798823685202679804768253);
    }

    // -- Helpers --

    function init_hook() internal {
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("ALM.sol", abi.encode(manager), hookAddress);
        ALM _hook = ALM(hookAddress);

        lendingAdapter = new MorphoLendingAdapter();
        lendingAdapter.setDepositUSDCmId(depositUSDCmId);
        lendingAdapter.setBorrowUSDCmId(borrowUSDCmId);
        lendingAdapter.addAuthorizedCaller(address(_hook));
        lendingAdapter.addAuthorizedCaller(address(rebalanceAdapter));

        _hook.setLendingAdapter(address(lendingAdapter));

        uint160 initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228

        rebalanceAdapter = new SRebalanceAdapter();
        rebalanceAdapter.setALM(address(_hook));
        rebalanceAdapter.setLendingAdapter(address(lendingAdapter));
        rebalanceAdapter.setSqrtPriceLastRebalance(initialSQRTPrice);

        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            _hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );

        hook = IALM(hookAddress);

        int24 deltaTick = 3000;
        hook.setBoundaries(
            initialSQRTPrice,
            192228 - deltaTick,
            192228 + deltaTick
            // 191144, // 5000 usdc for eth
            // 193376 // 4000 usdc for eth
        );

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
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
