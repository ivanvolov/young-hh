// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MarketParamsLib} from "@forks/morpho/MarketParamsLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";

abstract contract ALMTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;

    IALM hook;

    TestERC20 USDC;
    TestERC20 WETH;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;
    TestAccount alice;
    TestAccount swapper;

    HookEnabledSwapRouter router;
    Id bWETHmId;
    Id bUSDCmId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    uint256 almId;

    function labelTokens() public {
        WETH = TestERC20(ALMBaseLib.WETH);
        vm.label(address(WETH), "WETH");
        USDC = TestERC20(ALMBaseLib.USDC);
        vm.label(address(USDC), "USDC");
        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        vm.startPrank(alice.addr);
        USDC.approve(address(hook), type(uint256).max);
        WETH.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        USDC.approve(address(router), type(uint256).max);
        WETH.approve(address(router), type(uint256).max);
        USDC.approve(address(swapRouter), type(uint256).max);
        WETH.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapWETH_USDC_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
                false, // WETH -> USDC
                int256(amountOut),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
    }

    function swapUSDC_WETH_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
                true, // USDC -> WETH
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
    }

    // -- Uniswap V3 -- //

    function getETH_USDCPriceV3() public view returns (uint256) {
        return
            ALMBaseLib.getV3PoolPrice(
                0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
            );
    }

    // -- Morpho -- //

    function create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        address oracle,
        uint256 oracleNewPrice
    ) internal returns (Id) {
        MarketParams memory marketParams = MarketParams(
            loanToken,
            collateralToken,
            oracle,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, // We have only 1 irm in morpho so we can use this address
            lltv
        );

        modifyMockOracle(oracle, oracleNewPrice);

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);
        return MarketParamsLib.id(marketParams);
    }

    function modifyMockOracle(
        address oracle,
        uint256 newPrice
    ) internal returns (IChainlinkOracle iface) {
        //NOTICE: https://github.com/morpho-org/morpho-blue-oracles
        iface = IChainlinkOracle(oracle);
        address vault = address(IChainlinkOracle(oracle).VAULT());
        uint256 conversionSample = IChainlinkOracle(oracle)
            .VAULT_CONVERSION_SAMPLE();
        address baseFeed1 = address(IChainlinkOracle(oracle).BASE_FEED_1());
        address baseFeed2 = address(IChainlinkOracle(oracle).BASE_FEED_2());
        address quoteFeed1 = address(IChainlinkOracle(oracle).QUOTE_FEED_1());
        address quoteFeed2 = address(IChainlinkOracle(oracle).QUOTE_FEED_2());
        uint256 scaleFactor = IChainlinkOracle(oracle).SCALE_FACTOR();

        vm.mockCall(
            oracle,
            abi.encodeWithSelector(iface.price.selector),
            abi.encode(newPrice)
        );
        assertEq(iface.price(), newPrice);
        assertEq(address(iface.VAULT()), vault);
        assertEq(iface.VAULT_CONVERSION_SAMPLE(), conversionSample);
        assertEq(address(iface.BASE_FEED_1()), baseFeed1);
        assertEq(address(iface.BASE_FEED_2()), baseFeed2);
        assertEq(address(iface.QUOTE_FEED_1()), quoteFeed1);
        assertEq(address(iface.QUOTE_FEED_2()), quoteFeed2);
        assertEq(iface.SCALE_FACTOR(), scaleFactor);

        return iface;
    }

    function provideLiquidityToMorpho(Id marketId, uint256 amount) internal {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        console.log(">>", marketParams.loanToken);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        TestERC20(marketParams.loanToken).approve(
            address(morpho),
            type(uint256).max
        );
        (, uint256 shares) = morpho.supply(
            marketParams,
            amount,
            0,
            morphoLpProvider.addr,
            ""
        );

        assertEqMorphoState(marketId, morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }

    // -- Custom assertions -- //

    function assertALMV4PositionLiquidity(
        uint256 _almId,
        uint256 _liquidity
    ) public view {
        (uint128 liquidity, , ) = hook.getALMPosition(key, _almId);
        assertApproxEqAbs(liquidity, _liquidity, 10, "liquidity not equal");
    }

    function assertEqMorphoState(
        Id marketId,
        address owner,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);
        assertApproxEqAbs(
            p.supplyShares,
            _supplyShares,
            10,
            "supply shares not equal"
        );
        assertApproxEqAbs(
            p.borrowShares,
            _borrowShares,
            10,
            "borrow shares not equal"
        );
        assertApproxEqAbs(
            p.collateral,
            _collateral,
            10000,
            "collateral not equal"
        );
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWETH,
        uint256 _balanceUSDC
    ) public view {
        assertEqBalanceState(owner, _balanceWETH, _balanceUSDC, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWETH,
        uint256 _balanceUSDC,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            WETH.balanceOf(owner),
            _balanceWETH,
            10,
            "Balance WETH not equal"
        );
        assertApproxEqAbs(
            USDC.balanceOf(owner),
            _balanceUSDC,
            10,
            "Balance USDC not equal"
        );
        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
