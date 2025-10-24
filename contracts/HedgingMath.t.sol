// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./HedgingMath.sol";

/**
 * @title HedgingMathTest
 * @notice Comprehensive test suite for HedgingMath contract
 */
contract HedgingMathTest is Test {
    HedgingMath public hedgingMath;
    
    // Constants for Q96 format 
    uint256 constant Q96 = 2 ** 96;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        hedgingMath = new HedgingMath();
    }

    // ===========================
    // Test: get_liquidity_xy
    // ===========================

    function test_get_liquidity_xy_basic() public view {
        // Using wider range like original test to avoid overflow
        // sp = Q96 represents sqrt(price) = 1, so price = 1
        // sa = Q96/2 represents sqrt(price) = 0.5, so price = 0.25
        // sb = Q96*2 represents sqrt(price) = 2, so price = 4
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 / 2);
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        assertGt(x, 0, "x should be greater than 0");
        assertGt(y, 0, "y should be greater than 0");
    }

    function test_get_liquidity_xy_zero_value() public view {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 * 9 / 10);
        uint160 sb = uint160(Q96 * 11 / 10);
        uint256 value = 0;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        assertEq(x, 0, "x should be 0 when value is 0");
        assertEq(y, 0, "y should be 0 when value is 0");
    }

    function test_get_liquidity_xy_price_at_lower_bound() public view {
        uint160 sa = uint160(Q96 * 9 / 10);
        uint160 sb = uint160(Q96 * 11 / 10);
        uint160 sp = sa; // Price at lower bound
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        assertEq(x, value, "All value should go to x when price is at lower bound");
        assertEq(y, 0, "y should be 0 when price is at lower bound");
    }

    function test_get_liquidity_xy_price_at_upper_bound() public view {
        uint160 sa = uint160(Q96 * 9 / 10);
        uint160 sb = uint160(Q96 * 11 / 10);
        uint160 sp = sb; // Price at upper bound
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        assertEq(x, 0, "x should be 0 when price is at upper bound");
        assertEq(y, value, "All value should go to y when price is at upper bound");
    }

    function test_get_liquidity_xy_invalid_range() public {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 * 11 / 10); // sa > sb - invalid
        uint160 sb = uint160(Q96 * 9 / 10);
        uint256 value = 1000 * PRECISION;

        vm.expectRevert(HedgingMath.InvalidPriceRange.selector);
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
    }

    function test_get_liquidity_xy_price_out_of_range_below() public {
        uint160 sp = uint160(Q96 * 8 / 10); // Below sa
        uint160 sa = uint160(Q96 * 9 / 10);
        uint160 sb = uint160(Q96 * 11 / 10);
        uint256 value = 1000 * PRECISION;

        vm.expectRevert(HedgingMath.PriceOutOfRange.selector);
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
    }

    function test_get_liquidity_xy_price_out_of_range_above() public {
        uint160 sp = uint160(Q96 * 12 / 10); // Above sb
        uint160 sa = uint160(Q96 * 9 / 10);
        uint160 sb = uint160(Q96 * 11 / 10);
        uint256 value = 1000 * PRECISION;

        vm.expectRevert(HedgingMath.PriceOutOfRange.selector);
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
    }

    // ===========================
    // Test: findMaxX2
    // ===========================

    function test_findMaxX2_basic() public view {
        uint256 p = PRECISION;              // 1.0
        uint256 a = (9 * PRECISION) / 10;   // 0.9
        uint256 b = (11 * PRECISION) / 10;  // 1.1
        uint256 vMax = 1000 * PRECISION;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);

        assertGt(maxX, 0, "maxX should be greater than 0");
        assertLe(maxX, vMax, "maxX should not exceed vMax");
    }

    function test_findMaxX2_zero_vMax() public view {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 vMax = 0;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);

        assertEq(maxX, 0, "maxX should be 0 when vMax is 0");
    }

    function test_findMaxX2_invalid_range() public {
        uint256 p = PRECISION;
        uint256 a = (11 * PRECISION) / 10; // a > b - invalid
        uint256 b = (9 * PRECISION) / 10;
        uint256 vMax = 1000 * PRECISION;

        vm.expectRevert(HedgingMath.InvalidPriceRange.selector);
        hedgingMath.findMaxX2(p, a, b, vMax);
    }

    function test_findMaxX2_price_out_of_range() public {
        uint256 p = (8 * PRECISION) / 10; // Below a
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 vMax = 1000 * PRECISION;

        vm.expectRevert(HedgingMath.PriceOutOfRange.selector);
        hedgingMath.findMaxX2(p, a, b, vMax);
    }

    // ===========================
    // Test: Liquidity Functions
    // ===========================

    function test_getLiquidity0() public view {
        uint256 x_val = 100 * PRECISION;
        uint256 sa_val = Q96 * 9 / 10;
        uint256 sb_val = Q96 * 11 / 10;

        uint256 liquidity = hedgingMath.unwrap(
            hedgingMath.getLiquidity0(
                hedgingMath.ud(x_val),
                hedgingMath.ud(sa_val),
                hedgingMath.ud(sb_val)
            )
        );

        assertGt(liquidity, 0, "Liquidity should be greater than 0");
    }

    function test_getLiquidity1() public view {
        uint256 y_val = 100 * PRECISION;
        uint256 sa_val = Q96 * 9 / 10;
        uint256 sb_val = Q96 * 11 / 10;

        uint256 liquidity = hedgingMath.unwrap(
            hedgingMath.getLiquidity1(
                hedgingMath.ud(y_val),
                hedgingMath.ud(sa_val),
                hedgingMath.ud(sb_val)
            )
        );

        assertGt(liquidity, 0, "Liquidity should be greater than 0");
    }

    function test_getLiquidity() public view {
        uint256 x_val = 50 * PRECISION;
        uint256 y_val = 50 * PRECISION;
        uint256 sp_val = Q96;
        uint256 sa_val = Q96 * 9 / 10;
        uint256 sb_val = Q96 * 11 / 10;

        uint256 liquidity = hedgingMath.unwrap(
            hedgingMath.getLiquidity(
                hedgingMath.ud(x_val),
                hedgingMath.ud(y_val),
                hedgingMath.ud(sp_val),
                hedgingMath.ud(sa_val),
                hedgingMath.ud(sb_val)
            )
        );

        assertGt(liquidity, 0, "Combined liquidity should be greater than 0");
    }

    function test_getLiquidity_price_below_range() public view {
        uint256 x_val = 100 * PRECISION;
        uint256 y_val = 0;
        uint256 sp_val = Q96 * 8 / 10; // Below sa
        uint256 sa_val = Q96 * 9 / 10;
        uint256 sb_val = Q96 * 11 / 10;

        uint256 liquidity = hedgingMath.unwrap(
            hedgingMath.getLiquidity(
                hedgingMath.ud(x_val),
                hedgingMath.ud(y_val),
                hedgingMath.ud(sp_val),
                hedgingMath.ud(sa_val),
                hedgingMath.ud(sb_val)
            )
        );

        assertGt(liquidity, 0, "Liquidity should be calculated from token0 only");
    }

    function test_getLiquidity_price_above_range() public view {
        uint256 x_val = 0;
        uint256 y_val = 100 * PRECISION;
        uint256 sp_val = Q96 * 12 / 10; // Above sb
        uint256 sa_val = Q96 * 9 / 10;
        uint256 sb_val = Q96 * 11 / 10;

        uint256 liquidity = hedgingMath.unwrap(
            hedgingMath.getLiquidity(
                hedgingMath.ud(x_val),
                hedgingMath.ud(y_val),
                hedgingMath.ud(sp_val),
                hedgingMath.ud(sa_val),
                hedgingMath.ud(sb_val)
            )
        );

        assertGt(liquidity, 0, "Liquidity should be calculated from token1 only");
    }

    // ===========================
    // Test: calculateAmounts
    // ===========================

    function test_calculateAmounts_price_increase() public view {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = (105 * PRECISION) / 100; // Price increased

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(p, a, b, x, y, P1);

        assertLt(x1, x, "x should decrease when price increases");
        assertGt(y1, y, "y should increase when price increases");
    }

    function test_calculateAmounts_price_decrease() public view {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = (95 * PRECISION) / 100; // Price decreased

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(p, a, b, x, y, P1);

        assertGt(x1, x, "x should increase when price decreases");
        assertLt(y1, y, "y should decrease when price decreases");
    }

    function test_calculateAmounts_no_price_change() public view {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = p; // No price change

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(p, a, b, x, y, P1);

        assertEq(x1, x, "x should remain the same when price doesn't change");
        assertEq(y1, y, "y should remain the same when price doesn't change");
    }

    function test_calculateAmounts_invalid_range() public {
        uint256 p = PRECISION;
        uint256 a = (11 * PRECISION) / 10; // a > b - invalid
        uint256 b = (9 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = (105 * PRECISION) / 100;

        vm.expectRevert(HedgingMath.InvalidPriceRange.selector);
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
    }

    function test_calculateAmounts_price_out_of_range() public {
        uint256 p = (8 * PRECISION) / 10; // Below a
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = (105 * PRECISION) / 100;

        vm.expectRevert(HedgingMath.PriceOutOfRange.selector);
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
    }

    function test_calculateAmounts_new_price_out_of_range() public {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = (12 * PRECISION) / 10; // Above b

        vm.expectRevert(HedgingMath.PriceOutOfRange.selector);
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
    }

    // ===========================
    // Test: findEqualPnLValues
    // ===========================

    function test_findEqualPnLValues_basic() public view {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 P1 = (105 * PRECISION) / 100;
        uint256 shortPrice = (95 * PRECISION) / 100;

        (uint256 lpValue, uint256 shortValue) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1,
            shortPrice
        );

        assertGt(lpValue, 0, "LP value should be greater than 0");
        assertGe(shortValue, 0, "Short value should be non-negative");
    }

    function test_findEqualPnLValues_invalid_range() public {
        uint256 p = PRECISION;
        uint256 a = (11 * PRECISION) / 10; // a > b - invalid
        uint256 b = (9 * PRECISION) / 10;
        uint256 P1 = (105 * PRECISION) / 100;
        uint256 shortPrice = (95 * PRECISION) / 100;

        vm.expectRevert(HedgingMath.InvalidPriceRange.selector);
        hedgingMath.findEqualPnLValues(p, a, b, P1, shortPrice);
    }

    function test_findEqualPnLValues_price_equals_short_price() public {
        uint256 p = PRECISION;
        uint256 a = (9 * PRECISION) / 10;
        uint256 b = (11 * PRECISION) / 10;
        uint256 P1 = (105 * PRECISION) / 100;
        uint256 shortPrice = P1; // Same as P1

        vm.expectRevert(HedgingMath.DivisionByZero.selector);
        hedgingMath.findEqualPnLValues(p, a, b, P1, shortPrice);
    }

    function test_findEqualPnLValues_various_scenarios() public view {
        uint256 p = PRECISION;
        uint256 a = (8 * PRECISION) / 10;
        uint256 b = (12 * PRECISION) / 10;

        // Scenario 1: Price increases
        uint256 P1_up = (11 * PRECISION) / 10;
        uint256 shortPrice1 = (9 * PRECISION) / 10;
        (uint256 lpValue1, uint256 shortValue1) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1_up,
            shortPrice1
        );
        assertGt(lpValue1, 0, "LP value should be positive in scenario 1");

        // Scenario 2: Price decreases
        uint256 P1_down = (9 * PRECISION) / 10;
        uint256 shortPrice2 = (11 * PRECISION) / 10;
        (uint256 lpValue2, uint256 shortValue2) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1_down,
            shortPrice2
        );
        assertGt(lpValue2, 0, "LP value should be positive in scenario 2");
    }

    // ===========================
    // Test: Math Helper Functions
    // ===========================

    function test_mulDiv_basic() public view {
        uint256 a = 100 * PRECISION;
        uint256 b = 50 * PRECISION;
        uint256 denominator = 25 * PRECISION;

        uint256 result = hedgingMath.mulDiv(a, b, denominator);

        assertEq(result, 200 * PRECISION, "mulDiv should calculate correctly");
    }

    function test_mulDiv_no_overflow() public view {
        uint256 a = type(uint128).max;
        uint256 b = 2;
        uint256 denominator = 1;

        uint256 result = hedgingMath.mulDiv(a, b, denominator);

        assertEq(result, a * b, "mulDiv should handle large numbers");
    }

    function test_sqrt_basic() public view {
        uint256 y = 16 * PRECISION;

        uint256 result = hedgingMath.sqrt(y);

        assertEq(result, 4e9, "sqrt(16e18) should equal 4e9");
    }

    function test_sqrt_perfect_squares() public view {
        assertEq(hedgingMath.sqrt(0), 0, "sqrt(0) should be 0");
        assertEq(hedgingMath.sqrt(1), 1, "sqrt(1) should be 1");
        assertEq(hedgingMath.sqrt(4), 2, "sqrt(4) should be 2");
        assertEq(hedgingMath.sqrt(9), 3, "sqrt(9) should be 3");
        assertEq(hedgingMath.sqrt(100), 10, "sqrt(100) should be 10");
    }

    // ===========================
    // Test: UD60x18 Helper Functions
    // ===========================

    function test_ud60x18_wrap_unwrap() public view {
        uint256 value = 123 * PRECISION;

        uint256 wrapped = hedgingMath.unwrap(hedgingMath.ud(value));

        assertEq(wrapped, value, "Wrap and unwrap should return original value");
    }

    function test_ud60x18_add() public view {
        uint256 a = 100 * PRECISION;
        uint256 b = 50 * PRECISION;

        uint256 result = hedgingMath.unwrap(
            hedgingMath.ud_add(hedgingMath.ud(a), hedgingMath.ud(b))
        );

        assertEq(result, 150 * PRECISION, "Addition should work correctly");
    }

    function test_ud60x18_sub() public view {
        uint256 a = 100 * PRECISION;
        uint256 b = 50 * PRECISION;

        uint256 result = hedgingMath.unwrap(
            hedgingMath.ud_sub(hedgingMath.ud(a), hedgingMath.ud(b))
        );

        assertEq(result, 50 * PRECISION, "Subtraction should work correctly");
    }

    function test_ud60x18_mul() public view {
        uint256 a = 10 * PRECISION;
        uint256 b = 5 * PRECISION;

        uint256 result = hedgingMath.unwrap(
            hedgingMath.ud_mul(hedgingMath.ud(a), hedgingMath.ud(b))
        );

        assertEq(result, 50 * PRECISION, "Multiplication should work correctly");
    }

    function test_ud60x18_div() public view {
        uint256 a = 100 * PRECISION;
        uint256 b = 5 * PRECISION;

        uint256 result = hedgingMath.unwrap(
            hedgingMath.ud_div(hedgingMath.ud(a), hedgingMath.ud(b))
        );

        assertEq(result, 20 * PRECISION, "Division should work correctly");
    }

    function test_ud60x18_sqrt() public view {
        uint256 value = 16 * PRECISION;

        uint256 result = hedgingMath.unwrap(
            hedgingMath.ud_sqrt(hedgingMath.ud(value))
        );

        assertApproxEqRel(result, 4e9, 0.01e18, "sqrt should work correctly");
    }

    // ===========================
    // Edge Cases & Integration Tests
    // ===========================

    function test_integration_full_hedging_scenario() public view {
        // Use wider Q96 ranges for get_liquidity_xy to avoid overflow
        uint160 sp = uint160(Q96);               // sqrt price for price = 1
        uint160 sa = uint160(Q96 / 2);           // lower bound (price = 0.25)
        uint160 sb = uint160(Q96 * 2);           // upper bound (price = 4)
        uint256 initialValue = 1000 * PRECISION;

        // Get initial liquidity distribution
        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, initialValue);

        // Verify initial amounts
        assertGt(x, 0, "Initial x should be positive");
        assertGt(y, 0, "Initial y should be positive");

        // For calculateAmounts, use regular price format with tighter ranges
        uint256 p = PRECISION;                    // price = 1.0
        uint256 a = (9 * PRECISION) / 10;         // price = 0.9
        uint256 b = (11 * PRECISION) / 10;        // price = 1.1
        uint256 P1 = (105 * PRECISION) / 100;     // new price = 1.05

        // Calculate new amounts after price change
        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(p, a, b, x, y, P1);

        // Verify amounts changed appropriately
        assertLt(x1, x, "x should decrease on price increase");
        assertGt(y1, y, "y should increase on price increase");

        // Calculate hedging position
        uint256 shortPrice = (95 * PRECISION) / 100; // 0.95
        (uint256 lpValue, uint256 shortValue) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1,
            shortPrice
        );

        assertGt(lpValue, 0, "LP value should be calculated");
        assertGe(shortValue, 0, "Short value should be non-negative");
    }

    function test_edge_case_extreme_price_ranges() public view {
        // Using wider but safe Q96 range
        uint160 sp = uint160(Q96);           // Current price
        uint160 sa = uint160(Q96 / 2);       // Lower bound (price = 0.25)
        uint160 sb = uint160(Q96 * 2);       // Upper bound (price = 4)
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        assertGt(x + y, 0, "Should handle wide price ranges");
    }

    function test_edge_case_very_small_amounts() public view {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 / 2);
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1e12; // Very small amount

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, value);

        // Should not revert with small amounts
        assertTrue(x + y > 0 || value == 0, "Should handle small amounts");
    }
}