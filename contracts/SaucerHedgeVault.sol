// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SaucerHedgeVault
 * @notice ERC-4626 compliant vault for SaucerHedge protocol
 * @dev Users deposit assets, Vincent abilities manage positions on their behalf
 */
contract SaucerHedgeVault is ERC4626, Ownable, ReentrancyGuard, Pausable {
    // Vincent PKP that has permission to execute strategies
    address public vincentPKP;

    // SaucerHedger contract that executes IL hedging
    address public saucerHedger;

    // Performance fee (in basis points, e.g., 200 = 2%)
    uint256 public performanceFee;

    // Fee recipient
    address public feeRecipient;

    // User deposit limits
    uint256 public maxDepositPerUser;
    uint256 public totalDepositCap;

    // Tracking user positions
    struct UserPosition {
        uint256 shares;
        uint256 hedgedPositionId;
        uint256 depositTime;
        bool hasActivePosition;
    }

    mapping(address => UserPosition) public userPositions;

    // Events
    event VincentPKPUpdated(address indexed oldPKP, address indexed newPKP);
    event HedgedPositionOpened(
        address indexed user,
        uint256 positionId,
        uint256 shares
    );
    event HedgedPositionClosed(
        address indexed user,
        uint256 positionId,
        uint256 shares
    );
    event PerformanceFeeCollected(uint256 amount);
    event EmergencyWithdrawal(address indexed user, uint256 amount);

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _vincentPKP,
        address _saucerHedger,
        address _feeRecipient,
        address _owner
    )
        ERC20(_name, _symbol) // Pass to ERC20 constructor
        ERC4626(_asset) // Pass to ERC4626 constructor
        Ownable(_owner) // Initialize Ownable
    {
        vincentPKP = _vincentPKP;
        saucerHedger = _saucerHedger;
        feeRecipient = _feeRecipient;
        performanceFee = 200; // 2% default

        uint8 assetDecimals = IERC20Metadata(address(_asset)).decimals();
        maxDepositPerUser = 100_000 * 10 ** assetDecimals; // 100k default
        totalDepositCap = 10_000_000 * 10 ** assetDecimals; // 10M default
    }

    /**
     * @notice Deposit assets and open hedged position
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive vault shares
     * @param token0 First token for LP pair
     * @param token1 Second token for LP pair
     * @param tickLower Lower tick for concentrated liquidity
     * @param tickUpper Upper tick for concentrated liquidity
     * @return shares Amount of vault shares minted
     */
    function depositAndHedge(
        uint256 assets,
        address receiver,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        require(assets > 0, "Cannot deposit 0");
        require(totalAssets() + assets <= totalDepositCap, "Exceeds total cap");
        require(
            convertToAssets(userPositions[receiver].shares) + assets <=
                maxDepositPerUser,
            "Exceeds user deposit limit"
        );

        // Deposit assets and mint shares
        shares = deposit(assets, receiver);

        // Record user position
        userPositions[receiver].shares += shares;
        userPositions[receiver].depositTime = block.timestamp;

        // Approve SaucerHedger to use vault assets
        IERC20(asset()).approve(saucerHedger, assets);

        return shares;
    }

    /**
     * @notice Open hedged position (callable only by Vincent PKP)
     * @dev This is called by Vincent abilities after user deposits
     */
    function openHedgedPositionForUser(
        address user,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external onlyVincentPKP returns (uint256 positionId) {
        require(
            !userPositions[user].hasActivePosition,
            "Position already active"
        );
        require(userPositions[user].shares > 0, "No shares");

        // Transfer assets to SaucerHedger
        IERC20(token0).transfer(saucerHedger, amount0);
        if (token0 != token1) {
            IERC20(token1).transfer(saucerHedger, amount1);
        }

        // Call SaucerHedger to open hedged position
        positionId = ISaucerHedger(saucerHedger).openHedgedLP(
            token0,
            token1,
            amount0,
            amount1,
            tickLower,
            tickUpper
        );

        // Record position
        userPositions[user].hedgedPositionId = positionId;
        userPositions[user].hasActivePosition = true;

        emit HedgedPositionOpened(user, positionId, userPositions[user].shares);

        return positionId;
    }

    /**
     * @notice Close hedged position (callable only by Vincent PKP)
     */
    function closeHedgedPositionForUser(
        address user
    ) external onlyVincentPKP returns (uint256 amount0, uint256 amount1) {
        require(userPositions[user].hasActivePosition, "No active position");

        uint256 positionId = userPositions[user].hedgedPositionId;

        // Get balance before
        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));

        // Close position on SaucerHedger
        ISaucerHedger(saucerHedger).closeHedgedLP(positionId);

        // Get returned assets
        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        amount0 = balanceAfter - balanceBefore;

        // Collect performance fee
        if (performanceFee > 0) {
            uint256 originalDeposit = convertToAssets(
                userPositions[user].shares
            );
            if (amount0 > originalDeposit) {
                uint256 profit = amount0 - originalDeposit;
                uint256 fee = (profit * performanceFee) / 10000;
                IERC20(asset()).transfer(feeRecipient, fee);
                amount0 -= fee;
                emit PerformanceFeeCollected(fee);
            }
        }

        userPositions[user].hasActivePosition = false;

        emit HedgedPositionClosed(user, positionId, userPositions[user].shares);

        return (amount0, 0);
    }

    /**
     * @notice Withdraw assets by burning shares
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        require(
            !userPositions[owner].hasActivePosition,
            "Close position first"
        );

        shares = super.withdraw(assets, receiver, owner);

        // Update user position tracking
        uint256 sharesValue = previewWithdraw(assets);
        if (userPositions[owner].shares >= sharesValue) {
            userPositions[owner].shares -= sharesValue;
        } else {
            userPositions[owner].shares = 0;
        }

        return shares;
    }

    /**
     * @notice Redeem shares for assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        require(
            !userPositions[owner].hasActivePosition,
            "Close position first"
        );

        assets = super.redeem(shares, receiver, owner);

        if (userPositions[owner].shares >= shares) {
            userPositions[owner].shares -= shares;
        } else {
            userPositions[owner].shares = 0;
        }

        return assets;
    }

    /**
     * @notice Emergency withdraw (pause must be active)
     */
    function emergencyWithdraw() external whenPaused nonReentrant {
        uint256 shares = userPositions[msg.sender].shares;
        require(shares > 0, "No shares to withdraw");

        uint256 assets = convertToAssets(shares);

        _burn(msg.sender, shares);
        IERC20(asset()).transfer(msg.sender, assets);

        userPositions[msg.sender].shares = 0;
        userPositions[msg.sender].hasActivePosition = false;

        emit EmergencyWithdrawal(msg.sender, assets);
    }

    // ========== ADMIN FUNCTIONS ==========

    function setVincentPKP(address _newPKP) external onlyOwner {
        address oldPKP = vincentPKP;
        vincentPKP = _newPKP;
        emit VincentPKPUpdated(oldPKP, _newPKP);
    }

    function setSaucerHedger(address _saucerHedger) external onlyOwner {
        saucerHedger = _saucerHedger;
    }

    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee too high"); // Max 10%
        performanceFee = _fee;
    }

    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    function setDepositLimits(
        uint256 _maxPerUser,
        uint256 _totalCap
    ) external onlyOwner {
        maxDepositPerUser = _maxPerUser;
        totalDepositCap = _totalCap;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ========== MODIFIERS ==========

    modifier onlyVincentPKP() {
        require(msg.sender == vincentPKP, "Only Vincent PKP");
        _;
    }

    // ========== VIEW FUNCTIONS ==========

    function getUserPosition(
        address user
    ) external view returns (UserPosition memory) {
        return userPositions[user];
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }
}

/**
 * @title ISaucerHedger
 * @notice Interface for SaucerHedger contract
 */
interface ISaucerHedger {
    function openHedgedLP(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external payable returns (uint256 positionId);

    function closeHedgedLP(uint256 positionId) external;

    function getPosition(
        address user,
        uint256 positionId
    )
        external
        view
        returns (
            uint256 tokenId,
            uint256 leverageId,
            uint128 liquidity,
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1,
            uint256 shortAmount,
            int24 tickLower,
            int24 tickUpper,
            bool active
        );
}
