// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title UD60x18Lib
 * @notice Shared library for UD60x18 fixed-point math operations
 * @dev Single source of truth for UD60x18 type and helper functions
 */
abstract contract UD60x18Lib {
    // UD60x18 type for fixed-point math (18 decimal precision)
    type UD60x18 is uint256;

    // ===========================
    // UD60x18 Helper Functions
    // ===========================

    function ud(uint256 x) internal pure returns (UD60x18) {
        return UD60x18.wrap(x);
    }

    function unwrap(UD60x18 x) internal pure returns (uint256) {
        return UD60x18.unwrap(x);
    }

    function ud_add(UD60x18 x, UD60x18 y) internal pure returns (UD60x18) {
        return UD60x18.wrap(UD60x18.unwrap(x) + UD60x18.unwrap(y));
    }

    function ud_sub(UD60x18 x, UD60x18 y) internal pure returns (UD60x18) {
        return UD60x18.wrap(UD60x18.unwrap(x) - UD60x18.unwrap(y));
    }

    function ud_mul(UD60x18 x, UD60x18 y) internal pure returns (UD60x18) {
        return UD60x18.wrap((UD60x18.unwrap(x) * UD60x18.unwrap(y)) / 1e18);
    }

    function ud_div(UD60x18 x, UD60x18 y) internal pure returns (UD60x18) {
        return UD60x18.wrap((UD60x18.unwrap(x) * 1e18) / UD60x18.unwrap(y));
    }

    function ud_sqrt(UD60x18 x) internal pure returns (UD60x18) {
        return UD60x18.wrap(sqrt(UD60x18.unwrap(x)));
    }

    /**
     * @notice Babylonian square root method
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
