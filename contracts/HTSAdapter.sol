// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title HTSAdapter
 * @notice Adapter for interacting with both HTS tokens and ERC20 tokens on Hedera
 * @dev HTS tokens are native Hedera tokens, not smart contracts
 * This adapter provides a unified interface for token operations
 */
abstract contract HTSAdapter {
    // Hedera precompile address for HTS operations
    address constant HTS_PRECOMPILE = address(0x167);

    /**
     * @notice Transfer tokens (works with both HTS and ERC20)
     * @param token Token address
     * @param from Source address
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function _transferToken(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from == address(this)) {
            // Transfer from this contract
            require(
                IERC20(token).transfer(to, amount),
                "HTSAdapter: transfer failed"
            );
        } else {
            // Transfer from another address
            require(
                IERC20(token).transferFrom(from, to, amount),
                "HTSAdapter: transferFrom failed"
            );
        }
    }

    /**
     * @notice Approve token spending (works with both HTS and ERC20)
     * @param token Token address
     * @param spender Spender address
     * @param amount Amount to approve
     */
    function _approveToken(
        address token,
        address spender,
        uint256 amount
    ) internal {
        require(
            IERC20(token).approve(spender, amount),
            "HTSAdapter: approve failed"
        );
    }

    /**
     * @notice Get token balance
     * @param token Token address
     * @param account Account address
     * @return Token balance
     */
    function _getBalance(
        address token,
        address account
    ) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /**
     * @notice Get token decimals
     * @param token Token address
     * @return Number of decimals
     */
    function _getDecimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    /**
     * @notice Get token symbol
     * @param token Token address
     * @return Token symbol
     */
    function _getSymbol(address token) internal view returns (string memory) {
        return IERC20Metadata(token).symbol();
    }

    /**
     * @notice Check if address is HBAR (native token)
     * @param token Token address
     * @return true if HBAR, false otherwise
     */
    function _isHBAR(address token) internal pure returns (bool) {
        return token == address(0);
    }

    /**
     * @notice Safely transfer tokens with balance check
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        uint256 balance = _getBalance(token, address(this));
        require(balance >= amount, "HTSAdapter: insufficient balance");

        _transferToken(token, address(this), to, amount);
    }
}
