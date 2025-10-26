import {
  Client,
  AccountId,
  PrivateKey,
  ContractCallQuery,
  ContractExecuteTransaction,
  ContractFunctionParameters,
  Hbar,
  HbarUnit,
  Long,
} from "@hashgraph/sdk";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * VaultManager Complete Test - UPDATED WITH YOUR DEPLOYED ADDRESSES
 */

// YOUR ACTUAL DEPLOYED TOKEN ADDRESSES (from factory deployment)
const USDC_CONTRACT_ID = "0.0.7132258";
const HBAR_CONTRACT_ID = "0.0.7132254";
const USDC_EVM_ADDRESS = "0x068e1563c08173eDCDC4A94969Eee2d29605C50E";
const HBAR_EVM_ADDRESS = "0x546268afB164e72C7e0bf6262b0A406860d93F47";

// Test amounts - adjust based on your balance
const USDC_AMOUNT = 10; // Start with 10 USDC
const HBAR_AMOUNT = 10; // Start with 10 HBAR
const TICK_LOWER = -887220;
const TICK_UPPER = 887220;

let client: Client;
let operatorAccountId: AccountId;
let operatorPrivateKey: PrivateKey;
let vaultManagerId: string;
let vaultManagerEvmAddress: string;

function hederaIdToEvmAddress(hederaId: string): string {
  const parts = hederaId.split(".");
  const num = parseInt(parts[2]);
  return "0x" + num.toString(16).padStart(40, "0");
}

async function initialize() {
  console.log(`\n🚀 VaultManager Complete Test`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);

  client = Client.forTestnet();

  if (!process.env.HEDERA_ACCOUNT_ID || !process.env.PRIVATE_KEY) {
    throw new Error("HEDERA_ACCOUNT_ID and PRIVATE_KEY required");
  }

  operatorAccountId = AccountId.fromString(process.env.HEDERA_ACCOUNT_ID);
  operatorPrivateKey = PrivateKey.fromStringECDSA(process.env.PRIVATE_KEY);
  client.setOperator(operatorAccountId, operatorPrivateKey);

  vaultManagerId = process.env.VAULT_MANAGER_ID || "";

  if (!vaultManagerId) {
    throw new Error("VAULT_MANAGER_ID required");
  }

  vaultManagerEvmAddress = hederaIdToEvmAddress(vaultManagerId);

  console.log(`✅ Initialized`);
  console.log(`  Account: ${operatorAccountId.toString()}`);
  console.log(`  VaultManager: ${vaultManagerId}`);
  console.log(`\n  Test Amounts:`);
  console.log(`  USDC: ${USDC_AMOUNT}`);
  console.log(`  HBAR: ${HBAR_AMOUNT}`);
}

async function checkVaultConfiguration() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`🔍 Verifying Vault Configuration\n`);

  try {
    const vaultsQuery = new ContractCallQuery()
      .setContractId(vaultManagerId)
      .setGas(150000)
      .setFunction("getVaultAssets");

    const vaultsResult = await vaultsQuery.execute(client);
    const usdcAsset = vaultsResult.getAddress(0);
    const hbarAsset = vaultsResult.getAddress(1);

    console.log(`  USDC Vault Asset: ${usdcAsset}`);
    console.log(`  HBAR Vault Asset: ${hbarAsset}`);

    // Verify they match our expected addresses
    if (
      usdcAsset.toLowerCase() !==
      USDC_EVM_ADDRESS.toLowerCase().replace("0x", "")
    ) {
      console.log(`  ⚠️  WARNING: USDC asset mismatch!`);
      console.log(`     Expected: ${USDC_EVM_ADDRESS}`);
    }

    if (
      hbarAsset.toLowerCase() !==
      HBAR_EVM_ADDRESS.toLowerCase().replace("0x", "")
    ) {
      console.log(`  ⚠️  WARNING: HBAR asset mismatch!`);
      console.log(`     Expected: ${HBAR_EVM_ADDRESS}`);
    }

    console.log(`  ✅ Vaults configured correctly!`);
  } catch (error: any) {
    console.log(`  ❌ Could not verify vaults: ${error.message}`);
    throw error;
  }
}

