// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SaucerHedgeVault.sol";
import "./SaucerHedgeVaultFactory.sol";

/**
 * @title VaultManager
 * @notice Manages multi-asset deposits across separate vaults for LP pairs
 * @dev Coordinates USDC + HBAR deposits and interacts with SaucerHedger
 */
contract VaultManager is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Core addresses
    address public vincentPKP;
    address public saucerHedger;
    SaucerHedgeVaultFactory public immutable vaultFactory;

    // Vault addresses for LP pairs
    address public usdcVault;
    address public hbarVault;

    // User LP deposit tracking
    struct UserLPDeposit {
        uint256 usdcAmount;
        uint256 hbarAmount;
        uint256 usdcShares;
        uint256 hbarShares;
        uint256 hedgedPositionId;
        uint256 depositTimestamp;
        bool hasActivePosition;
    }

    mapping(address => UserLPDeposit) public userLPDeposits;

    // Events
    event LPDepositMade(
        address indexed user,
        uint256 usdcAmount,
        uint256 hbarAmount,
        uint256 usdcShares,
        uint256 hbarShares
    );
    event HedgedLPOpened(
        address indexed user,
        uint256 indexed positionId,
        uint256 usdcAmount,
        uint256 hbarAmount
    );
    event HedgedLPClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 usdcReturned,
        uint256 hbarReturned
    );
    event VincentPKPUpdated(address indexed oldPKP, address indexed newPKP);
    event VaultsUpdated(address indexed usdcVault, address indexed hbarVault);
    event EmergencyWithdrawal(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(
        address _vaultFactory,
        address _vincentPKP,
        address _saucerHedger,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_vaultFactory != address(0), "Invalid factory");
        require(_vincentPKP != address(0), "Invalid PKP");
        require(_saucerHedger != address(0), "Invalid SaucerHedger");

        vaultFactory = SaucerHedgeVaultFactory(_vaultFactory);
        vincentPKP = _vincentPKP;
        saucerHedger = _saucerHedger;
    }

    /**
     * @notice Set vault addresses for USDC and HBAR
     * @dev Must be called after vaults are created via factory
     */
    function setVaults(
        address _usdcVault,
        address _hbarVault
    ) external onlyOwner {
        require(_usdcVault != address(0), "Invalid USDC vault");
        require(_hbarVault != address(0), "Invalid HBAR vault");
        require(vaultFactory.isValidVault(_usdcVault), "USDC vault not valid");
        require(vaultFactory.isValidVault(_hbarVault), "HBAR vault not valid");

        usdcVault = _usdcVault;
        hbarVault = _hbarVault;

        emit VaultsUpdated(_usdcVault, _hbarVault);
    }

    /**
     * @notice Deposit both USDC and HBAR for LP position
     * @param usdcAmount Amount of USDC to deposit
     * @param hbarAmount Amount of HBAR/WHBAR to deposit
     * @return usdcShares Shares received from USDC vault
     * @return hbarShares Shares received from HBAR vault
     */
    function depositForLP(
        uint256 usdcAmount,
        uint256 hbarAmount
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 usdcShares, uint256 hbarShares)
    {
        require(
            usdcVault != address(0) && hbarVault != address(0),
            "Vaults not set"
        );
        require(usdcAmount > 0 && hbarAmount > 0, "Invalid amounts");
        require(
            !userLPDeposits[msg.sender].hasActivePosition,
            "Position already active"
        );

        // Get vault assets
        address usdcAsset = SaucerHedgeVault(usdcVault).asset();
        address hbarAsset = SaucerHedgeVault(hbarVault).asset();

        // Transfer tokens from user to this contract
        IERC20(usdcAsset).safeTransferFrom(
            msg.sender,
            address(this),
            usdcAmount
        );
        IERC20(hbarAsset).safeTransferFrom(
            msg.sender,
            address(this),
            hbarAmount
        );

        // Approve vaults
        IERC20(usdcAsset).approve(usdcVault, usdcAmount);
        IERC20(hbarAsset).approve(hbarVault, hbarAmount);

        // Deposit to both vaults (receives shares)
        usdcShares = SaucerHedgeVault(usdcVault).deposit(
            usdcAmount,
            address(this)
        );
        hbarShares = SaucerHedgeVault(hbarVault).deposit(
            hbarAmount,
            address(this)
        );

        // Record user deposits
        userLPDeposits[msg.sender] = UserLPDeposit({
            usdcAmount: usdcAmount,
            hbarAmount: hbarAmount,
            usdcShares: usdcShares,
            hbarShares: hbarShares,
            hedgedPositionId: 0,
            depositTimestamp: block.timestamp,
            hasActivePosition: false
        });

        emit LPDepositMade(
            msg.sender,
            usdcAmount,
            hbarAmount,
            usdcShares,
            hbarShares
        );

        return (usdcShares, hbarShares);
    }

    /**
     * @notice Open hedged LP position for user (Vincent PKP only)
     * @param user User address
     * @param tickLower Lower tick for concentrated liquidity
     * @param tickUpper Upper tick for concentrated liquidity
     * @return positionId Position ID from SaucerHedger
     */
    function openHedgedLPForUser(
        address user,
        int24 tickLower,
        int24 tickUpper
    ) external onlyVincentPKP nonReentrant returns (uint256 positionId) {
        require(
            !userLPDeposits[user].hasActivePosition,
            "Position already active"
        );
        require(userLPDeposits[user].usdcShares > 0, "No USDC deposited");
        require(userLPDeposits[user].hbarShares > 0, "No HBAR deposited");

        // Redeem from both vaults
        uint256 usdcAmount = SaucerHedgeVault(usdcVault).redeem(
            userLPDeposits[user].usdcShares,
            address(this),
            address(this)
        );

        uint256 hbarAmount = SaucerHedgeVault(hbarVault).redeem(
            userLPDeposits[user].hbarShares,
            address(this),
            address(this)
        );

        // Get asset addresses
        address usdcAsset = SaucerHedgeVault(usdcVault).asset();
        address hbarAsset = SaucerHedgeVault(hbarVault).asset();

        // Approve SaucerHedger
        IERC20(usdcAsset).approve(saucerHedger, usdcAmount);
        IERC20(hbarAsset).approve(saucerHedger, hbarAmount);

        // Open hedged position
        positionId = ISaucerHedger(saucerHedger).openHedgedLP(
            usdcAsset,
            hbarAsset,
            usdcAmount,
            hbarAmount,
            tickLower,
            tickUpper
        );

        // Update user position
        userLPDeposits[user].hedgedPositionId = positionId;
        userLPDeposits[user].hasActivePosition = true;

        emit HedgedLPOpened(user, positionId, usdcAmount, hbarAmount);

        return positionId;
    }

    /**
     * @notice Close hedged LP position for user (Vincent PKP only)
     * @param user User address
     * @return usdcReturned Amount of USDC returned to user
     * @return hbarReturned Amount of HBAR returned to user
     */
    function closeHedgedLPForUser(
        address user
    )
        external
        onlyVincentPKP
        nonReentrant
        returns (uint256 usdcReturned, uint256 hbarReturned)
    {
        require(userLPDeposits[user].hasActivePosition, "No active position");

        uint256 positionId = userLPDeposits[user].hedgedPositionId;

        // Get asset addresses
        address usdcAsset = SaucerHedgeVault(usdcVault).asset();
        address hbarAsset = SaucerHedgeVault(hbarVault).asset();

        // Get balances before closing
        uint256 usdcBalanceBefore = IERC20(usdcAsset).balanceOf(address(this));
        uint256 hbarBalanceBefore = IERC20(hbarAsset).balanceOf(address(this));

        // Close position on SaucerHedger
        ISaucerHedger(saucerHedger).closeHedgedLP(positionId);

        // Calculate returned amounts
        usdcReturned =
            IERC20(usdcAsset).balanceOf(address(this)) -
            usdcBalanceBefore;
        hbarReturned =
            IERC20(hbarAsset).balanceOf(address(this)) -
            hbarBalanceBefore;

        // Transfer tokens back to user
        if (usdcReturned > 0) {
            IERC20(usdcAsset).safeTransfer(user, usdcReturned);
        }
        if (hbarReturned > 0) {
            IERC20(hbarAsset).safeTransfer(user, hbarReturned);
        }

        // Reset user position
        userLPDeposits[user].hasActivePosition = false;
        userLPDeposits[user].hedgedPositionId = 0;

        emit HedgedLPClosed(user, positionId, usdcReturned, hbarReturned);

        return (usdcReturned, hbarReturned);
    }

    /**
     * @notice Withdraw deposits before opening position
     * @dev Only callable if no active position
     */
    function withdrawDeposits() external nonReentrant {
        require(
            !userLPDeposits[msg.sender].hasActivePosition,
            "Close position first"
        );
        require(
            userLPDeposits[msg.sender].usdcShares > 0 ||
                userLPDeposits[msg.sender].hbarShares > 0,
            "No deposits"
        );

        uint256 usdcAmount = 0;
        uint256 hbarAmount = 0;

        // Redeem USDC shares if any
        if (userLPDeposits[msg.sender].usdcShares > 0) {
            usdcAmount = SaucerHedgeVault(usdcVault).redeem(
                userLPDeposits[msg.sender].usdcShares,
                msg.sender,
                address(this)
            );
        }

        // Redeem HBAR shares if any
        if (userLPDeposits[msg.sender].hbarShares > 0) {
            hbarAmount = SaucerHedgeVault(hbarVault).redeem(
                userLPDeposits[msg.sender].hbarShares,
                msg.sender,
                address(this)
            );
        }

        // Reset user deposits
        delete userLPDeposits[msg.sender];

        emit EmergencyWithdrawal(
            msg.sender,
            SaucerHedgeVault(usdcVault).asset(),
            usdcAmount
        );
        emit EmergencyWithdrawal(
            msg.sender,
            SaucerHedgeVault(hbarVault).asset(),
            hbarAmount
        );
    }

    /**
     * @notice Emergency withdraw specific token (owner only, when paused)
     */
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner whenPaused {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyWithdrawal(to, token, amount);
    }

    // ========== ADMIN FUNCTIONS ==========

    function setVincentPKP(address _newPKP) external onlyOwner {
        require(_newPKP != address(0), "Invalid PKP");
        address oldPKP = vincentPKP;
        vincentPKP = _newPKP;
        emit VincentPKPUpdated(oldPKP, _newPKP);
    }

    function setSaucerHedger(address _saucerHedger) external onlyOwner {
        require(_saucerHedger != address(0), "Invalid SaucerHedger");
        saucerHedger = _saucerHedger;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========== VIEW FUNCTIONS ==========

    function getUserLPDeposit(
        address user
    ) external view returns (UserLPDeposit memory) {
        return userLPDeposits[user];
    }

    function getVaultAssets()
        external
        view
        returns (address usdcAsset, address hbarAsset)
    {
        if (usdcVault != address(0)) {
            usdcAsset = SaucerHedgeVault(usdcVault).asset();
        }
        if (hbarVault != address(0)) {
            hbarAsset = SaucerHedgeVault(hbarVault).asset();
        }
        return (usdcAsset, hbarAsset);
    }

    function hasActivePosition(address user) external view returns (bool) {
        return userLPDeposits[user].hasActivePosition;
    }

    // ========== MODIFIERS ==========

    modifier onlyVincentPKP() {
        require(msg.sender == vincentPKP, "Only Vincent PKP");
        _;
    }
}
