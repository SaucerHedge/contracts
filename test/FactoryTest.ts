import {
  Client,
  AccountId,
  PrivateKey,
  ContractExecuteTransaction,
  ContractFunctionParameters,
  ContractCallQuery,
} from "@hashgraph/sdk";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * Set Vaults in VaultManager
 * Use this if you already have vault addresses
 */

// EXISTING USDC Vault from deployment
const USDC_VAULT_ADDRESS = "0xa7303803ddea114fc4f53b1070e09956b3251fe3"; // From your deployment

// We'll deploy HBAR vault or you can provide existing one
const SAUCER_HEDGE_FACTORY_ID = "0.0.7131832";
const WHBAR_ASSET_EVM = "0x546268afB164e72C7e0bf6262b0A406860d93F47"; // WHBAR 0.0.1456986

let client: Client;
let operatorAccountId: AccountId;
let vaultManagerId: string;

function hederaIdToEvmAddress(hederaId: string): string {
  const parts = hederaId.split(".");
  const num = parseInt(parts[2]);
  return "0x" + num.toString(16).padStart(40, "0");
}

async function initialize() {
  console.log(`\n⚙️  Set Vaults in VaultManager`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);

  client = Client.forTestnet();

  operatorAccountId = AccountId.fromString(process.env.HEDERA_ACCOUNT_ID!);
  const operatorPrivateKey = PrivateKey.fromStringECDSA(
    process.env.PRIVATE_KEY!
  );
  client.setOperator(operatorAccountId, operatorPrivateKey);

  vaultManagerId = process.env.VAULT_MANAGER_ID!;

  console.log(`✅ Initialized`);
  console.log(`  Account: ${operatorAccountId.toString()}`);
  console.log(`  VaultManager: ${vaultManagerId}`);
}

async function deployHBARVault() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`🏗️  Step 1: Deploying HBAR Vault (shHBAR)\n`);

  // First check if it already exists
  try {
    const vaultQuery = new ContractCallQuery()
      .setContractId(SAUCER_HEDGE_FACTORY_ID)
      .setGas(100000)
      .setFunction(
        "getVault",
        new ContractFunctionParameters().addAddress(WHBAR_ASSET_EVM)
      );

    const vaultResult = await vaultQuery.execute(client);
    const existingVault = vaultResult.getAddress(0);

    const isZero =
      existingVault.toLowerCase().replace(/^0x/, "").replace(/^0+/, "") === "";

    if (!isZero) {
      console.log(`  ✅ HBAR Vault already exists: ${existingVault}`);
      return existingVault;
    }
  } catch (error) {
    console.log(`  No existing vault found, will deploy...`);
  }

  try {
    const deployTx = new ContractExecuteTransaction()
      .setContractId(SAUCER_HEDGE_FACTORY_ID)
      .setGas(5000000)
      .setFunction(
        "createVault",
        new ContractFunctionParameters()
          .addAddress(WHBAR_ASSET_EVM)
          .addString("SaucerHedge HBAR Vault")
          .addString("shHBAR")
      );

    console.log(`  Deploying shHBAR vault...`);
    console.log(`  Asset: ${WHBAR_ASSET_EVM} (WHBAR)`);

    const deploySubmit = await deployTx.execute(client);
    const deployReceipt = await deploySubmit.getReceipt(client);

    console.log(`  ✅ Status: ${deployReceipt.status}`);
    console.log(`  📄 TX: ${deploySubmit.transactionId}`);
    console.log(
      `  🔗 HashScan: https://hashscan.io/testnet/transaction/${deploySubmit.transactionId}`
    );

    // Wait a bit for state to update
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Query the vault address
    const vaultQuery = new ContractCallQuery()
      .setContractId(SAUCER_HEDGE_FACTORY_ID)
      .setGas(100000)
      .setFunction(
        "getVault",
        new ContractFunctionParameters().addAddress(WHBAR_ASSET_EVM)
      );

    const vaultResult = await vaultQuery.execute(client);
    const vaultAddress = vaultResult.getAddress(0);

    console.log(`  🎉 HBAR Vault deployed at: ${vaultAddress}`);
    return vaultAddress;
  } catch (error: any) {
    console.error(`  ❌ Failed to deploy: ${error.message}`);
    console.log(`\n  💡 Check HashScan for details`);
    throw error;
  }
}

