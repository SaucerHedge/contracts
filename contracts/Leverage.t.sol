// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./Leverage.sol";
import "./interfaces/IBonzo.sol";

/**
 * @title LeverageTest
 * @notice Comprehensive unit tests for Leverage contract
 */
contract LeverageTest is Test {
    Leverage public leverage;
    
    // Mock addresses
    address public mockBonzoPool;
    address public mockRouter;
    address public mockFactory;
    address public mockQuoter;
    address public mockBaseAsset;    // e.g., USDC
    address public mockLeveragedAsset; // e.g., HBAR
    address public user;
    address public owner;
    
    // Constants
    uint256 constant PRECISION = 1e18;
    uint256 constant INITIAL_BALANCE = 10000 * PRECISION;
    
    // Custom type
    type UD60x18 is uint256;
    
    function setUp() public {
        // Setup mock addresses
        mockBonzoPool = makeAddr("bonzoPool");
        mockRouter = makeAddr("router");
        mockFactory = makeAddr("factory");
        mockQuoter = makeAddr("quoter");
        mockBaseAsset = makeAddr("baseAsset");
        mockLeveragedAsset = makeAddr("leveragedAsset");
        user = makeAddr("user");
        owner = address(this); // Test contract is owner
        
        // CRITICAL: Mock WHBAR() call on router BEFORE deploying Leverage
        // The SaucerSwapper constructor needs this
        // WHBAR testnet address: 0x0000000000000000000000000000000000003aD1 (checksummed)
        address testnetWHBAR = address(0x0000000000000000000000000000000000003aD1);
        
        vm.mockCall(
            mockRouter,
            abi.encodeWithSignature("WHBAR()"),
            abi.encode(testnetWHBAR)
        );
        
        // Deploy leverage contract
        leverage = new Leverage(
            mockBonzoPool,
            mockRouter,
            mockFactory,
            mockQuoter
        );
        
        // Label addresses
        vm.label(address(leverage), "Leverage");
        vm.label(mockBonzoPool, "BonzoPool");
        vm.label(mockRouter, "Router");
        vm.label(mockFactory, "Factory");
        vm.label(mockQuoter, "Quoter");
        vm.label(mockBaseAsset, "BaseAsset");
        vm.label(mockLeveragedAsset, "LeveragedAsset");
        vm.label(testnetWHBAR, "WHBAR-Testnet");
        vm.label(user, "User");
    }
    
    // ===========================
    // Constructor Tests
    // ===========================
    
    function test_constructor() public {
        assertEq(
            address(leverage.bonzoPool()),
            mockBonzoPool,
            "Bonzo pool should be set"
        );
        assertEq(
            leverage.owner(),
            owner,
            "Owner should be set to deployer"
        );
        
        // Verify parent SaucerSwapper was initialized correctly
        assertEq(
            address(leverage.saucerSwapRouter()),
            mockRouter,
            "Router should be set"
        );
        assertEq(
            address(leverage.saucerSwapFactory()),
            mockFactory,
            "Factory should be set"
        );
    }
    
    function test_constructor_withZeroAddresses() public {
        // Even with zero addresses for bonzo and quoter, we need valid router/factory
        // and WHBAR mock for SaucerSwapper parent constructor
        address validRouter = makeAddr("validRouter");
        address validFactory = makeAddr("validFactory");
        address testnetWHBAR = address(0x0000000000000000000000000000000000003aD1);
        
        vm.mockCall(
            validRouter,
            abi.encodeWithSignature("WHBAR()"),
            abi.encode(testnetWHBAR)
        );
        
        Leverage newLeverage = new Leverage(
            address(0),      // bonzo can be zero
            validRouter,     // router must be non-zero
            validFactory,    // factory must be non-zero
            address(0)       // quoter can be zero
        );
        
        assertEq(
            address(newLeverage.bonzoPool()),
            address(0),
            "Should accept zero address for bonzo pool"
        );
        assertEq(
            address(newLeverage.saucerSwapQuoter()),
            address(0),
            "Should accept zero address for quoter"
        );
    }
    
    function test_constructor_flashConstants() public {
        assertEq(
            leverage.openFlashConstant(),
            1.005e18,
            "Open flash constant should be 1.005e18"
        );
        assertEq(
            leverage.closeFlashConstant(),
            1.009e16,
            "Close flash constant should be 1.009e16"
        );
    }
    
    function test_constructor_revertsWithZeroRouter() public {
        vm.expectRevert("Invalid router address");
        new Leverage(
            mockBonzoPool,
            address(0),     // Zero router
            mockFactory,
            mockQuoter
        );
    }
    
    function test_constructor_revertsWithZeroFactory() public {
        address validRouter = makeAddr("validRouter");
        address testnetWHBAR = address(0x0000000000000000000000000000000000003aD1);
        
        vm.mockCall(
            validRouter,
            abi.encodeWithSignature("WHBAR()"),
            abi.encode(testnetWHBAR)
        );
        
        vm.expectRevert("Invalid factory address");
        new Leverage(
            mockBonzoPool,
            validRouter,
            address(0),     // Zero factory
            mockQuoter
        );
    }
    
    function test_constructor_revertsIfWHBARIsZero() public {
        address validRouter = makeAddr("validRouter");
        
        // Mock WHBAR() to return zero
        vm.mockCall(
            validRouter,
            abi.encodeWithSignature("WHBAR()"),
            abi.encode(address(0))
        );
        
        vm.expectRevert("Failed to get WHBAR address");
        new Leverage(
            mockBonzoPool,
            validRouter,
            mockFactory,
            mockQuoter
        );
    }
    
    // ===========================
    // Owner Modifier Tests
    // ===========================
    
    function test_onlyOwner_allowsOwner() public {
        // Owner should be able to call owner-only functions
        bool success = leverage.updateFlashConstant(1.01e18, 1.01e16);
        assertTrue(success, "Owner should be able to update constants");
    }
    
    function test_onlyOwner_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        leverage.updateFlashConstant(1.01e18, 1.01e16);
    }
    
    function test_onlyOwner_emergencyWithdraw() public {
        // Mock the balance call that emergencyWithdraw makes
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature("balanceOf(address)", address(leverage)),
            abi.encode(100 * PRECISION)
        );
        
        // Mock the transfer call
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                owner,
                100 * PRECISION
            ),
            abi.encode(true)
        );
        
        // Owner can call emergency withdraw
        leverage.emergencyWithdraw(mockBaseAsset);
        // Should not revert
    }
    
    function test_onlyOwner_emergencyWithdraw_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        leverage.emergencyWithdraw(mockBaseAsset);
    }
    
    // ===========================
    // getUserIDlength Tests
    // ===========================
    
    function test_getUserIDlength_initiallyZero() public {
        uint256 length = leverage.getUserIDlength(user);
        assertEq(length, 0, "User should have no positions initially");
    }
    
    function test_getUserIDlength_differentUsers() public {
        address user2 = makeAddr("user2");
        
        uint256 length1 = leverage.getUserIDlength(user);
        uint256 length2 = leverage.getUserIDlength(user2);
        
        assertEq(length1, 0, "User1 should have no positions");
        assertEq(length2, 0, "User2 should have no positions");
    }
    
    // ===========================
    // updateFlashConstant Tests
    // ===========================
    
    function test_updateFlashConstant_success() public {
        uint256 newOpenConstant = 1.01e18;
        uint256 newCloseConstant = 1.02e16;
        
        bool success = leverage.updateFlashConstant(
            newOpenConstant,
            newCloseConstant
        );
        
        assertTrue(success, "Should return true");
        assertEq(
            leverage.openFlashConstant(),
            newOpenConstant,
            "Open constant should be updated"
        );
        assertEq(
            leverage.closeFlashConstant(),
            newCloseConstant,
            "Close constant should be updated"
        );
    }
    
    function test_updateFlashConstant_withZeroValues() public {
        bool success = leverage.updateFlashConstant(0, 0);
        
        assertTrue(success, "Should accept zero values");
        assertEq(leverage.openFlashConstant(), 0, "Should be updated to 0");
        assertEq(leverage.closeFlashConstant(), 0, "Should be updated to 0");
    }
    
    function test_updateFlashConstant_withLargeValues() public {
        uint256 largeValue = type(uint256).max;
        
        bool success = leverage.updateFlashConstant(largeValue, largeValue);
        
        assertTrue(success, "Should accept large values");
        assertEq(
            leverage.openFlashConstant(),
            largeValue,
            "Should be updated to large value"
        );
    }
    
    function test_updateFlashConstant_multipleUpdates() public {
        // First update
        leverage.updateFlashConstant(1.01e18, 1.01e16);
        assertEq(leverage.openFlashConstant(), 1.01e18);
        
        // Second update
        leverage.updateFlashConstant(1.02e18, 1.02e16);
        assertEq(leverage.openFlashConstant(), 1.02e18);
        
        // Third update
        leverage.updateFlashConstant(1.03e18, 1.03e16);
        assertEq(leverage.openFlashConstant(), 1.03e18);
    }
    
    // ===========================
    // Position Structure Tests
    // ===========================
    
    function test_positions_defaultValues() public {
        // Query a non-existent position
        (
            address baseAsset,
            address leveragedAsset,
            uint256 amount,
            ,
            bool isLong,
            uint256 initialAmount,
            bool isClosed
        ) = leverage.positions(user, 0);
        
        assertEq(baseAsset, address(0), "Default base asset should be zero");
        assertEq(leveragedAsset, address(0), "Default leveraged asset should be zero");
        assertEq(amount, 0, "Default amount should be zero");
        assertFalse(isLong, "Default isLong should be false");
        assertEq(initialAmount, 0, "Default initial amount should be zero");
        assertFalse(isClosed, "Default isClosed should be false");
    }
    
    // ===========================
    // viewAccountData Tests
    // ===========================
    
    function test_viewAccountData_callsExternalContract() public {
        // Mock the external call
        vm.mockCall(
            mockBonzoPool,
            abi.encodeWithSelector(
                IBonzoPool.getUserAccountData.selector,
                address(leverage)
            ),
            abi.encode(1000, 500, 500, 8000, 7500, 2e18)
        );
        
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = leverage.viewAccountData();
        
        assertEq(totalCollateralBase, 1000, "Total collateral should match");
        assertEq(totalDebtBase, 500, "Total debt should match");
        assertEq(availableBorrowBase, 500, "Available borrow should match");
        assertEq(currentLiquidationThreshold, 8000, "Liquidation threshold should match");
        assertEq(ltv, 7500, "LTV should match");
        assertEq(healthFactor, 2e18, "Health factor should match");
    }
    
    function test_viewAccountData_withZeroValues() public {
        // Mock zero values
        vm.mockCall(
            mockBonzoPool,
            abi.encodeWithSelector(
                IBonzoPool.getUserAccountData.selector,
                address(leverage)
            ),
            abi.encode(0, 0, 0, 0, 0, 0)
        );
        
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,
            uint256 healthFactor
        ) = leverage.viewAccountData();
        
        assertEq(totalCollateralBase, 0, "Should return zero");
        assertEq(totalDebtBase, 0, "Should return zero");
        assertEq(healthFactor, 0, "Should return zero");
    }
    
    // ===========================
    // Emergency Withdraw Tests
    // ===========================
    
    function test_emergencyWithdraw_withZeroBalance() public {
        // Mock balance as zero
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature("balanceOf(address)", address(leverage)),
            abi.encode(0)
        );
        
        // Mock transfer (even though amount is 0, the call is still made)
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature("transfer(address,uint256)", owner, 0),
            abi.encode(true)
        );
        
        // Should not revert even with zero balance
        leverage.emergencyWithdraw(mockBaseAsset);
    }
    
    function test_emergencyWithdraw_onlyOwnerCanCall() public {
        vm.prank(user);
        vm.expectRevert("Not owner");
        leverage.emergencyWithdraw(mockBaseAsset);
    }
    
    // ===========================
    // FlashloanParams Structure Tests
    // ===========================
    
    function test_flashloanParams_encoding() public {
        // Create sample params
        Leverage.FlashloanParams memory params = Leverage.FlashloanParams({
            user: user,
            nonCollateralAsset: mockLeveragedAsset,
            amount: 1000 * PRECISION,
            isLong: false,
            isClose: false,
            positionId: 0
        });
        
        // Encode
        bytes memory encoded = abi.encode(params);
        
        // Decode
        Leverage.FlashloanParams memory decoded = abi.decode(
            encoded,
            (Leverage.FlashloanParams)
        );
        
        // Verify
        assertEq(decoded.user, user, "User should match");
        assertEq(
            decoded.nonCollateralAsset,
            mockLeveragedAsset,
            "Asset should match"
        );
        assertEq(decoded.amount, 1000 * PRECISION, "Amount should match");
        assertFalse(decoded.isLong, "isLong should match");
        assertFalse(decoded.isClose, "isClose should match");
        assertEq(decoded.positionId, 0, "positionId should match");
    }
    
    // ===========================
    // Edge Case Tests
    // ===========================
    
    function test_getUserIDlength_withMultipleUsers() public {
        address[] memory users = new address[](5);
        for (uint i = 0; i < 5; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            uint256 length = leverage.getUserIDlength(users[i]);
            assertEq(length, 0, "Each user should start with 0 positions");
        }
    }
    
    function test_updateFlashConstant_emitsNoEvent() public {
        // Note: This function doesn't emit events, which might be worth adding
        vm.recordLogs();
        leverage.updateFlashConstant(1.01e18, 1.01e16);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "Should not emit any events");
    }
    
    function test_constants_initialValues() public {
        // Verify initial constants are set correctly
        assertGt(leverage.openFlashConstant(), 1e18, "Open constant should be > 1");
        assertLt(leverage.closeFlashConstant(), 1e18, "Close constant should be < 1");
    }
    
    // ===========================
    // Gas Tests
    // ===========================
    
    function test_gas_getUserIDlength() public {
        uint256 gasBefore = gasleft();
        leverage.getUserIDlength(user);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 15000, "Gas should be reasonable");
    }
    
    function test_gas_updateFlashConstant() public {
        uint256 gasBefore = gasleft();
        leverage.updateFlashConstant(1.01e18, 1.01e16);
        uint256 gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 50000, "Gas should be reasonable");
    }
    
    function test_gas_viewAccountData() public {
        // Mock the call
        vm.mockCall(
            mockBonzoPool,
            abi.encodeWithSelector(
                IBonzoPool.getUserAccountData.selector,
                address(leverage)
            ),
            abi.encode(1000, 500, 500, 8000, 7500, 2e18)
        );
        
        uint256 gasBefore = gasleft();
        leverage.viewAccountData();
        uint256 gasUsed = gasBefore - gasleft();
        
        // View function should be cheap
        assertLt(gasUsed, 100000, "Gas should be reasonable for view function");
    }
    
    // ===========================
    // Access Control Tests
    // ===========================
    
    function test_accessControl_ownerCanUpdateConstants() public {
        vm.prank(owner);
        bool success = leverage.updateFlashConstant(1.01e18, 1.01e16);
        assertTrue(success, "Owner should succeed");
    }
    
    function test_accessControl_ownerCanEmergencyWithdraw() public {
        // Mock balance and transfer calls
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature("balanceOf(address)", address(leverage)),
            abi.encode(100 * PRECISION)
        );
        
        vm.mockCall(
            mockBaseAsset,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                owner,
                100 * PRECISION
            ),
            abi.encode(true)
        );
        
        vm.prank(owner);
        // Should not revert
        leverage.emergencyWithdraw(mockBaseAsset);
    }
    
    function test_accessControl_nonOwnerCannotUpdate() public {
        vm.startPrank(user);
        vm.expectRevert("Not owner");
        leverage.updateFlashConstant(1.01e18, 1.01e16);
        vm.stopPrank();
    }
    
    function test_accessControl_nonOwnerCannotWithdraw() public {
        vm.startPrank(user);
        vm.expectRevert("Not owner");
        leverage.emergencyWithdraw(mockBaseAsset);
        vm.stopPrank();
    }
    
    // ===========================
    // State Consistency Tests
    // ===========================
    
    function test_stateConsistency_afterMultipleUpdates() public {
        // Update 1
        leverage.updateFlashConstant(1.01e18, 1.01e16);
        uint256 open1 = leverage.openFlashConstant();
        uint256 close1 = leverage.closeFlashConstant();
        
        // Update 2
        leverage.updateFlashConstant(1.02e18, 1.02e16);
        uint256 open2 = leverage.openFlashConstant();
        uint256 close2 = leverage.closeFlashConstant();
        
        // Verify changes
        assertNotEq(open1, open2, "Values should be different");
        assertNotEq(close1, close2, "Values should be different");
        assertEq(open2, 1.02e18, "Should be latest value");
        assertEq(close2, 1.02e16, "Should be latest value");
    }
    
    function test_stateConsistency_positionIsolation() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        
        // Both users should have independent position arrays
        uint256 len1 = leverage.getUserIDlength(user1);
        uint256 len2 = leverage.getUserIDlength(user2);
        
        assertEq(len1, 0, "User1 should start empty");
        assertEq(len2, 0, "User2 should start empty");
    }
    
    // ===========================
    // Boundary Tests
    // ===========================
    
    function test_boundary_maxUint256FlashConstant() public {
        uint256 maxValue = type(uint256).max;
        
        bool success = leverage.updateFlashConstant(maxValue, maxValue);
        assertTrue(success, "Should handle max uint256");
        assertEq(leverage.openFlashConstant(), maxValue);
    }
    
    function test_boundary_zeroFlashConstant() public {
        bool success = leverage.updateFlashConstant(0, 0);
        assertTrue(success, "Should handle zero values");
        assertEq(leverage.openFlashConstant(), 0);
        assertEq(leverage.closeFlashConstant(), 0);
    }
    
    // ===========================
    // Integration Readiness Tests
    // ===========================
    
    function test_integration_bonzoPoolSet() public {
        assertTrue(
            address(leverage.bonzoPool()) != address(0),
            "Bonzo pool should be set for integration"
        );
    }
    
    function test_integration_ownerSet() public {
        assertTrue(
            leverage.owner() != address(0),
            "Owner should be set"
        );
    }
}

