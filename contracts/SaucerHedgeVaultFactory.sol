// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SaucerHedgeVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SaucerHedgeVaultFactory
 * @notice Factory for deploying SaucerHedge vaults for different assets
 * @dev Manages multiple vaults (USDC, HBAR, etc.) with standardized configuration
 */
contract SaucerHedgeVaultFactory is Ownable {
    // Array of all deployed vaults
    address[] public allVaults;

    // Mapping: asset => vault address
    mapping(address => address) public assetToVault;

    // Mapping: vault => is valid
    mapping(address => bool) public isValidVault;

    // Default configuration
    address public defaultVincentPKP;
    address public defaultSaucerHedger;
    address public defaultFeeRecipient;
    uint256 public defaultPerformanceFee;

    // Events
    event VaultCreated(
        address indexed asset,
        address indexed vault,
        string name,
        string symbol
    );
    event DefaultConfigUpdated(
        address vincentPKP,
        address saucerHedger,
        address feeRecipient,
        uint256 performanceFee
    );

    constructor(
        address _vincentPKP,
        address _saucerHedger,
        address _feeRecipient
    ) Ownable(msg.sender) {
        require(_vincentPKP != address(0), "Invalid Vincent PKP");
        require(_saucerHedger != address(0), "Invalid SaucerHedger");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        defaultVincentPKP = _vincentPKP;
        defaultSaucerHedger = _saucerHedger;
        defaultFeeRecipient = _feeRecipient;
        defaultPerformanceFee = 200; // 2%
    }

    /**
     * @notice Create a new vault for an asset
     * @param asset Underlying asset address (USDC, WHBAR, etc.)
     * @param name Vault token name
     * @param symbol Vault token symbol
     * @return vault Address of deployed vault
     */
    function createVault(
        address asset,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address vault) {
        require(assetToVault[asset] == address(0), "Vault already exists");
        require(asset != address(0), "Invalid asset");

        // Deploy new vault with 7 parameters (including initialOwner)
        SaucerHedgeVault newVault = new SaucerHedgeVault(
            IERC20(asset), // 1. asset address
            name, // 2. vault token name
            symbol, // 3. vault token symbol
            defaultVincentPKP, // 4. Vincent PKP
            defaultSaucerHedger, // 5. SaucerHedger contract
            defaultFeeRecipient, // 6. fee recipient
            msg.sender // 7. initial owner (the factory owner)
        );

        vault = address(newVault);

        // Record vault
        allVaults.push(vault);
        assetToVault[asset] = vault;
        isValidVault[vault] = true;

        emit VaultCreated(asset, vault, name, symbol);

        return vault;
    }

    /**
     * @notice Create vaults for multiple assets at once
     */
    function createVaultsBatch(
        address[] memory assets,
        string[] memory names,
        string[] memory symbols
    ) external onlyOwner returns (address[] memory vaults) {
        require(
            assets.length == names.length && assets.length == symbols.length,
            "Length mismatch"
        );

        vaults = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            require(
                assetToVault[assets[i]] == address(0),
                "Vault already exists"
            );
            require(assets[i] != address(0), "Invalid asset");

            // Deploy new vault with 7 parameters
            SaucerHedgeVault newVault = new SaucerHedgeVault(
                IERC20(assets[i]), // 1. asset address
                names[i], // 2. vault token name
                symbols[i], // 3. vault token symbol
                defaultVincentPKP, // 4. Vincent PKP
                defaultSaucerHedger, // 5. SaucerHedger contract
                defaultFeeRecipient, // 6. fee recipient
                msg.sender // 7. initial owner
            );

            address vaultAddress = address(newVault);
            vaults[i] = vaultAddress;

            // Record vault
            allVaults.push(vaultAddress);
            assetToVault[assets[i]] = vaultAddress;
            isValidVault[vaultAddress] = true;

            emit VaultCreated(assets[i], vaultAddress, names[i], symbols[i]);
        }

        return vaults;
    }

    /**
     * @notice Get vault for a specific asset
     */
    function getVault(address asset) external view returns (address) {
        return assetToVault[asset];
    }

    /**
     * @notice Get all deployed vaults
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @notice Get total number of vaults
     */
    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @notice Check if vault exists for asset
     */
    function vaultExists(address asset) external view returns (bool) {
        return assetToVault[asset] != address(0);
    }

    /**
     * @notice Update default configuration for new vaults
     */
    function updateDefaultConfig(
        address _vincentPKP,
        address _saucerHedger,
        address _feeRecipient,
        uint256 _performanceFee
    ) external onlyOwner {
        require(_vincentPKP != address(0), "Invalid Vincent PKP");
        require(_saucerHedger != address(0), "Invalid SaucerHedger");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_performanceFee <= 1000, "Fee too high"); // Max 10%

        defaultVincentPKP = _vincentPKP;
        defaultSaucerHedger = _saucerHedger;
        defaultFeeRecipient = _feeRecipient;
        defaultPerformanceFee = _performanceFee;

        emit DefaultConfigUpdated(
            _vincentPKP,
            _saucerHedger,
            _feeRecipient,
            _performanceFee
        );
    }

    /**
     * @notice Update Vincent PKP for a specific vault
     */
    function updateVincentPKPForVault(
        address vaultAddress,
        address _newPKP
    ) external onlyOwner {
        require(isValidVault[vaultAddress], "Invalid vault");
        require(_newPKP != address(0), "Invalid PKP");
        SaucerHedgeVault(vaultAddress).setVincentPKP(_newPKP);
    }

    /**
     * @notice Update Vincent PKP for all existing vaults
     */
    function updateVincentPKPForAllVaults(address _newPKP) external onlyOwner {
        require(_newPKP != address(0), "Invalid PKP");

        for (uint256 i = 0; i < allVaults.length; i++) {
            SaucerHedgeVault(allVaults[i]).setVincentPKP(_newPKP);
        }

        // Update default for future vaults
        defaultVincentPKP = _newPKP;
    }

    /**
     * @notice Update SaucerHedger for a specific vault
     */
    function updateSaucerHedgerForVault(
        address vaultAddress,
        address _saucerHedger
    ) external onlyOwner {
        require(isValidVault[vaultAddress], "Invalid vault");
        require(_saucerHedger != address(0), "Invalid SaucerHedger");
        SaucerHedgeVault(vaultAddress).setSaucerHedger(_saucerHedger);
    }

    /**
     * @notice Pause a specific vault
     */
    function pauseVault(address vaultAddress) external onlyOwner {
        require(isValidVault[vaultAddress], "Invalid vault");
        SaucerHedgeVault(vaultAddress).pause();
    }

    /**
     * @notice Unpause a specific vault
     */
    function unpauseVault(address vaultAddress) external onlyOwner {
        require(isValidVault[vaultAddress], "Invalid vault");
        SaucerHedgeVault(vaultAddress).unpause();
    }

    /**
     * @notice Pause all vaults (emergency)
     */
    function pauseAllVaults() external onlyOwner {
        for (uint256 i = 0; i < allVaults.length; i++) {
            SaucerHedgeVault(allVaults[i]).pause();
        }
    }

    /**
     * @notice Unpause all vaults
     */
    function unpauseAllVaults() external onlyOwner {
        for (uint256 i = 0; i < allVaults.length; i++) {
            SaucerHedgeVault(allVaults[i]).unpause();
        }
    }

    /**
     * @notice Get vault details
     */
    function getVaultDetails(
        address vaultAddress
    )
        external
        view
        returns (
            address asset,
            string memory name,
            string memory symbol,
            uint256 totalAssets,
            uint256 totalSupply,
            address vincentPKP,
            address saucerHedger,
            uint256 performanceFee
        )
    {
        require(isValidVault[vaultAddress], "Invalid vault");

        SaucerHedgeVault vault = SaucerHedgeVault(vaultAddress);

        asset = vault.asset();
        name = vault.name();
        symbol = vault.symbol();
        totalAssets = vault.totalAssets();
        totalSupply = vault.totalSupply();
        vincentPKP = vault.vincentPKP();
        saucerHedger = vault.saucerHedger();
        performanceFee = vault.performanceFee();

        return (
            asset,
            name,
            symbol,
            totalAssets,
            totalSupply,
            vincentPKP,
            saucerHedger,
            performanceFee
        );
    }
}
