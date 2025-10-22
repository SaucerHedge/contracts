// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Leverage.sol";

/**
 * @title Factory
 * @notice Factory contract for deploying Leverage contracts
 * @dev Each user can have their own Leverage contract instance
 */
contract Factory {
    // Mapping: user address => leverage contract address
    mapping(address => address) public leverageContracts;

    address public immutable bonzoPool;
    address public immutable saucerRouter;
    address public immutable saucerFactory;
    address public immutable saucerQuoter;

    event LeverageContractCreated(
        address indexed user,
        address leverageContract
    );

    constructor(
        address _bonzoPool,
        address _saucerRouter,
        address _saucerFactory,
        address _saucerQuoter
    ) {
        require(_bonzoPool != address(0), "Invalid Bonzo pool address");
        require(_saucerRouter != address(0), "Invalid router address");
        require(_saucerFactory != address(0), "Invalid factory address");

        bonzoPool = _bonzoPool;
        saucerRouter = _saucerRouter;
        saucerFactory = _saucerFactory;
        saucerQuoter = _saucerQuoter;
    }

    /**
     * @notice Get leverage contract for a user
     * @param user User address
     * @return Leverage contract address
     */
    function getLeverageContract(address user) external view returns (address) {
        return leverageContracts[user];
    }

    /**
     * @notice Create a new leverage contract for the caller
     * @return Address of the new leverage contract
     */
    function createLeverageContract() external returns (address) {
        require(
            leverageContracts[msg.sender] == address(0),
            "Leverage contract already exists"
        );

        Leverage leverageContract = new Leverage(
            bonzoPool,
            saucerRouter,
            saucerFactory,
            saucerQuoter
        );

        // Transfer ownership to the caller if needed
        // Note: Current Leverage design sets owner to msg.sender (Factory)
        // If you need caller as owner, modify Leverage constructor

        leverageContracts[msg.sender] = address(leverageContract);

        emit LeverageContractCreated(msg.sender, address(leverageContract));

        return address(leverageContract);
    }

    /**
     * @notice Create a leverage contract for any address (useful for contracts like SaucerHedger)
     * @param owner The address that will own the leverage contract
     * @return Address of the new leverage contract
     */
    function createLeverageContractFor(
        address owner
    ) external returns (address) {
        require(owner != address(0), "Invalid owner address");
        require(
            leverageContracts[owner] == address(0),
            "Leverage contract already exists for this owner"
        );

        Leverage leverageContract = new Leverage(
            bonzoPool,
            saucerRouter,
            saucerFactory,
            saucerQuoter
        );

        leverageContracts[owner] = address(leverageContract);

        emit LeverageContractCreated(owner, address(leverageContract));

        return address(leverageContract);
    }

    /**
     * @notice Check if user has a leverage contract
     * @param user User address
     * @return true if user has a leverage contract, false otherwise
     */
    function hasLeverageContract(address user) external view returns (bool) {
        return leverageContracts[user] != address(0);
    }
}
