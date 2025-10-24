// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./Swapper.sol";
import "./interfaces/ISaucerSwap.sol";

/**
 * @title SaucerSwapperTest
 * @notice Comprehensive unit tests for SaucerSwapper contract
 */
contract SaucerSwapperTest is Test {
    SaucerSwapper public swapper;
    
    // Mock addresses
    address public mockRouter;
    address public mockFactory;
    address public mockQuoter;
    address public mockToken0;
    address public mockToken1;
    address public mockWHBAR;
    address public mockPool;
    address public user;
    
    // Constants
    uint256 constant PRECISION = 1e18;
    uint24 constant DEFAULT_FEE = 3000;
    uint256 constant SLIPPAGE_TOLERANCE = 100; // 1%
    uint256 constant BASIS_POINTS = 10000;
    
    // Events
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event RouterUpdated(address indexed newRouter);
    event FactoryUpdated(address indexed newFactory);
    
    function setUp() public {
        // Setup mock addresses
        mockRouter = makeAddr("router");
        mockFactory = makeAddr("factory");
        mockQuoter = makeAddr("quoter");
        mockToken0 = makeAddr("token0");
        mockToken1 = makeAddr("token1");
        mockWHBAR = makeAddr("WHBAR");
        mockPool = makeAddr("pool");
        user = makeAddr("user");
        
        // Mock WHBAR call
        vm.mockCall(
            mockRouter,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(mockWHBAR)
        );
        
        // Deploy swapper
        swapper = new SaucerSwapper(mockRouter, mockFactory, mockQuoter);
        
        // Label addresses
        vm.label(address(swapper), "SaucerSwapper");
        vm.label(mockRouter, "Router");
        vm.label(mockFactory, "Factory");
        vm.label(mockQuoter, "Quoter");
        vm.label(mockToken0, "Token0");
        vm.label(mockToken1, "Token1");
        vm.label(mockWHBAR, "WHBAR");
        vm.label(user, "User");
    }
    
    // ===========================
    // Constructor Tests
    // ===========================
    
    function test_constructor() public {
        assertEq(
            address(swapper.saucerSwapRouter()),
            mockRouter,
            "Router should be set"
        );
        assertEq(
            address(swapper.saucerSwapFactory()),
            mockFactory,
            "Factory should be set"
        );
        assertEq(
            address(swapper.saucerSwapQuoter()),
            mockQuoter,
            "Quoter should be set"
        );
        assertEq(
            swapper.WHBAR(),
            mockWHBAR,
            "WHBAR should be retrieved from router"
        );
    }
    
    function test_constructor_withZeroQuoter() public {
        vm.mockCall(
            mockRouter,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(mockWHBAR)
        );
        
        SaucerSwapper newSwapper = new SaucerSwapper(
            mockRouter,
            mockFactory,
            address(0)
        );
        
        assertEq(
            address(newSwapper.saucerSwapQuoter()),
            address(0),
            "Quoter can be zero"
        );
    }
    
    function test_constructor_revertsWithZeroRouter() public {
        vm.expectRevert("Invalid router address");
        new SaucerSwapper(address(0), mockFactory, mockQuoter);
    }
    
    function test_constructor_revertsWithZeroFactory() public {
        vm.expectRevert("Invalid factory address");
        new SaucerSwapper(mockRouter, address(0), mockQuoter);
    }
    
    function test_constructor_revertsIfWHBARIsZero() public {
        // Mock WHBAR as zero
        vm.mockCall(
            mockRouter,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(address(0))
        );
        
        vm.expectRevert("Failed to get WHBAR address");
        new SaucerSwapper(mockRouter, mockFactory, mockQuoter);
    }
    
    // ===========================
    // Constants Tests
    // ===========================
    
    function test_constants() public {
        assertEq(swapper.DEFAULT_FEE(), 3000, "Default fee should be 0.3%");
        assertEq(
            swapper.SLIPPAGE_TOLERANCE(),
            100,
            "Slippage tolerance should be 1%"
        );
        assertEq(swapper.BASIS_POINTS(), 10000, "Basis points should be 10000");
    }
    
    // ===========================
    // getPool Tests
    // ===========================
    
    function test_getPool_returnsPoolAddress() public {
        // Mock factory call
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(mockPool)
        );
        
        address pool = swapper.getPool(mockToken0, mockToken1, DEFAULT_FEE);
        
        assertEq(pool, mockPool, "Should return pool address");
    }
    
    function test_getPool_returnsZeroIfNoPool() public {
        // Mock factory returning zero address
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(address(0))
        );
        
        address pool = swapper.getPool(mockToken0, mockToken1, DEFAULT_FEE);
        
        assertEq(pool, address(0), "Should return zero if pool doesn't exist");
    }
    
    function test_getPool_differentFeeTiers() public {
        uint24[] memory fees = new uint24[](3);
        fees[0] = 500;   // 0.05%
        fees[1] = 3000;  // 0.3%
        fees[2] = 10000; // 1%
        
        for (uint i = 0; i < fees.length; i++) {
            vm.mockCall(
                mockFactory,
                abi.encodeWithSelector(
                    ISaucerSwapV2Factory.getPool.selector,
                    mockToken0,
                    mockToken1,
                    fees[i]
                ),
                abi.encode(mockPool)
            );
            
            address pool = swapper.getPool(mockToken0, mockToken1, fees[i]);
            assertEq(pool, mockPool, "Should work for different fee tiers");
        }
    }
    
    // ===========================
    // poolExists Tests
    // ===========================
    
    function test_poolExists_returnsTrue() public {
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(mockPool)
        );
        
        bool exists = swapper.poolExists(mockToken0, mockToken1, DEFAULT_FEE);
        
        assertTrue(exists, "Should return true if pool exists");
    }
    
    function test_poolExists_returnsFalse() public {
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(address(0))
        );
        
        bool exists = swapper.poolExists(mockToken0, mockToken1, DEFAULT_FEE);
        
        assertFalse(exists, "Should return false if pool doesn't exist");
    }
    
    // ===========================
    // getAvailableFeeTiers Tests
    // ===========================
    
    function test_getAvailableFeeTiers_allExist() public {
        // Mock all three fee tiers as existing
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                500
            ),
            abi.encode(mockPool)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                3000
            ),
            abi.encode(mockPool)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                10000
            ),
            abi.encode(mockPool)
        );
        
        uint24[] memory fees = swapper.getAvailableFeeTiers(mockToken0, mockToken1);
        
        assertEq(fees.length, 3, "Should return all 3 fee tiers");
        assertEq(fees[0], 500, "First tier should be 0.05%");
        assertEq(fees[1], 3000, "Second tier should be 0.3%");
        assertEq(fees[2], 10000, "Third tier should be 1%");
    }
    
    function test_getAvailableFeeTiers_someExist() public {
        // Mock only 0.3% tier as existing
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                500
            ),
            abi.encode(address(0))
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                3000
            ),
            abi.encode(mockPool)
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                10000
            ),
            abi.encode(address(0))
        );
        
        uint24[] memory fees = swapper.getAvailableFeeTiers(mockToken0, mockToken1);
        
        assertEq(fees.length, 1, "Should return only existing tiers");
        assertEq(fees[0], 3000, "Should be 0.3% tier");
    }
    
    function test_getAvailableFeeTiers_noneExist() public {
        // Mock all tiers as non-existing
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                500
            ),
            abi.encode(address(0))
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                3000
            ),
            abi.encode(address(0))
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                10000
            ),
            abi.encode(address(0))
        );
        
        uint24[] memory fees = swapper.getAvailableFeeTiers(mockToken0, mockToken1);
        
        assertEq(fees.length, 0, "Should return empty array");
    }
    
    // ===========================
    // updateRouter Tests
    // ===========================
    
    function test_updateRouter_success() public {
        address newRouter = makeAddr("newRouter");
        address newWHBAR = makeAddr("newWHBAR");
        
        vm.mockCall(
            newRouter,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(newWHBAR)
        );
        
        vm.expectEmit(true, false, false, false);
        emit RouterUpdated(newRouter);
        
        swapper.updateRouter(newRouter);
        
        assertEq(address(swapper.saucerSwapRouter()), newRouter);
        assertEq(swapper.WHBAR(), newWHBAR);
    }
    
    function test_updateRouter_revertsWithZeroAddress() public {
        vm.expectRevert("Invalid router");
        swapper.updateRouter(address(0));
    }
    
    // ===========================
    // updateFactory Tests
    // ===========================
    
    function test_updateFactory_success() public {
        address newFactory = makeAddr("newFactory");
        
        vm.expectEmit(true, false, false, false);
        emit FactoryUpdated(newFactory);
        
        swapper.updateFactory(newFactory);
        
        assertEq(address(swapper.saucerSwapFactory()), newFactory);
    }
    
    function test_updateFactory_revertsWithZeroAddress() public {
        vm.expectRevert("Invalid factory");
        swapper.updateFactory(address(0));
    }
    
    // ===========================
    // receive() Tests
    // ===========================
    
    function test_receive_acceptsHBAR() public {
        uint256 amount = 1 ether;
        
        (bool success, ) = address(swapper).call{value: amount}("");
        
        assertTrue(success, "Should accept HBAR");
        assertEq(address(swapper).balance, amount, "Balance should increase");
    }
    
    function test_receive_multiplePayments() public {
        uint256 payment1 = 1 ether;
        uint256 payment2 = 2 ether;
        
        (bool success1, ) = address(swapper).call{value: payment1}("");
        (bool success2, ) = address(swapper).call{value: payment2}("");
        
        assertTrue(success1 && success2, "Should accept multiple payments");
        assertEq(
            address(swapper).balance,
            payment1 + payment2,
            "Balance should be sum"
        );
    }
    
    // ===========================
    // Gas Tests
    // ===========================
    
    function test_gas_getPool() public {
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(mockPool)
        );
        
        uint256 gasBefore = gasleft();
        swapper.getPool(mockToken0, mockToken1, DEFAULT_FEE);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 10000, "Gas should be reasonable");
    }
    
    function test_gas_poolExists() public {
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken1,
                DEFAULT_FEE
            ),
            abi.encode(mockPool)
        );
        
        uint256 gasBefore = gasleft();
        swapper.poolExists(mockToken0, mockToken1, DEFAULT_FEE);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 12000, "Gas should be reasonable");
    }
    
    // ===========================
    // Edge Case Tests
    // ===========================
    
    function test_getPool_withSameTokens() public {
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(
                ISaucerSwapV2Factory.getPool.selector,
                mockToken0,
                mockToken0,
                DEFAULT_FEE
            ),
            abi.encode(address(0))
        );
        
        address pool = swapper.getPool(mockToken0, mockToken0, DEFAULT_FEE);
        
        // Should not revert, just return zero
        assertEq(pool, address(0), "Same tokens should return zero");
    }
    
    function test_getAvailableFeeTiers_largeGasConsumption() public {
        // This tests gas consumption for checking multiple pools
        vm.mockCall(
            mockFactory,
            abi.encodeWithSelector(ISaucerSwapV2Factory.getPool.selector),
            abi.encode(address(0))
        );
        
        uint256 gasBefore = gasleft();
        swapper.getAvailableFeeTiers(mockToken0, mockToken1);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should be reasonable even when checking 3 pools
        assertLt(gasUsed, 50000, "Gas should be acceptable");
    }
    
    function test_updateRouter_updatesWHBAR() public {
        address newRouter = makeAddr("newRouter");
        address newWHBAR = makeAddr("newWHBAR");
        
        vm.mockCall(
            newRouter,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(newWHBAR)
        );
        
        address oldWHBAR = swapper.WHBAR();
        swapper.updateRouter(newRouter);
        address updatedWHBAR = swapper.WHBAR();
        
        assertNotEq(oldWHBAR, updatedWHBAR, "WHBAR should be updated");
        assertEq(updatedWHBAR, newWHBAR, "WHBAR should match new router");
    }
    
    // ===========================
    // State Consistency Tests
    // ===========================
    
    function test_stateConsistency_multipleUpdates() public {
        address router1 = makeAddr("router1");
        address router2 = makeAddr("router2");
        address whbar1 = makeAddr("whbar1");
        address whbar2 = makeAddr("whbar2");
        
        vm.mockCall(
            router1,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(whbar1)
        );
        vm.mockCall(
            router2,
            abi.encodeWithSelector(ISaucerSwapV2Router.WHBAR.selector),
            abi.encode(whbar2)
        );
        
        swapper.updateRouter(router1);
        assertEq(swapper.WHBAR(), whbar1);
        
        swapper.updateRouter(router2);
        assertEq(swapper.WHBAR(), whbar2);
    }
    
    function test_stateConsistency_factoryIndependent() public {
        address newFactory = makeAddr("newFactory");
        address routerBefore = address(swapper.saucerSwapRouter());
        address whbarBefore = swapper.WHBAR();
        
        swapper.updateFactory(newFactory);
        
        // Router and WHBAR should remain unchanged
        assertEq(
            address(swapper.saucerSwapRouter()),
            routerBefore,
            "Router should not change"
        );
        assertEq(swapper.WHBAR(), whbarBefore, "WHBAR should not change");
    }
    
    // ===========================
    // Integration Readiness Tests
    // ===========================
    
    function test_integration_allAddressesSet() public {
        assertTrue(
            address(swapper.saucerSwapRouter()) != address(0),
            "Router should be set"
        );
        assertTrue(
            address(swapper.saucerSwapFactory()) != address(0),
            "Factory should be set"
        );
        assertTrue(swapper.WHBAR() != address(0), "WHBAR should be set");
    }
    
    function test_integration_constantsAreReasonable() public {
        assertLe(
            swapper.SLIPPAGE_TOLERANCE(),
            1000,
            "Slippage should be <= 10%"
        );
        assertGe(
            swapper.SLIPPAGE_TOLERANCE(),
            10,
            "Slippage should be >= 0.1%"
        );
        assertEq(swapper.BASIS_POINTS(), 10000, "Basis points standard");
    }
}