async function checkBalances() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`📊 Checking Token Balances\n`);

  const userEvmAddress = `0x${operatorAccountId.toSolidityAddress()}`;

  // Check USDC balance
  try {
    const usdcBalanceQuery = new ContractCallQuery()
      .setContractId(USDC_CONTRACT_ID)
      .setGas(100000)
      .setFunction(
        "balanceOf",
        new ContractFunctionParameters().addAddress(userEvmAddress)
      );

    const usdcBalance = await usdcBalanceQuery.execute(client);
    const usdcAmount = usdcBalance.getUint256(0).toNumber() / 1e6;
    console.log(`  USDC Balance: ${usdcAmount} USDC`);

    if (usdcAmount < USDC_AMOUNT) {
      console.log(
        `  ❌ Insufficient USDC! Need: ${USDC_AMOUNT}, Have: ${usdcAmount}`
      );
      throw new Error(`Insufficient USDC balance`);
    }
    console.log(`  ✅ Sufficient USDC`);
  } catch (error: any) {
    console.log(`  ❌ USDC check failed: ${error.message}`);
    throw error;
  }

  // Check HBAR token balance
  try {
    const hbarBalanceQuery = new ContractCallQuery()
      .setContractId(HBAR_CONTRACT_ID)
      .setGas(100000)
      .setFunction(
        "balanceOf",
        new ContractFunctionParameters().addAddress(userEvmAddress)
      );

    const hbarBalance = await hbarBalanceQuery.execute(client);
    const hbarAmount = hbarBalance.getUint256(0).toNumber() / 1e8;
    console.log(`  HBAR Token Balance: ${hbarAmount} HBAR`);

    if (hbarAmount < HBAR_AMOUNT) {
      console.log(`  ⚠️  Insufficient HBAR tokens!`);
      console.log(`  Need: ${HBAR_AMOUNT}, Have: ${hbarAmount}`);
      return { needsMore: true, hbar: hbarAmount };
    }

    console.log(`  ✅ Sufficient HBAR tokens`);
    return { needsMore: false, hbar: hbarAmount };
  } catch (error: any) {
    console.log(`  ⚠️  HBAR check failed: ${error.message}`);
    console.log(
      `  You may need to mint/acquire HBAR tokens at ${HBAR_CONTRACT_ID}`
    );
    throw error;
  }
}

async function approveTokens() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`✅ Approving Tokens\n`);

  // Approve USDC
  try {
    console.log(`  Approving ${USDC_AMOUNT} USDC...`);
    const usdcApproveTx = new ContractExecuteTransaction()
      .setContractId(USDC_CONTRACT_ID)
      .setGas(300000)
      .setFunction(
        "approve",
        new ContractFunctionParameters()
          .addAddress(vaultManagerEvmAddress)
          .addUint256(Long.fromNumber(USDC_AMOUNT * 1e6))
      );

    const usdcApproveSubmit = await usdcApproveTx.execute(client);
    const usdcApproveReceipt = await usdcApproveSubmit.getReceipt(client);

    console.log(`  ✅ USDC Approved: ${usdcApproveReceipt.status}`);
    console.log(`  📄 TX: ${usdcApproveSubmit.transactionId}`);
  } catch (error: any) {
    console.error(`  ❌ USDC approval failed: ${error.message}`);
    throw error;
  }

  // Approve HBAR tokens
  try {
    console.log(`\n  Approving ${HBAR_AMOUNT} HBAR tokens...`);
    const hbarApproveTx = new ContractExecuteTransaction()
      .setContractId(HBAR_CONTRACT_ID)
      .setGas(300000)
      .setFunction(
        "approve",
        new ContractFunctionParameters()
          .addAddress(vaultManagerEvmAddress)
          .addUint256(Long.fromNumber(HBAR_AMOUNT * 1e8))
      );

    const hbarApproveSubmit = await hbarApproveTx.execute(client);
    const hbarApproveReceipt = await hbarApproveSubmit.getReceipt(client);

    console.log(`  ✅ HBAR Approved: ${hbarApproveReceipt.status}`);
    console.log(`  📄 TX: ${hbarApproveSubmit.transactionId}`);
  } catch (error: any) {
    console.error(`  ❌ HBAR approval failed: ${error.message}`);
    throw error;
  }
}