/**
 * @title MockBonzoPool
 * @notice Mock contract for testing Bonzo pool interactions
 */
contract MockBonzoPool is IBonzoPool {
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;
    
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        collateral[onBehalfOf] += amount;
    }
    
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external override {
        debt[onBehalfOf] += amount;
    }
    
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external override returns (uint256) {
        if (debt[onBehalfOf] >= amount) {
            debt[onBehalfOf] -= amount;
            return amount;
        } else {
            uint256 repaid = debt[onBehalfOf];
            debt[onBehalfOf] = 0;
            return repaid;
        }
    }
    
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        uint256 withdrawn = amount == type(uint256).max 
            ? collateral[msg.sender] 
            : amount;
        
        if (collateral[msg.sender] >= withdrawn) {
            collateral[msg.sender] -= withdrawn;
            return withdrawn;
        }
        return 0;
    }
    
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external override {
        // Mock flash loan - would call back to receiver
        uint256[] memory premiums = new uint256[](amounts.length);
        for (uint i = 0; i < amounts.length; i++) {
            premiums[i] = amounts[i] / 1000; // 0.1% fee
        }
        
        IFlashLoanReceiver(receiverAddress).executeOperation(
            assets,
            amounts,
            premiums,
            msg.sender,
            params
        );
    }
    
    function getUserAccountData(
        address user
    ) external view override returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return (
            collateral[user],
            debt[user],
            collateral[user] - debt[user],
            8000,
            7500,
            collateral[user] > 0 && debt[user] > 0 
                ? (collateral[user] * 1e18) / debt[user] 
                : type(uint256).max
        );
    }
}