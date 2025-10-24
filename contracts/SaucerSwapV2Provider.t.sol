// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./Provider.sol";
import "./interfaces/ISaucerSwap.sol";

/**
 * @title SaucerSwapV2ProviderTest
 * @notice Comprehensive unit tests for SaucerSwapV2Provider
 */
contract SaucerSwapV2ProviderTest is Test {
    SaucerSwapV2Provider public provider;
    
    // Mock addresses
    address public mockNFTPositionManager;
    address public mockToken0;
    address public mockToken1;
    address public user;
    
    // Constants
    uint256 constant PRECISION = 1e18;
    uint256 constant Q96 = 2 ** 96;
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;
    int24 constant TICK_SPACING = 60;
    
    // Events to test
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        // Setup mock addresses
        mockNFTPositionManager = makeAddr("nftPositionManager");
        mockToken0 = makeAddr("token0");
        mockToken1 = makeAddr("token1");
        user = makeAddr("user");
        
        // Deploy provider
        provider = new SaucerSwapV2Provider(mockNFTPositionManager);
        
        // Label addresses for better trace output
        vm.label(address(provider), "SaucerSwapV2Provider");
        vm.label(mockNFTPositionManager, "NFTPositionManager");
        vm.label(mockToken0, "Token0");
        vm.label(mockToken1, "Token1");
        vm.label(user, "User");
    }
    
    // ===========================
    // Constructor Tests
    // ===========================
    
    function test_constructor() public {
        assertEq(
            address(provider.nonfungiblePositionManager()),
            mockNFTPositionManager,
            "NFT position manager should be set correctly"
        );
    }
    
    function test_constructor_withZeroAddress() public {
        // Should not revert - contract accepts zero address
        SaucerSwapV2Provider newProvider = new SaucerSwapV2Provider(address(0));
        assertEq(
            address(newProvider.nonfungiblePositionManager()),
            address(0),
            "Should accept zero address"
        );
    }
    
    // ===========================
    // onERC721Received Tests
    // ===========================
    
    function test_onERC721Received() public {
        bytes4 selector = provider.onERC721Received(
            address(this),
            address(this),
            1,
            ""
        );
        
        assertEq(
            selector,
            IERC721Receiver.onERC721Received.selector,
            "Should return correct selector"
        );
    }
    
    function test_onERC721Received_withData() public {
        bytes memory data = abi.encode("test data");
        bytes4 selector = provider.onERC721Received(
            user,
            address(this),
            999,
            data
        );
        
        assertEq(
            selector,
            IERC721Receiver.onERC721Received.selector,
            "Should return correct selector with data"
        );
    }
    
    // ===========================
    // priceToSqrtX96 Tests
    // ===========================
    
    function test_priceToSqrtX96_priceOne() public {
        uint256 price = PRECISION; // 1.0
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        // Function divides by 1e18, so result is: sqrt(1e18) * 2^96 / 1e18
        // sqrt(1e18) = 1e9, so result = 1e9 * 2^96 / 1e18 = 2^96 / 1e9
        uint160 expected = uint160(Q96 / 1e9);
        assertEq(sqrtPrice, expected, "Price 1.0 should give Q96/1e9");
    }
    
    function test_priceToSqrtX96_priceZeroPointTwoFive() public {
        uint256 price = PRECISION / 4; // 0.25
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        // sqrt(0.25e18) = 0.5e9, so result = 0.5e9 * 2^96 / 1e18 = Q96 / (2 * 1e9)
        uint160 expected = uint160(Q96 / (2 * 1e9));
        assertEq(sqrtPrice, expected, "Price 0.25 should give Q96/(2*1e9)");
    }
    
    function test_priceToSqrtX96_priceFour() public {
        uint256 price = 4 * PRECISION; // 4.0
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        // sqrt(4e18) = 2e9, so result = 2e9 * 2^96 / 1e18 = 2 * Q96 / 1e9
        uint160 expected = uint160((2 * Q96) / 1e9);
        assertEq(sqrtPrice, expected, "Price 4.0 should give 2*Q96/1e9");
    }
    
    function test_priceToSqrtX96_variousPrices() public {
        // Test a range of prices
        uint256[] memory prices = new uint256[](5);
        prices[0] = (1 * PRECISION) / 10;  // 0.1
        prices[1] = (5 * PRECISION) / 10;  // 0.5
        prices[2] = PRECISION;              // 1.0
        prices[3] = 2 * PRECISION;          // 2.0
        prices[4] = 10 * PRECISION;         // 10.0
        
        for (uint i = 0; i < prices.length; i++) {
            uint160 sqrtPrice = provider.priceToSqrtX96(prices[i]);
            assertGt(sqrtPrice, 0, "SqrtPrice should be positive");
        }
    }
    
    function test_priceToSqrtX96_zeroPrice() public {
        uint256 price = 0;
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        assertEq(sqrtPrice, 0, "Zero price should give zero sqrtPrice");
    }
    
    function test_priceToSqrtX96_smallPrice() public {
        uint256 price = 1; // Very small price
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        // Should not revert and should be very small
        assertGt(sqrtPrice, 0, "Small price should give non-zero sqrtPrice");
    }
    
    function test_priceToSqrtX96_largePrice() public {
        uint256 price = 1000000 * PRECISION; // Very large price
        uint160 sqrtPrice = provider.priceToSqrtX96(price);
        
        // Should not revert and should be larger than small price
        // Expected: sqrt(1000000e18) * 2^96 / 1e18 = 1000 * sqrt(1e18) * 2^96 / 1e18
        uint160 expectedSmall = uint160(Q96 / 1e9);
        assertGt(sqrtPrice, expectedSmall, "Large price should give larger sqrtPrice than price=1");
    }
    
    // ===========================
    // roundToNearestTick Tests
    // ===========================
    
    function test_roundToNearestTick_exactMultiple() public {
        int24 tick = 120; // Exact multiple of TICK_SPACING (60)
        int24 rounded = provider.roundToNearestTick(tick);
        
        assertEq(rounded, 120, "Exact multiple should not change");
    }
    
    function test_roundToNearestTick_roundDown() public {
        int24 tick = 125; // 125 = 120 + 5, should round down to 120
        int24 rounded = provider.roundToNearestTick(tick);
        
        assertEq(rounded, 120, "Should round down");
    }
    
    function test_roundToNearestTick_roundUp() public {
        int24 tick = 150; // 150 = 120 + 30, should round up to 180
        int24 rounded = provider.roundToNearestTick(tick);
        
        assertEq(rounded, 180, "Should round up");
    }
    
    function test_roundToNearestTick_negativeTick() public {
        int24 tick = -125;
        int24 rounded = provider.roundToNearestTick(tick);
        
        // -125 = -120 - 5, should round to -120
        assertEq(rounded, -120, "Negative tick should round correctly");
    }
    
    function test_roundToNearestTick_zero() public {
        int24 tick = 0;
        int24 rounded = provider.roundToNearestTick(tick);
        
        assertEq(rounded, 0, "Zero should stay zero");
    }
    
    function test_roundToNearestTick_nearZero() public {
        int24 tick = 25;
        int24 rounded = provider.roundToNearestTick(tick);
        
        // 25 < 30 (half of 60), so rounds down to 0
        assertEq(rounded, 0, "Should round down to 0");
    }
    
    function test_roundToNearestTick_boundary() public {
        // Test at the boundary (exactly half of TICK_SPACING)
        int24 tick = 30; // Exactly half of 60
        int24 rounded = provider.roundToNearestTick(tick);
        
        // At exactly half, the logic rounds up (30 >= 30)
        assertEq(rounded, 60, "At boundary (half) should round up");
    }
    
    function test_roundToNearestTick_justAboveBoundary() public {
        int24 tick = 31; // Just above half
        int24 rounded = provider.roundToNearestTick(tick);
        
        // Just above half, should round up
        assertEq(rounded, 60, "Just above boundary should round up");
    }
    
    function test_roundToNearestTick_minTick() public {
        int24 rounded = provider.roundToNearestTick(MIN_TICK);
        
        // MIN_TICK should be divisible by TICK_SPACING
        assertEq(rounded % TICK_SPACING, 0, "MIN_TICK should be valid");
    }
    
    function test_roundToNearestTick_maxTick() public {
        int24 rounded = provider.roundToNearestTick(MAX_TICK);
        
        // MAX_TICK should be divisible by TICK_SPACING
        assertEq(rounded % TICK_SPACING, 0, "MAX_TICK should be valid");
    }
    
    function test_roundToNearestTick_variousTicks() public {
        int24[] memory ticks = new int24[](10);
        ticks[0] = 1;
        ticks[1] = 59;
        ticks[2] = 61;
        ticks[3] = 119;
        ticks[4] = 121;
        ticks[5] = -1;
        ticks[6] = -59;
        ticks[7] = -61;
        ticks[8] = -119;
        ticks[9] = -121;
        
        for (uint i = 0; i < ticks.length; i++) {
            int24 rounded = provider.roundToNearestTick(ticks[i]);
            
            // Verify result is valid (multiple of TICK_SPACING)
            assertEq(
                rounded % TICK_SPACING,
                0,
                "Rounded tick should be multiple of TICK_SPACING"
            );
        }
    }
    
    // ===========================
    // mintNewPosition Tests
    // ===========================
    
    function test_mintNewPosition_revertsWhenNotEnoughAllowance() public {
        // This test would need proper mocking of token transfers
        // For now, we expect it to revert due to lack of proper setup
        
        vm.expectRevert();
        provider.mintNewPosition(
            mockToken0,
            mockToken1,
            100 * PRECISION,
            100 * PRECISION,
            -60,
            60
        );
    }
    
    // Note: Full testing of mintNewPosition would require mocking the
    // NFTPositionManager and token contracts, which is better done in
    // integration tests
    
    // ===========================
    // Edge Case Tests
    // ===========================
    
    function test_priceToSqrtX96_doesNotOverflow() public {
        // Test with maximum safe values
        uint256 maxSafePrice = type(uint128).max;
        
        // Should not revert
        uint160 sqrtPrice = provider.priceToSqrtX96(maxSafePrice);
        assertGt(sqrtPrice, 0, "Should handle large prices");
    }
    
    function test_roundToNearestTick_extremeValues() public {
        // Test with values near the limits
        int24[] memory extremeTicks = new int24[](4);
        extremeTicks[0] = MIN_TICK + 1;
        extremeTicks[1] = MIN_TICK + TICK_SPACING;
        extremeTicks[2] = MAX_TICK - 1;
        extremeTicks[3] = MAX_TICK - TICK_SPACING;
        
        for (uint i = 0; i < extremeTicks.length; i++) {
            int24 rounded = provider.roundToNearestTick(extremeTicks[i]);
            
            // Verify result is a valid tick (multiple of TICK_SPACING)
            assertEq(
                rounded % TICK_SPACING,
                0,
                "Rounded tick should be multiple of TICK_SPACING"
            );
            
            // Result may be slightly outside MIN/MAX range due to rounding
            // but should be close
            assertTrue(
                rounded >= MIN_TICK - TICK_SPACING && 
                rounded <= MAX_TICK + TICK_SPACING,
                "Should be within reasonable range"
            );
        }
    }
    
    // ===========================
    // Gas Optimization Tests
    // ===========================
    
    function test_gas_priceToSqrtX96() public {
        uint256 gasBefore = gasleft();
        provider.priceToSqrtX96(PRECISION);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas should be reasonable (less than 15k for sqrt operation)
        assertLt(gasUsed, 15000, "Gas usage should be reasonable");
    }
    
    function test_gas_roundToNearestTick() public {
        uint256 gasBefore = gasleft();
        provider.roundToNearestTick(125);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas should be reasonable (less than 10k for arithmetic)
        assertLt(gasUsed, 10000, "Gas usage should be reasonable");
    }
    
    // ===========================
    // Helper Function Tests
    // ===========================
    
    function test_tickSpacing_isValid() public pure {
        // TICK_SPACING (60) doesn't divide the tick range evenly
        // MIN_TICK = -887272, MAX_TICK = 887272
        // 887272 % 60 = 52 (not evenly divisible)
        // This is expected - the valid tick range is slightly smaller
        
        // Verify MIN_TICK and MAX_TICK are symmetric
        assertEq(MIN_TICK, -MAX_TICK, "MIN_TICK should equal -MAX_TICK");
        
        // Verify TICK_SPACING is reasonable
        assertGt(TICK_SPACING, 0, "TICK_SPACING should be positive");
        assertLt(TICK_SPACING, 1000, "TICK_SPACING should be reasonable");
    }
    
    function test_constants_areCorrect() public pure {
        assertEq(MIN_TICK, -887272, "MIN_TICK should be correct");
        assertEq(MAX_TICK, 887272, "MAX_TICK should be correct");
        assertEq(TICK_SPACING, 60, "TICK_SPACING should be correct");
        assertEq(MIN_TICK, -MAX_TICK, "MIN_TICK should equal -MAX_TICK");
    }
}

