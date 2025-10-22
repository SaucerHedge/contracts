// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./UD60x18Lib.sol";

/**
 * @title HedgingMath
 * @notice Mathematical calculations for hedging impermanent loss
 * @dev Based on concentrated liquidity math from SaucerSwap V2
 */
contract HedgingMath is UD60x18Lib {
    // Custom errors for better gas efficiency
    error InvalidPriceRange();
    error PriceOutOfRange();
    error DivisionByZero();
    error InvalidInput();

    /**
     * @notice Calculate liquidity distribution given price range and total value
     * @param sp Current sqrt price (Q96 format)
     * @param sa Lower bound sqrt price (Q96 format)
     * @param sb Upper bound sqrt price (Q96 format)
     * @param value Total value to distribute
     * @return x Amount of token0
     * @return y Amount of token1
     */
    function get_liquidity_xy(
        uint160 sp,
        uint160 sa,
        uint160 sb,
        uint256 value
    ) public pure returns (uint256 x, uint256 y) {
        // Input validation
        if (sa >= sb) revert InvalidPriceRange();
        if (sp < sa || sp > sb) revert PriceOutOfRange();
        if (value == 0) return (0, 0);

        // Check for potential overflow in calculations
        if (
            uint256(sp) > type(uint128).max ||
            uint256(sa) > type(uint128).max ||
            uint256(sb) > type(uint128).max
        ) {
            revert InvalidInput();
        }

        // Handle edge case: sp == sa
        if (sp == sa) {
            // All value goes to token0
            x = value;
            y = 0;
            return (x, y);
        }

        // Handle edge case: sp == sb
        if (sp == sb) {
            // All value goes to token1
            x = 0;
            y = value;
            return (x, y);
        }

        uint256 numerator1 = uint256(value) << 96;
        uint256 dividorFirst = mulDiv(
            uint256(sp - sa),
            uint256(sb),
            uint256(sb - sp)
        );
        uint256 dividorSecond = mulDiv(
            numerator1,
            1 << 96,
            (dividorFirst + sp)
        ) / sp;

        x = dividorSecond;

        // Calculate y with overflow protection
        uint256 spSquared = mulDiv(uint256(sp), uint256(sp), 2 ** 96);
        uint256 productXPrice = mulDiv(spSquared, x, 2 ** 96);

        if (productXPrice > value) {
            y = 0; // Avoid underflow
        } else {
            y = value - productXPrice;
        }

        return (x, y);
    }

    /**
     * @notice Find maximum x value for given parameters
     * @param p Current price
     * @param a Lower price bound
     * @param b Upper price bound
     * @param vMax Maximum value
     * @return Maximum x value
     */
    function findMaxX2(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 vMax
    ) public pure returns (uint256) {
        // Input validation
        if (a >= b) revert InvalidPriceRange();
        if (p < a || p > b) revert PriceOutOfRange();
        if (vMax == 0) return 0;

        UD60x18 sp = ud_sqrt(ud(p));
        UD60x18 sa = ud_sqrt(ud(a));
        UD60x18 sb = ud_sqrt(ud(b));

        // Check for division by zero: sb - sp must be non-zero
        if (unwrap(sb) <= unwrap(sp)) revert DivisionByZero();

        UD60x18 x2 = ud_div(
            ud(vMax),
            ud_add(
                ud_div(ud_mul(ud_sub(sp, sa), ud_mul(sp, sb)), ud_sub(sb, sp)),
                ud(p)
            )
        );

        return unwrap(x2);
    }

    /**
     * @notice Calculate liquidity from token0 amount
     * @param x Amount of token0
     * @param sa Lower sqrt price
     * @param sb Upper sqrt price
     * @return liquidity Liquidity value
     */
    function getLiquidity0(
        UD60x18 x,
        UD60x18 sa,
        UD60x18 sb
    ) public pure returns (UD60x18) {
        if (unwrap(sb) <= unwrap(sa)) revert InvalidPriceRange();
        return ud_div(ud_mul(ud_mul(x, sa), sb), ud_sub(sb, sa));
    }

    /**
     * @notice Calculate liquidity from token1 amount
     * @param y Amount of token1
     * @param sa Lower sqrt price
     * @param sb Upper sqrt price
     * @return liquidity Liquidity value
     */
    function getLiquidity1(
        UD60x18 y,
        UD60x18 sa,
        UD60x18 sb
    ) public pure returns (UD60x18) {
        if (unwrap(sb) <= unwrap(sa)) revert InvalidPriceRange();
        return ud_div(y, ud_sub(sb, sa));
    }

    /**
     * @notice Calculate combined liquidity from both tokens
     * @param x Amount of token0
     * @param y Amount of token1
     * @param sp Current sqrt price
     * @param sa Lower sqrt price
     * @param sb Upper sqrt price
     * @return liquidity Combined liquidity value
     */
    function getLiquidity(
        UD60x18 x,
        UD60x18 y,
        UD60x18 sp,
        UD60x18 sa,
        UD60x18 sb
    ) public pure returns (UD60x18) {
        if (unwrap(sb) <= unwrap(sa)) revert InvalidPriceRange();

        UD60x18 liquidity;

        if (unwrap(sp) <= unwrap(sa)) {
            liquidity = getLiquidity0(x, sa, sb);
        } else if (unwrap(sp) < unwrap(sb)) {
            UD60x18 liquidity0 = getLiquidity0(x, sp, sb);
            UD60x18 liquidity1 = getLiquidity1(y, sa, sp);
            liquidity = unwrap(liquidity0) < unwrap(liquidity1)
                ? liquidity0
                : liquidity1;
        } else {
            liquidity = getLiquidity1(y, sa, sb);
        }

        return liquidity;
    }

    /**
     * @notice Calculate token amounts after price change
     * @dev Fixed version with better overflow protection
     */
    function calculateAmounts(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 x,
        uint256 y,
        uint256 P1
    ) public pure returns (uint256 x1, uint256 y1) {
        // Input validation
        if (a >= b) revert InvalidPriceRange();
        if (p < a || p > b) revert PriceOutOfRange();
        if (P1 < a || P1 > b) revert PriceOutOfRange();

        // Calculate sqrt prices
        UD60x18 sp = ud_sqrt(ud(p));
        UD60x18 sa = ud_sqrt(ud(a));
        UD60x18 sb = ud_sqrt(ud(b));

        // Get liquidity
        UD60x18 L = getLiquidity(ud(x), ud(y), sp, sa, sb);

        // Clamp current price to range
        sp = _clamp(sp, sa, sb);

        // Calculate and clamp new sqrt price
        UD60x18 sp1 = _clamp(ud_sqrt(ud(P1)), sa, sb);

        // Calculate delta_x: L * (1/sp1 - 1/sp)
        // Avoid division issues by checking if sp1 == sp
        uint256 delta_x_raw;
        if (unwrap(sp1) == unwrap(sp)) {
            delta_x_raw = 0;
        } else if (unwrap(sp1) < unwrap(sp)) {
            // Price decreased, x increases
            delta_x_raw = unwrap(
                ud_mul(L, ud_sub(ud_div(ud(1e18), sp1), ud_div(ud(1e18), sp)))
            );
        } else {
            // Price increased, x decreases
            uint256 diff = unwrap(
                ud_sub(ud_div(ud(1e18), sp), ud_div(ud(1e18), sp1))
            );
            uint256 decrease = unwrap(ud_mul(L, ud(diff)));

            // Protect against underflow
            if (decrease > x) {
                x1 = 0;
                delta_x_raw = 0; // Will be handled below
            } else {
                delta_x_raw = decrease;
            }
        }

        // Calculate delta_y: L * (sp1 - sp)
        uint256 delta_y_raw;
        if (unwrap(sp1) >= unwrap(sp)) {
            delta_y_raw = unwrap(ud_mul(L, ud_sub(sp1, sp)));
        } else {
            // Price decreased, y decreases
            uint256 decrease = unwrap(ud_mul(L, ud_sub(sp, sp1)));
            if (decrease > y) {
                y1 = 0;
                delta_y_raw = 0;
            } else {
                delta_y_raw = decrease;
            }
        }

        // Calculate new amounts with overflow protection
        if (unwrap(sp1) < unwrap(sp)) {
            // Price decreased
            x1 = x + delta_x_raw;
            y1 = y > delta_y_raw ? y - delta_y_raw : 0;
        } else if (unwrap(sp1) > unwrap(sp)) {
            // Price increased
            x1 = x > delta_x_raw ? x - delta_x_raw : 0;
            y1 = y + delta_y_raw;
        } else {
            x1 = x;
            y1 = y;
        }

        return (x1, y1);
    }

    /**
     * @notice Find equal PnL values for hedging strategy
     * @dev Made internal so it can be called by SaucerHedger
     */
    function findEqualPnLValues(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 P1,
        uint256 shortPrice
    ) internal pure returns (uint256 lpValue, uint256 shortValue) {
        // Input validation
        if (a >= b) revert InvalidPriceRange();
        if (p < a || p > b) revert PriceOutOfRange();
        if (P1 < a || P1 > b) revert PriceOutOfRange();
        if (P1 == shortPrice) revert DivisionByZero();

        uint256 virtualLP = 1000e18;
        uint256 virtualShort;

        // Calculate initial amounts
        (uint256 x, uint256 y) = _getInitialAmounts(p, a, b, virtualLP);

        // Calculate PnL
        int256 PNL_V3 = _calculatePnL(p, a, b, x, y, P1);

        // Calculate short position size with overflow protection
        // virtualShort = (PNL_V3 * shortPrice) / (P1 - shortPrice)
        if (PNL_V3 < 0) {
            virtualShort = 0; // Negative PnL means no short needed
        } else {
            uint256 pnlAbs = uint256(PNL_V3);

            // Check for division by zero
            if (P1 > shortPrice) {
                virtualShort = (pnlAbs * shortPrice) / (P1 - shortPrice);
            } else if (shortPrice > P1) {
                virtualShort = (pnlAbs * shortPrice) / (shortPrice - P1);
            } else {
                revert DivisionByZero();
            }
        }

        return (virtualLP, virtualShort);
    }

    /**
     * @notice Helper to get initial token amounts
     */
    function _getInitialAmounts(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 virtualLP
    ) private pure returns (uint256 x, uint256 y) {
        // Handle edge case where p equals b
        if (p >= b) {
            x = 0;
            y = virtualLP;
            return (x, y);
        }

        // Handle edge case where p equals a
        if (p <= a) {
            x = virtualLP;
            y = 0;
            return (x, y);
        }

        x = findMaxX2(p, a, b, virtualLP);

        // Calculate y = virtualLP - x * p with overflow protection
        uint256 xp = (x * p) / 1e18;
        if (xp > virtualLP) {
            y = 0;
        } else {
            y = virtualLP - xp;
        }

        return (x, y);
    }

    /**
     * @notice Helper to calculate PnL
     */
    function _calculatePnL(
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 x,
        uint256 y,
        uint256 P1
    ) private pure returns (int256) {
        // Get amounts after price change
        (uint256 x1, uint256 y1) = calculateAmounts(p, a, b, x, y, P1);

        // Calculate initial value: x * p + y
        uint256 value = (x * p) / 1e18 + y;

        // Calculate new value: x1 * P1 + y1
        uint256 value1 = (x1 * P1) / 1e18 + y1;

        // Return PnL (can be negative)
        return int256(value1) - int256(value);
    }

    /**
     * @notice Clamp value between min and max
     */
    function _clamp(
        UD60x18 value,
        UD60x18 min,
        UD60x18 max
    ) private pure returns (UD60x18) {
        if (unwrap(value) < unwrap(min)) return min;
        if (unwrap(value) > unwrap(max)) return max;
        return value;
    }

    // ===========================
    // Math Helper Functions
    // ===========================

    /**
     * @notice Calculates floor(a×b÷denominator) with full precision
     * @dev Credit to Uniswap v3-core
     */
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // Handle non-overflow cases, 256 by 256 division
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        require(denominator > prod1);

        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }

        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
        }

        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }
}
