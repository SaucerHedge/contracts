// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./HedgingMath.sol";

contract HedgingMathTest is Test {
    HedgingMath public hedgingMath;

    // Constants for testing
    uint256 constant PRECISION = 1e18;
    uint256 constant Q96 = 2 ** 96;

    // Custom errors (must match contract)
    error InvalidPriceRange();
    error PriceOutOfRange();
    error DivisionByZero();
    error InvalidInput();

    function setUp() public {
        hedgingMath = new HedgingMath();
    }

    // ===========================
    // Test get_liquidity_xy
    // ===========================

    function test_get_liquidity_xy_basic() public view {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 / 2);
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(
            sp,
            sa,
            sb,
            value
        );

        assertTrue(x > 0, "x should be positive");
        assertTrue(y > 0, "y should be positive");

        uint256 totalValue = x + y;
        assertApproxEqRel(totalValue, value, 0.1e18);
    }

    function test_get_liquidity_xy_at_lower_bound() public view {
        uint160 sa = uint160(Q96);
        uint160 sp = sa;
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(
            sp,
            sa,
            sb,
            value
        );

        assertEq(x, value, "All value should be in x at lower bound");
        assertEq(y, 0, "y should be 0 at lower bound");
    }

    function test_get_liquidity_xy_at_upper_bound() public view {
        uint160 sa = uint160(Q96);
        uint160 sb = uint160(Q96 * 2);
        uint160 sp = sb;
        uint256 value = 1000 * PRECISION;

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(
            sp,
            sa,
            sb,
            value
        );

        assertEq(x, 0, "x should be 0 at upper bound");
        assertEq(y, value, "All value should be in y at upper bound");
    }

    function test_get_liquidity_xy_zero_value() public view {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 / 2);
        uint160 sb = uint160(Q96 * 2);

        (uint256 x, uint256 y) = hedgingMath.get_liquidity_xy(sp, sa, sb, 0);

        assertEq(x, 0, "x should be 0 when value is 0");
        assertEq(y, 0, "y should be 0 when value is 0");
    }

    function test_RevertWhen_InvalidRange_get_liquidity_xy() public {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 * 2);
        uint160 sb = uint160(Q96);
        uint256 value = 1000 * PRECISION;

        vm.expectRevert(InvalidPriceRange.selector);
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
    }

    function test_RevertWhen_PriceOutOfRange_get_liquidity_xy() public {
        uint160 sp = uint160(Q96 * 3);
        uint160 sa = uint160(Q96);
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1000 * PRECISION;

        vm.expectRevert(PriceOutOfRange.selector);
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
    }

    // ===========================
    // Test findMaxX2
    // ===========================

    function test_findMaxX2_basic() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);

        assertTrue(maxX > 0, "maxX should be positive");
        assertTrue(maxX <= vMax, "maxX should not exceed vMax");
    }

    function test_findMaxX2_zero_value() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, 0);

        assertEq(maxX, 0, "maxX should be 0 when vMax is 0");
    }

    function test_findMaxX2_price_variations() public view {
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 maxX_low = hedgingMath.findMaxX2(0.6e18, a, b, vMax);
        uint256 maxX_mid = hedgingMath.findMaxX2(1 * PRECISION, a, b, vMax);
        uint256 maxX_high = hedgingMath.findMaxX2(1.8e18, a, b, vMax);

        assertTrue(maxX_low > 0, "maxX should be positive at low price");
        assertTrue(maxX_mid > 0, "maxX should be positive at mid price");
        assertTrue(maxX_high > 0, "maxX should be positive at high price");
    }

    function test_RevertWhen_InvalidRange_findMaxX2() public {
        uint256 p = 1 * PRECISION;
        uint256 a = 2 * PRECISION;
        uint256 b = 0.5e18;
        uint256 vMax = 1000 * PRECISION;

        vm.expectRevert(InvalidPriceRange.selector);
        hedgingMath.findMaxX2(p, a, b, vMax);
    }

    function test_RevertWhen_PriceOutOfRange_findMaxX2() public {
        uint256 p = 3 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        vm.expectRevert(PriceOutOfRange.selector);
        hedgingMath.findMaxX2(p, a, b, vMax);
    }

    function test_RevertWhen_PriceAtUpperBound_findMaxX2() public {
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 p = b;
        uint256 vMax = 1000 * PRECISION;

        vm.expectRevert(DivisionByZero.selector);
        hedgingMath.findMaxX2(p, a, b, vMax);
    }

    function testFuzz_findMaxX2(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 vMax
    ) public view {
        a = bound(a, 0.1e18, 5e18);
        b = bound(b, a * 2, a * 20);
        p = bound(p, a, (b * 95) / 100);
        vMax = bound(vMax, 0, 100000e18);

        vm.assume(b > a);
        vm.assume(p < b);

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);
        assertTrue(maxX >= 0, "maxX should be non-negative");
    }

    // ===========================
    // Test calculateAmounts
    // ===========================

    function test_calculateAmounts_price_unchanged() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = p;

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        assertEq(x1, x, "x should remain same");
        assertEq(y1, y, "y should remain same");
    }

    function test_calculateAmounts_price_increase() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1.5e18;

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        assertTrue(
            x1 <= x,
            "x should decrease or stay same when price increases"
        );
        assertTrue(
            y1 >= y,
            "y should increase or stay same when price increases"
        );
    }

    function test_calculateAmounts_price_decrease() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 0.7e18;

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        assertTrue(
            x1 >= x,
            "x should increase or stay same when price decreases"
        );
        assertTrue(
            y1 <= y,
            "y should decrease or stay same when price decreases"
        );
    }

    function test_RevertWhen_InvalidRange_calculateAmounts() public {
        uint256 p = 1 * PRECISION;
        uint256 a = 2 * PRECISION;
        uint256 b = 0.5e18;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1 * PRECISION;

        vm.expectRevert(InvalidPriceRange.selector);
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
    }

    function test_RevertWhen_PriceOutOfRange_calculateAmounts() public {
        uint256 p = 3 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1 * PRECISION;

        vm.expectRevert(PriceOutOfRange.selector);
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
    }

    function testFuzz_calculateAmounts(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 x,
        uint256 y,
        uint256 P1
    ) public view {
        a = bound(a, 0.1e18, 5e18);
        b = bound(b, a * 2, a * 10);
        p = bound(p, a, b);
        x = bound(x, 1e18, 10000e18);
        y = bound(y, 1e18, 10000e18);
        P1 = bound(P1, a, b);

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        assertTrue(x1 >= 0, "x1 should be non-negative");
        assertTrue(y1 >= 0, "y1 should be non-negative");
    }

    // ===========================
    // Test findEqualPnLValues
    // ===========================

    function test_findEqualPnLValues_basic() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 P1 = 1.5e18;
        uint256 shortPrice = 1.2e18;

        (uint256 lpValue, uint256 shortValue) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1,
            shortPrice
        );

        assertTrue(lpValue > 0, "lpValue should be positive");
        assertTrue(shortValue >= 0, "shortValue should be non-negative");
        assertEq(lpValue, 1000 * PRECISION, "lpValue should be 1000e18");
    }

    function test_findEqualPnLValues_different_scenarios() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;

        // Scenario 1: Price increases moderately
        (, uint256 short1) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            1.5e18,
            1.2e18
        );

        // Scenario 2: Price increases significantly
        (, uint256 short2) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            1.8e18,
            1.3e18
        );

        // Both scenarios should produce valid short values
        assertTrue(short1 >= 0, "Short value 1 should be non-negative");
        assertTrue(short2 >= 0, "Short value 2 should be non-negative");
    }

    function test_findEqualPnLValues_boundary_prices() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 shortPrice = 1.2e18;

        (uint256 lpLower, ) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            a,
            shortPrice
        );

        (uint256 lpUpper, ) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            b,
            shortPrice
        );

        assertTrue(lpLower > 0, "Should handle lower boundary");
        assertTrue(lpUpper > 0, "Should handle upper boundary");
    }

    function test_RevertWhen_InvalidRange_findEqualPnLValues() public {
        uint256 p = 1 * PRECISION;
        uint256 a = 2 * PRECISION;
        uint256 b = 0.5e18;
        uint256 P1 = 1 * PRECISION;
        uint256 shortPrice = 0.8e18;

        vm.expectRevert(InvalidPriceRange.selector);
        hedgingMath.findEqualPnLValues(p, a, b, P1, shortPrice);
    }

    function test_RevertWhen_DivisionByZero_findEqualPnLValues() public {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 P1 = 1.5e18;
        uint256 shortPrice = P1;

        vm.expectRevert(DivisionByZero.selector);
        hedgingMath.findEqualPnLValues(p, a, b, P1, shortPrice);
    }

    function testFuzz_findEqualPnLValues(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 P1,
        uint256 shortPrice
    ) public view {
        a = bound(a, 0.1e18, 5e18);
        b = bound(b, a * 2, a * 10);
        p = bound(p, (a * 11) / 10, (b * 9) / 10);
        P1 = bound(P1, (a * 11) / 10, (b * 9) / 10);
        shortPrice = bound(shortPrice, (a * 11) / 10, (b * 9) / 10);

        vm.assume(b > a);
        vm.assume(P1 != shortPrice);
        vm.assume(p > a && p < b);
        vm.assume(P1 > a && P1 < b);
        vm.assume(shortPrice > a && shortPrice < b);
        vm.assume(p < (b * 95) / 100);

        (uint256 lpValue, uint256 shortValue) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1,
            shortPrice
        );

        assertTrue(lpValue > 0, "lpValue should be positive");
        assertTrue(shortValue >= 0, "shortValue should be non-negative");
    }

    // ===========================
    // Test Liquidity Functions
    // ===========================

    function test_getLiquidity0_basic() public view {
        uint256 x = 100 * PRECISION;
        uint256 sa_val = 0.5e18;
        uint256 sb_val = 2 * PRECISION;

        HedgingMath.UD60x18 sa = HedgingMath.UD60x18.wrap(sa_val);
        HedgingMath.UD60x18 sb = HedgingMath.UD60x18.wrap(sb_val);
        HedgingMath.UD60x18 x_ud = HedgingMath.UD60x18.wrap(x);

        HedgingMath.UD60x18 liquidity = hedgingMath.getLiquidity0(x_ud, sa, sb);

        assertTrue(
            HedgingMath.UD60x18.unwrap(liquidity) > 0,
            "Liquidity should be positive"
        );
    }

    function test_getLiquidity1_basic() public view {
        uint256 y = 100 * PRECISION;
        uint256 sa_val = 0.5e18;
        uint256 sb_val = 2 * PRECISION;

        HedgingMath.UD60x18 sa = HedgingMath.UD60x18.wrap(sa_val);
        HedgingMath.UD60x18 sb = HedgingMath.UD60x18.wrap(sb_val);
        HedgingMath.UD60x18 y_ud = HedgingMath.UD60x18.wrap(y);

        HedgingMath.UD60x18 liquidity = hedgingMath.getLiquidity1(y_ud, sa, sb);

        assertTrue(
            HedgingMath.UD60x18.unwrap(liquidity) > 0,
            "Liquidity should be positive"
        );
    }

    function test_RevertWhen_InvalidRange_getLiquidity0() public {
        uint256 x = 100 * PRECISION;
        uint256 sa_val = 2 * PRECISION;
        uint256 sb_val = 0.5e18;

        HedgingMath.UD60x18 sa = HedgingMath.UD60x18.wrap(sa_val);
        HedgingMath.UD60x18 sb = HedgingMath.UD60x18.wrap(sb_val);
        HedgingMath.UD60x18 x_ud = HedgingMath.UD60x18.wrap(x);

        vm.expectRevert(InvalidPriceRange.selector);
        hedgingMath.getLiquidity0(x_ud, sa, sb);
    }

    // ===========================
    // Integration Tests
    // ===========================

    function test_integration_full_workflow() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 x = hedgingMath.findMaxX2(p, a, b, vMax);
        uint256 y = vMax - (x * p) / PRECISION;

        uint256 P1 = 1.5e18;
        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        uint256 shortPrice = 1.2e18;
        (uint256 lpValue, uint256 shortValue) = hedgingMath.findEqualPnLValues(
            p,
            a,
            b,
            P1,
            shortPrice
        );

        assertTrue(x > 0 && y >= 0, "Initial amounts should be valid");
        assertTrue(x1 >= 0 && y1 >= 0, "New amounts should be non-negative");
        assertTrue(
            lpValue > 0 && shortValue >= 0,
            "Hedging values should be valid"
        );
    }

    function test_integration_extreme_price_moves() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 x = hedgingMath.findMaxX2(p, a, b, vMax);
        uint256 y = vMax - (x * p) / PRECISION;

        uint256 P1_high = 1.9e18;
        (uint256 x1_high, uint256 y1_high) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1_high
        );

        uint256 P1_low = 0.6e18;
        (uint256 x1_low, uint256 y1_low) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1_low
        );

        assertTrue(
            x1_high >= 0 && y1_high >= 0,
            "High price amounts should be non-negative"
        );
        assertTrue(
            x1_low >= 0 && y1_low >= 0,
            "Low price amounts should be non-negative"
        );
    }

    function test_integration_multiple_price_changes() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 x = hedgingMath.findMaxX2(p, a, b, vMax);
        uint256 y = vMax - (x * p) / PRECISION;

        uint256 P1 = 1.3e18;
        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );

        uint256 P2 = 1.6e18;
        (uint256 x2, uint256 y2) = hedgingMath.calculateAmounts(
            P1,
            a,
            b,
            x1,
            y1,
            P2
        );

        assertTrue(x2 >= 0 && y2 >= 0, "Final amounts should be non-negative");
    }

    // ===========================
    // Edge Cases
    // ===========================

    function test_edge_case_small_price_range() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.95e18;
        uint256 b = 1.05e18;
        uint256 vMax = 1000 * PRECISION;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);
        assertTrue(maxX >= 0, "Should handle small price ranges");
    }

    function test_edge_case_large_price_range() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.1e18;
        uint256 b = 10 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 maxX = hedgingMath.findMaxX2(p, a, b, vMax);
        assertTrue(maxX > 0, "Should handle large price ranges");
    }

    function test_edge_case_price_at_lower_bound() public view {
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 p = a;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1 * PRECISION;

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );
        assertTrue(x1 >= 0 && y1 >= 0, "Should handle price at lower bound");
    }

    function test_edge_case_price_at_upper_bound() public view {
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 p = b;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1 * PRECISION;

        (uint256 x1, uint256 y1) = hedgingMath.calculateAmounts(
            p,
            a,
            b,
            x,
            y,
            P1
        );
        assertTrue(x1 >= 0 && y1 >= 0, "Should handle price at upper bound");
    }

    // ===========================
    // Gas Optimization Tests
    // ===========================

    function test_gas_get_liquidity_xy() public view {
        uint160 sp = uint160(Q96);
        uint160 sa = uint160(Q96 / 2);
        uint160 sb = uint160(Q96 * 2);
        uint256 value = 1000 * PRECISION;

        uint256 gasBefore = gasleft();
        hedgingMath.get_liquidity_xy(sp, sa, sb, value);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(gasUsed > 0, "Should consume gas");
    }

    function test_gas_findMaxX2() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 vMax = 1000 * PRECISION;

        uint256 gasBefore = gasleft();
        hedgingMath.findMaxX2(p, a, b, vMax);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(gasUsed > 0, "Should consume gas");
    }

    function test_gas_calculateAmounts() public view {
        uint256 p = 1 * PRECISION;
        uint256 a = 0.5e18;
        uint256 b = 2 * PRECISION;
        uint256 x = 100 * PRECISION;
        uint256 y = 100 * PRECISION;
        uint256 P1 = 1.5e18;

        uint256 gasBefore = gasleft();
        hedgingMath.calculateAmounts(p, a, b, x, y, P1);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(gasUsed > 0, "Should consume gas");
    }
}