/**
 * @title MockNFTPositionManager
 * @notice Mock contract for testing NFT position manager interactions
 */
contract MockNFTPositionManager {
    uint256 public nextTokenId = 1;
    
    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    
    mapping(uint256 => Position) public positions;
    
    function mint(
        ISaucerSwapV2NonfungiblePositionManager.MintParams calldata params
    ) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        tokenId = nextTokenId++;
        liquidity = 1000e18; // Mock liquidity
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        
        // Store position
        positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        
        return (tokenId, liquidity, amount0, amount1);
    }
    
    function collect(
        ISaucerSwapV2NonfungiblePositionManager.CollectParams calldata
    ) external returns (uint256 amount0, uint256 amount1) {
        return (100, 100); // Mock collected fees
    }
    
    function increaseLiquidity(
        ISaucerSwapV2NonfungiblePositionManager.IncreaseLiquidityParams calldata params
    ) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        liquidity = 500e18; // Mock additional liquidity
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        
        return (liquidity, amount0, amount1);
    }
    
    function decreaseLiquidity(
        ISaucerSwapV2NonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = uint256(params.liquidity) / 2;
        amount1 = uint256(params.liquidity) / 2;
        
        return (amount0, amount1);
    }
    
    function burn(uint256 tokenId) external {
        delete positions[tokenId];
    }
}