async function setVaultsInManager(usdcVault: string, hbarVault: string) {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`⚙️  Step 2: Setting Vaults in VaultManager\n`);

  // Ensure addresses have 0x prefix
  if (!usdcVault.startsWith("0x")) {
    usdcVault = "0x" + usdcVault;
  }
  if (!hbarVault.startsWith("0x")) {
    hbarVault = "0x" + hbarVault;
  }

  console.log(`  USDC Vault: ${usdcVault}`);
  console.log(`  HBAR Vault: ${hbarVault}`);

  // Verify neither is zero address
  const isUsdcZero =
    usdcVault.toLowerCase().replace(/^0x/, "").replace(/^0+/, "") === "";
  const isHbarZero =
    hbarVault.toLowerCase().replace(/^0x/, "").replace(/^0+/, "") === "";

  if (isUsdcZero || isHbarZero) {
    console.log(`  ❌ ERROR: Cannot set zero address as vault!`);
    throw new Error("Invalid vault address - cannot be zero");
  }

  try {
    const setVaultsTx = new ContractExecuteTransaction()
      .setContractId(vaultManagerId)
      .setGas(500000)
      .setFunction(
        "setVaults",
        new ContractFunctionParameters()
          .addAddress(usdcVault)
          .addAddress(hbarVault)
      );

    console.log(`\n  Calling setVaults()...`);
    const setVaultsSubmit = await setVaultsTx.execute(client);
    const setVaultsReceipt = await setVaultsSubmit.getReceipt(client);

    console.log(`  ✅ Status: ${setVaultsReceipt.status}`);
    console.log(`  📄 TX: ${setVaultsSubmit.transactionId}`);
    console.log(
      `  🔗 HashScan: https://hashscan.io/testnet/transaction/${setVaultsSubmit.transactionId}`
    );
  } catch (error: any) {
    console.error(`  ❌ Failed: ${error.message}`);

    if (error.message.includes("Ownable")) {
      console.log(`\n  ⚠️  You are not the owner of VaultManager!`);
      console.log(`     Current account: ${operatorAccountId.toString()}`);
      console.log(`     Only the owner can call setVaults()`);
    }

    throw error;
  }
}

async function verifyConfiguration() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`✅ Step 3: Verifying Configuration\n`);

  try {
    const vaultsQuery = new ContractCallQuery()
      .setContractId(vaultManagerId)
      .setGas(150000)
      .setFunction("getVaultAssets");

    const vaultsResult = await vaultsQuery.execute(client);
    const usdcAsset = vaultsResult.getAddress(0);
    const hbarAsset = vaultsResult.getAddress(1);

    console.log(`  Final Configuration:`);
    console.log(`    USDC Vault Asset: ${usdcAsset}`);
    console.log(`    HBAR Vault Asset: ${hbarAsset}`);

    const isUsdcZero =
      usdcAsset.toLowerCase().replace(/^0x/, "").replace(/^0+/, "") === "";
    const isHbarZero =
      hbarAsset.toLowerCase().replace(/^0x/, "").replace(/^0+/, "") === "";

    if (isUsdcZero || isHbarZero) {
      console.log(`\n  ❌ Configuration incomplete (zero addresses detected)`);
      return false;
    }

    console.log(`\n  ✅ Configuration verified successfully!`);
    return true;
  } catch (error: any) {
    console.log(`  ⚠️  Could not verify: ${error.message}`);
    return false;
  }
}

async function main() {
  try {
    await initialize();

    console.log(`\n  Using existing USDC Vault: ${USDC_VAULT_ADDRESS}`);

    // Deploy HBAR vault
    const hbarVault = await deployHBARVault();

    // Set both vaults in VaultManager
    await setVaultsInManager(USDC_VAULT_ADDRESS, hbarVault);

    // Verify
    const success = await verifyConfiguration();

    if (success) {
      console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
      console.log(`🎉 SUCCESS! Vaults configured in VaultManager!`);
      console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
      console.log(`  ✅ You can now run the deposit test!`);
      console.log(`     npx ts-node VaultTest-Final.ts\n`);
    }
  } catch (error: any) {
    console.error(`\n❌ Failed: ${error.message}`);
    process.exit(1);
  } finally {
    if (client) {
      client.close();
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
