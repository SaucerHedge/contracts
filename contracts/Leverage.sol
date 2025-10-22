// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IBonzo.sol";
import "./Swapper.sol";

/**
 * @title Leverage
 * @notice Manages leveraged positions using Bonzo Finance (adapted from Aave)
 * @dev Enables short positions with flash loans for hedging IL
 */
contract Leverage is SaucerSwapper, IFlashLoanReceiver {
    // Custom UD60x18 type for fixed-point math
    type UD60x18 is uint256;

    struct Position {
        address baseAsset;
        address leveragedAsset;
        uint256 amount;
        UD60x18 leverage;
        bool isLong;
        uint256 initialAmount;
        bool isClosed;
    }

    struct FlashloanParams {
        address user;
        address nonCollateralAsset;
        uint256 amount;
        bool isLong;
        bool isClose;
        uint256 positionId; // ADDED: Track which position is being operated on
    }

    // Mapping: address user => ID => Position
    mapping(address => mapping(uint256 => Position)) public positions;

    // Mapping: address user => position IDs
    mapping(address => uint256[]) public IDs;

    IBonzoPool public bonzoPool;
    address public owner;

    // Flash loan constants (adjusted for Bonzo)
    uint256 public openFlashConstant = 1.005e18;
    uint256 public closeFlashConstant = 1.009e16;

    event PositionOpened(
        address indexed user,
        uint256 indexed id,
        address baseAsset,
        address leveragedAsset,
        uint256 amount,
        uint256 leverage
    );

    event PositionClosed(address indexed user, uint256 indexed id);

    constructor(
        address _bonzoPool,
        address _router,
        address _factory,
        address _quoter
    ) SaucerSwapper(_router, _factory, _quoter) {
        bonzoPool = IBonzoPool(_bonzoPool);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Get number of positions for a user
     * @param user User address
     * @return Number of positions
     */
    function getUserIDlength(address user) external view returns (uint256) {
        return IDs[user].length;
    }

    /**
     * @notice Update flash loan constants
     * @param _openFlashConstant New open flash constant
     * @param _closeFlashConstant New close flash constant
     */
    function updateFlashConstant(
        uint256 _openFlashConstant,
        uint256 _closeFlashConstant
    ) public onlyOwner returns (bool) {
        openFlashConstant = _openFlashConstant;
        closeFlashConstant = _closeFlashConstant;
        return true;
    }

    /**
     * @notice Open a short position
     * @param baseAsset Base asset (e.g., USDC)
     * @param leveragedAsset Asset to short (e.g., HBAR)
     * @param amountBase Amount of base asset
     * @param leverage Leverage amount (1-5x)
     * @return positionId The ID of the created position
     */
    function short(
        address baseAsset,
        address leveragedAsset,
        uint256 amountBase,
        UD60x18 leverage
    ) public returns (uint256 positionId) {
        // Transfer base asset from user
        _transferToken(baseAsset, msg.sender, address(this), amountBase);

        // Calculate flash loan amount
        uint256 flashLoanAmount = unwrap(
            ud_sub(ud_mul(ud(amountBase), leverage), ud(amountBase))
        );

        // Create new position
        uint256 ID = IDs[msg.sender].length;
        IDs[msg.sender].push(ID);

        Position memory position = Position({
            baseAsset: baseAsset,
            leveragedAsset: leveragedAsset,
            amount: amountBase,
            leverage: leverage,
            isLong: false,
            initialAmount: flashLoanAmount,
            isClosed: false
        });

        positions[msg.sender][ID] = position;

        // Prepare flash loan parameters
        FlashloanParams memory flashParams = FlashloanParams({
            user: msg.sender,
            nonCollateralAsset: leveragedAsset,
            amount: amountBase + flashLoanAmount,
            isLong: false,
            isClose: false,
            positionId: ID // ADDED: Pass position ID
        });

        bytes memory params = abi.encode(flashParams);

        // Execute flash loan
        getFlashloan(baseAsset, flashLoanAmount, params);

        emit PositionOpened(
            msg.sender,
            ID,
            baseAsset,
            leveragedAsset,
            amountBase,
            unwrap(leverage)
        );

        return ID;
    }

    /**
     * @notice Execute short position setup
     * @param baseAsset Base asset address
     * @param liquidityBase Total liquidity in base asset
     * @param flashLoanAmount Flash loan amount
     * @param leveragedAsset Leveraged asset address
     */
    function executeShort(
        address baseAsset,
        uint256 liquidityBase,
        uint256 flashLoanAmount,
        address leveragedAsset
    ) private {
        // Supply collateral to Bonzo
        _approveToken(baseAsset, address(bonzoPool), liquidityBase);
        bonzoPool.supply(baseAsset, liquidityBase, address(this), 0);

        // Calculate borrow amount
        uint256 price = getPrice(leveragedAsset, baseAsset);
        uint8 decimalsLeveraged = _getDecimals(leveragedAsset);
        uint8 decimalsBase = _getDecimals(baseAsset);

        uint256 borrowAmount;
        if (decimalsLeveraged > decimalsBase) {
            borrowAmount =
                (flashLoanAmount *
                    10 ** (decimalsLeveraged - decimalsBase) *
                    openFlashConstant) /
                (price * 10 ** decimalsLeveraged);
        } else {
            borrowAmount =
                (flashLoanAmount * openFlashConstant) /
                (price * 10 ** (decimalsBase - decimalsLeveraged));
        }

        // Borrow from Bonzo
        bonzoPool.borrow(leveragedAsset, borrowAmount, 2, 0, address(this));

        // Swap borrowed asset to base asset
        swapExactInputSingle(leveragedAsset, baseAsset, borrowAmount);
    }

    /**
     * @notice Close a short position
     * @param ID Position ID
     */
    function closePosition(uint256 ID) external returns (bool) {
        require(
            positions[msg.sender][ID].baseAsset != address(0),
            "No position found"
        );
        require(!positions[msg.sender][ID].isClosed, "Position already closed");

        positions[msg.sender][ID].isClosed = true;
        Position memory posParams = positions[msg.sender][ID];

        // Get total debt
        (, uint256 totalDebtBase, , , , ) = bonzoPool.getUserAccountData(
            address(this)
        );

        address flashloanAsset;
        uint256 flashLoanAmount;

        if (posParams.isLong) {
            flashloanAsset = posParams.baseAsset;
            flashLoanAmount = (totalDebtBase * closeFlashConstant) / 1e18;
        } else {
            flashloanAsset = posParams.leveragedAsset;
            uint256 price = getPrice(flashloanAsset, posParams.baseAsset);
            flashLoanAmount = (totalDebtBase * closeFlashConstant) / price;
        }

        FlashloanParams memory flashParams = FlashloanParams({
            user: msg.sender,
            nonCollateralAsset: flashloanAsset,
            amount: flashLoanAmount,
            isLong: posParams.isLong,
            isClose: true,
            positionId: ID // ADDED: Pass position ID
        });

        bytes memory params = abi.encode(flashParams);
        getFlashloan(flashloanAsset, flashLoanAmount, params);

        emit PositionClosed(msg.sender, ID);
        return true;
    }

    /**
     * @notice Execute close short position
     * @param flashParams Flash loan parameters
     * @param flashLoanAmount Flash loan amount
     * @param loanAmount Total loan amount including fee
     */
    function executeCloseShort(
        FlashloanParams memory flashParams,
        uint256 flashLoanAmount,
        uint256 loanAmount
    ) private {
        // FIXED: Use the position ID from flashParams instead of hardcoded 0
        Position memory positionParams = positions[flashParams.user][
            flashParams.positionId
        ];

        // Repay borrowed asset to Bonzo
        _approveToken(
            positionParams.leveragedAsset,
            address(bonzoPool),
            flashLoanAmount
        );
        bonzoPool.repay(
            positionParams.leveragedAsset,
            flashLoanAmount,
            2,
            address(this)
        );

        // Withdraw collateral
        uint256 swapAmount;
        {
            uint256 balance_t0 = _getBalance(
                positionParams.baseAsset,
                address(this)
            );
            bonzoPool.withdraw(
                positionParams.baseAsset,
                type(uint256).max,
                address(this)
            );
            uint256 balance_t1 = _getBalance(
                positionParams.baseAsset,
                address(this)
            );
            swapAmount = balance_t1 - balance_t0;
        }

        // Swap base asset back to leveraged asset
        uint256 amountOut = swapExactInputSingle(
            positionParams.baseAsset,
            positionParams.leveragedAsset,
            swapAmount
        );

        // Return profit/loss to user
        if (amountOut > loanAmount) {
            uint256 userProfit = amountOut - loanAmount;
            _safeTransfer(
                positionParams.leveragedAsset,
                flashParams.user,
                userProfit
            );
        }
    }

    /**
     * @notice Request flash loan from Bonzo
     * @param asset Asset to borrow
     * @param amount Amount to borrow
     * @param params Encoded parameters
     */
    function getFlashloan(
        address asset,
        uint256 amount,
        bytes memory params
    ) private {
        address[] memory assets = new address[](1);
        assets[0] = asset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // No debt (must repay in same transaction)

        bonzoPool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }

    /**
     * @notice Flash loan callback function
     * @param assets Borrowed assets
     * @param amounts Borrowed amounts
     * @param premiums Flash loan fees
     * @param initiator Flash loan initiator
     * @param _params Encoded parameters
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata _params
    ) external override returns (bool) {
        require(msg.sender == address(bonzoPool), "Not Bonzo");
        require(initiator == address(this), "Only from this contract");

        FlashloanParams memory params = abi.decode(_params, (FlashloanParams));

        if (!params.isClose) {
            if (!params.isLong) {
                executeShort(
                    assets[0],
                    params.amount,
                    amounts[0] + premiums[0],
                    params.nonCollateralAsset
                );
            }
        } else {
            if (!params.isLong) {
                executeCloseShort(params, amounts[0], amounts[0] + premiums[0]);
            }
        }

        // Approve Bonzo to pull repayment
        _approveToken(assets[0], address(bonzoPool), amounts[0] + premiums[0]);

        // Transfer any remaining balance to user
        uint256 balance = _getBalance(assets[0], address(this));
        uint256 repayAmount = amounts[0] + premiums[0];

        if (balance > repayAmount) {
            uint256 leftOver = balance - repayAmount;
            _safeTransfer(assets[0], params.user, leftOver);
        }

        return true;
    }

    /**
     * @notice Emergency withdraw function
     * @param asset Asset to withdraw
     */
    function emergencyWithdraw(address asset) external onlyOwner {
        uint256 balance = _getBalance(asset, address(this));
        _safeTransfer(asset, msg.sender, balance);
    }

    /**
     * @notice View account data on Bonzo
     */
    function viewAccountData()
        public
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return bonzoPool.getUserAccountData(address(this));
    }

    // ===========================
    // UD60x18 Helper Functions
    // ===========================

    function ud(uint256 x) private pure returns (UD60x18) {
        return UD60x18.wrap(x);
    }

    function unwrap(UD60x18 x) private pure returns (uint256) {
        return UD60x18.unwrap(x);
    }

    function ud_add(UD60x18 x, UD60x18 y) private pure returns (UD60x18) {
        return UD60x18.wrap(UD60x18.unwrap(x) + UD60x18.unwrap(y));
    }

    function ud_sub(UD60x18 x, UD60x18 y) private pure returns (UD60x18) {
        require(unwrap(x) >= unwrap(y), "UD60x18: subtraction underflow");
        return UD60x18.wrap(UD60x18.unwrap(x) - UD60x18.unwrap(y));
    }

    function ud_mul(UD60x18 x, UD60x18 y) private pure returns (UD60x18) {
        return UD60x18.wrap((UD60x18.unwrap(x) * UD60x18.unwrap(y)) / 1e18);
    }

    function ud_div(UD60x18 x, UD60x18 y) private pure returns (UD60x18) {
        require(unwrap(y) != 0, "UD60x18: division by zero");
        return UD60x18.wrap((UD60x18.unwrap(x) * 1e18) / UD60x18.unwrap(y));
    }
}