async function depositToVaults() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`💰 Depositing to Vaults\n`);

  console.log(`  Depositing ${USDC_AMOUNT} USDC and ${HBAR_AMOUNT} HBAR...`);

  try {
    const depositTx = new ContractExecuteTransaction()
      .setContractId(vaultManagerId)
      .setGas(3000000)
      .setFunction(
        "depositForLP",
        new ContractFunctionParameters()
          .addUint256(Long.fromNumber(USDC_AMOUNT * 1e6))
          .addUint256(Long.fromNumber(HBAR_AMOUNT * 1e8))
      );

    const depositSubmit = await depositTx.execute(client);
    const depositReceipt = await depositSubmit.getReceipt(client);

    console.log(`  ✅ Status: ${depositReceipt.status}`);
    console.log(`  📄 TX: ${depositSubmit.transactionId}`);
    console.log(
      `  🔗 HashScan: https://hashscan.io/testnet/transaction/${depositSubmit.transactionId}`
    );

    // Query deposit details
    const userEvmAddress = `0x${operatorAccountId.toSolidityAddress()}`;

    try {
      const depositQuery = new ContractCallQuery()
        .setContractId(vaultManagerId)
        .setGas(200000)
        .setFunction(
          "getUserLPDeposit",
          new ContractFunctionParameters().addAddress(userEvmAddress)
        );

      const depositResult = await depositQuery.execute(client);

      console.log(`\n  📊 Deposit Details:`);
      console.log(
        `    USDC Amount: ${depositResult.getUint256(0).toNumber() / 1e6} USDC`
      );
      console.log(
        `    HBAR Amount: ${depositResult.getUint256(1).toNumber() / 1e8} HBAR`
      );
      console.log(`    USDC Shares: ${depositResult.getUint256(2).toString()}`);
      console.log(`    HBAR Shares: ${depositResult.getUint256(3).toString()}`);
      console.log(`    Has Active Position: ${depositResult.getBool(6)}`);
    } catch (error: any) {
      console.log(`  ⚠️  Could not query details: ${error.message}`);
    }
  } catch (error: any) {
    console.error(`  ❌ Deposit failed: ${error.message}`);
    console.log(
      `\n  🔗 Check: https://hashscan.io/testnet/transaction/${error.transactionId}`
    );
    throw error;
  }
}

async function openHedgedPosition() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`🔐 Opening Hedged Position (Vincent PKP)\n`);

  const vincentPrivateKey = process.env.VINCENT_PKP_PRIVATE_KEY;

  if (!vincentPrivateKey) {
    console.log(`  ⚠️  VINCENT_PKP_PRIVATE_KEY not found`);
    console.log(`  Skipping position opening`);
    return;
  }

  const VINCENT_PKP = "0xdd8eE640f02789910B364C1233f3A744AaCf1d82";

  try {
    const vincentClient = Client.forTestnet();
    const vincentAccountId = AccountId.fromEvmAddress(0, 0, VINCENT_PKP);
    const vincentKey = PrivateKey.fromStringECDSA(vincentPrivateKey);
    vincentClient.setOperator(vincentAccountId, vincentKey);

    const userEvmAddress = `0x${operatorAccountId.toSolidityAddress()}`;

    const openPositionTx = new ContractExecuteTransaction()
      .setContractId(vaultManagerId)
      .setGas(5000000)
      .setFunction(
        "openHedgedLPForUser",
        new ContractFunctionParameters()
          .addAddress(userEvmAddress)
          .addInt24(TICK_LOWER)
          .addInt24(TICK_UPPER)
      );

    console.log(`  Opening position...`);
    const openPositionSubmit = await openPositionTx.execute(vincentClient);
    const openPositionReceipt = await openPositionSubmit.getReceipt(
      vincentClient
    );

    console.log(`  ✅ Status: ${openPositionReceipt.status}`);
    console.log(`  📄 TX: ${openPositionSubmit.transactionId}`);
    console.log(
      `  🔗 HashScan: https://hashscan.io/testnet/transaction/${openPositionSubmit.transactionId}`
    );

    vincentClient.close();
  } catch (error: any) {
    console.error(`  ❌ Failed: ${error.message}`);
    throw error;
  }
}

async function showSummary() {
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`📋 Summary\n`);

  const userEvmAddress = `0x${operatorAccountId.toSolidityAddress()}`;

  try {
    const finalQuery = new ContractCallQuery()
      .setContractId(vaultManagerId)
      .setGas(200000)
      .setFunction(
        "getUserLPDeposit",
        new ContractFunctionParameters().addAddress(userEvmAddress)
      );

    const finalResult = await finalQuery.execute(client);

    console.log(`  ✅ Test Completed!`);
    console.log(`\n  Final Position:`);
    console.log(`    USDC: ${finalResult.getUint256(0).toNumber() / 1e6} USDC`);
    console.log(`    HBAR: ${finalResult.getUint256(1).toNumber() / 1e8} HBAR`);
    console.log(`    Position ID: ${finalResult.getUint256(4).toString()}`);
    console.log(`    Active: ${finalResult.getBool(6)}`);
  } catch (error: any) {
    console.log(`  ⚠️  Could not query: ${error.message}`);
  }

  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
}

async function main() {
  try {
    await initialize();
    await checkVaultConfiguration();
    await checkBalances();
    await approveTokens();
    await depositToVaults();
    await openHedgedPosition();
    await showSummary();

    console.log(`✨ All operations completed!\n`);
  } catch (error: any) {
    console.error(`\n❌ Test failed: ${error.message}`);
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
