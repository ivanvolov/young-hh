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
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {MorphoLendingAdapter} from "@src/core/MorphoLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

contract ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        create_and_seed_morpho_markets();
        init_hook();
        approve_accounts();
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
        almId = hook.deposit(amountToDep, alice.addr);

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
        assertApproxEqAbs(deltaWETH, 997462731958539338, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, usdcToSwap, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep - deltaWETH);

        assertEq(hook.sqrtPriceCurrent(), 1181129931283302189208560775441188);
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 4480759374; // this should be get from quoter
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

        assertEq(hook.sqrtPriceCurrent(), 1184419155958983279206311649470597);
    }

    function test_swap_price_down_in() public {
        uint256 wethToSwap = 1 ether;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 4475615278);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, deltaUSDC, amountToDep + wethToSwap);

        assertEq(hook.sqrtPriceCurrent(), 1184419155958983279206311649470597);
    }

    function test_swap_price_down_out() public {
        uint256 wethToSwapQ = 999756616564962687;
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

        assertEq(hook.sqrtPriceCurrent(), 1181128042874516412352801494904842);
    }

    function test_swap_price_down_rebalance() public {
        test_swap_price_down_in();

        vm.expectRevert();
        rebalanceAdapter.rebalance();

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance();

        // Swap some more
        uint256 wethToSwap = 10 * 1e18;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        swapWETH_USDC_In(wethToSwap);

        assertEq(hook.sqrtPriceCurrent(), 1200876713261900852260821717286331);

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 48557065456, 110999999999999999712);

        assertEq(rebalanceAdapter.sqrtPriceLastRebalance(), initialSQRTPrice);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance();

        assertEq(
            rebalanceAdapter.sqrtPriceLastRebalance(),
            1200876713261900852260821717286331
        );

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, 98346744659021088613);
    }

    function test_lending_adapter_migration() public {
        test_swap_price_down_rebalance();
        // This is better to do after rebalance

        vm.startPrank(deployer.addr);
        ILendingAdapter newAdapter = new MorphoLendingAdapter();
        newAdapter.setDepositUSDCmId(depositUSDCmId);
        newAdapter.setBorrowUSDCmId(borrowUSDCmId);
        newAdapter.addAuthorizedCaller(address(hook));
        newAdapter.addAuthorizedCaller(address(rebalanceAdapter));
        newAdapter.addAuthorizedCaller(alice.addr);

        rebalanceAdapter.setLendingAdapter(address(newAdapter));
        hook.setLendingAdapter(address(newAdapter));

        lendingAdapter.addAuthorizedCaller(address(alice.addr));
        vm.stopPrank();

        uint256 collateral = lendingAdapter.getCollateral();
        vm.startPrank(alice.addr);
        lendingAdapter.removeCollateral(collateral);

        WETH.approve(address(newAdapter), type(uint256).max);
        newAdapter.addCollateral(collateral);
        vm.stopPrank();

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, address(newAdapter), 0, 0, 0);
        assertEqMorphoA(
            borrowUSDCmId,
            address(newAdapter),
            0,
            0,
            98346744659021088613
        );
    }

    // -- Helpers --

    function init_hook() internal {
        vm.startPrank(deployer.addr);
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

        rebalanceAdapter = new SRebalanceAdapter();
        lendingAdapter = new MorphoLendingAdapter();

        lendingAdapter.setDepositUSDCmId(depositUSDCmId);
        lendingAdapter.setBorrowUSDCmId(borrowUSDCmId);
        lendingAdapter.addAuthorizedCaller(address(hook));
        lendingAdapter.addAuthorizedCaller(address(rebalanceAdapter));

        initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228
        rebalanceAdapter.setALM(address(hook));
        rebalanceAdapter.setLendingAdapter(address(lendingAdapter));
        rebalanceAdapter.setSqrtPriceLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setTickDeltaThreshold(300);

        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hook,
            200,
            initialSQRTPrice,
            ""
        );

        hook.setLendingAdapter(address(lendingAdapter));
        assertEq(hook.tickLower(), 192230 + 3000);
        assertEq(hook.tickUpper(), 192230 - 3000);
        hook.setAuthorizedPool(key);

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
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
