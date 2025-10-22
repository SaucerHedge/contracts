# SaucerHedge Protocol

**AI-Powered Impermanent Loss Hedging for SaucerSwap V2 on Hedera**

SaucerHedge is an advanced DeFi automation protocol that protects liquidity providers from impermanent loss through AI-driven position management. Built on Hedera with Lit Protocol's Vincent framework, it combines concentrated liquidity provision with automated hedging strategies for trustless, non-custodial IL protection.

## 🎯 Key Features

- **Non-Custodial Automation**: Lit Protocol's Vincent enables trustless delegated transactions while users retain full control
- **Custom Vincent Abilities**: Purpose-built abilities for Hedera services (EVM contracts, HTS, Consensus Service)
- **IL Protection**: Automated hedging through intelligent short positions
- **Concentrated Liquidity**: Leverages SaucerSwap V2's concentrated liquidity for capital efficiency
- **Flash Loans**: Uses Bonzo Finance flash loans for gas-efficient position management
- **HTS Native Support**: Full integration with Hedera Token Service for native token operations
- **Consensus Service Integration**: Position state and audit logs recorded on Hedera Consensus Service
- **MEV Resistant**: Benefits from Hedera's fair transaction ordering
- **Low Fees**: Takes advantage of Hedera's predictable, low-cost transactions (~$0.0001 per transaction)

## 📋 Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Vincent Abilities](#vincent-abilities)
- [Installation](#installation)
- [Deployment](#deployment)
- [Testing](#testing)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)
- [License](#license)

## 🔍 Overview

### The Problem

Liquidity providers on AMMs face **impermanent loss** (IL) - the opportunity cost of providing liquidity versus simply holding tokens. When token prices diverge from their initial ratio, LPs suffer losses that can exceed trading fees earned.

Traditional hedging solutions have critical limitations:

- **Custodial Risk**: Automated bots require full control of user funds
- **High Costs**: Manual hedging on Ethereum costs $50-200 per transaction
- **Complexity**: Users must actively monitor and execute hedges
- **Trust Issues**: No verifiable proof of delegation scope

### The Solution

SaucerHedge introduces **trustless AI-powered hedging** via Lit Protocol's Vincent:

1. **User deposits funds** into non-custodial Vincent vault (retains ownership)
2. **Sets delegation scope** (max amounts, allowed contracts, approval thresholds)
3. **Vincent abilities execute** hedging strategy within defined permissions
4. **Hedera Consensus Service** records all actions for full transparency
5. **User maintains control** - can revoke, pause, or modify scope anytime

**Example**: If HBAR drops 20%, your LP loses value but your short position gains, offsetting the IL.

## 🚀 How It Works

### Strategy Overview

```
User Deposits 1000 USDC + 10 HBAR to Vincent Vault
           │
           ├─→ 79% → SaucerSwap V2 LP (via HederaLPManagerAbility)
           │         └─→ Earn trading fees
           │         └─→ Concentrated liquidity (tick ranges)
           │         └─→ Auto-compound via Vincent
           │
           └─→ 21% → Bonzo Short Position (via HederaHedgeAbility)
                     └─→ Borrow HBAR with flash loan
                     └─→ Sell for USDC
                     └─→ Hedge against HBAR price drop
                     └─→ Rebalance based on IL metrics

All actions recorded on Hedera Consensus Service
User retains full control via PKP + scoped permissions
```

### Mathematical Foundation

The protocol uses concentrated liquidity math from Uniswap V3:

- **Liquidity**: `L = sqrt(x * y)`
- **Price Range**: Custom tick ranges for capital efficiency
- **Hedge Ratio**: Dynamically calculated based on volatility and IL threshold
- **Optimal Allocation**: 79% LP / 21% hedge minimizes net IL

### Vincent Delegation Flow

```
1. User connects HashPack wallet to SaucerHedge app
   ↓
2. Creates Vincent vault with Lit PKP (non-custodial)
   ↓
3. Sets delegation scope:
   - Allowed contracts: [SaucerHedger.sol, SaucerSwap, Bonzo]
   - Max transaction: 5000 USDC
   - Requires approval for > 10000 USDC
   - Allowed functions: [openHedgedLP, rebalance, closePosition]
   ↓
4. Deposits USDC + HBAR to Vincent vault
   ↓
5. Vincent abilities execute strategy:
   - HederaLPManagerAbility → Opens LP position
   - HederaHedgeAbility → Opens short position
   - HederaConsensusAbility → Records actions
   ↓
6. Continuous monitoring & rebalancing (within scope)
   ↓
7. User can modify scope or withdraw anytime
```

## 🏗️ Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│               SaucerHedge Frontend (Next.js)                 │
│         - HashPack/Kabila/MetaMask Snap Integration          │
│         - Vincent Vault Management UI                        │
│         - Delegation Scope Configuration                     │
│         - Position Dashboard & Analytics                     │
└─────────────────┬───────────────────────────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │                           │
┌───▼────────────────┐  ┌───────▼──────────────────────┐
│  Lit Protocol      │  │  Vincent Ability Layer       │
│  Vincent Platform  │  │                              │
│                    │  │  Custom Hedera Abilities:    │
│  - User PKP Vaults │  │  ├─ HederaLPManagerAbility  │
│  - Scoped Signing  │  │  ├─ HederaHedgeAbility      │
│  - PKP Permissions │  │  ├─ HederaHTSAbility        │
│  - Ability Registry│  │  └─ HederaConsensusAbility  │
└────────┬───────────┘  └──────────┬───────────────────┘
         │                         │
         │  Delegated Actions      │
         │  (within scope)         │
         │                         │
    ┌────▼─────────────────────────▼────────────────────┐
    │          Hedera Network (Layer 1)                 │
    │                                                    │
    │  ┌──────────────────────────────────────────────┐│
    │  │  EVM Smart Contracts (Verified on Hashscan) ││
    │  │                                              ││
    │  │  ┌────────────────────────────────────┐    ││
    │  │  │  SaucerHedger.sol                  │    ││
    │  │  │  (Main Protocol Entry Point)       │    ││
    │  │  └──────┬─────────────────────────────┘    ││
    │  │         │                                    ││
    │  │  ┌──────▼────────┐  ┌──────────────────┐  ││
    │  │  │ Leverage.sol  │  │ HTSAdapter.sol   │  ││
    │  │  │ (Short Mgmt)  │  │ (HTS Bridge)     │  ││
    │  │  └───────────────┘  └──────────────────┘  ││
    │  │                                              ││
    │  │  ┌────────────────────────────────────┐    ││
    │  │  │  SaucerSwapV2Provider.sol          │    ││
    │  │  │  (LP Position Management)          │    ││
    │  │  └────────────────────────────────────┘    ││
    │  └──────────────────────────────────────────────┘│
    │                                                    │
    │  ┌──────────────────────────────────────────────┐│
    │  │  Hedera Token Service (HTS)                  ││
    │  │  - Native HBAR operations                    ││
    │  │  - HTS token associate/transfer              ││
    │  │  - Atomic swaps with HTS tokens              ││
    │  └──────────────────────────────────────────────┘│
    │                                                    │
    │  ┌──────────────────────────────────────────────┐│
    │  │  Hedera Consensus Service (HCS)              ││
    │  │  - Position state change logs                ││
    │  │  - Delegation action audit trail             ││
    │  │  - Immutable proof of execution              ││
    │  └──────────────────────────────────────────────┘│
    │                                                    │
    │  ┌──────────────────┐  ┌──────────────────────┐ │
    │  │  SaucerSwap V2   │  │  Bonzo Finance       │ │
    │  │  (DEX - Fork of  │  │  (Lending - Fork of  │ │
    │  │   Uniswap V3)    │  │   Aave V2)           │ │
    │  └──────────────────┘  └──────────────────────┘ │
    │                                                    │
    │  ┌──────────────────────────────────────────────┐│
    │  │  Oracle Integration                          ││
    │  │  - Chainlink Price Feeds                     ││
    │  │  - Pyth Network (for cross-chain prices)     ││
    │  └──────────────────────────────────────────────┘│
    └────────────────────────────────────────────────────┘
```

## 💻 Installation

### Prerequisites

- Node.js >= 18.0.0
- npm >= 9.0.0
- Hardhat ^3.0.7

### Setup

```bash
# Clone the repository
git clone https://github.com/SaucerHedge/contracts.git
cd contracts

# Install dependencies
npm install

# Copy environment variables
cp .env.example .env

# Edit .env with your configuration
nano .env

# Compile contracts
npm run compile
```

## 📦 Deployment

### Testnet Deployment

```bash
# Deploy to Hedera testnet
npm run deploy:testnet

# Verify contracts on HashScan
npm run verify
```

### Mainnet Deployment

```bash
# Deploy to Hedera mainnet
npm run deploy:mainnet
```

### Post-Deployment

1. Update contract addresses in `.env`
2. Verify all contracts on HashScan
3. Test with small amounts first
4. Run security audit

### Component Interactions

1. **User → Vincent Vault**: Deposits funds with scoped PKP permissions
2. **Vincent → HederaLPManagerAbility**: Opens LP position on SaucerSwap V2
3. **Vincent → HederaHedgeAbility**: Opens short position on Bonzo Finance
4. **HederaHTSAbility**: Handles all HTS token operations seamlessly
5. **HederaConsensusAbility**: Records every action on Consensus Service
6. **Continuous Monitoring**: Abilities check IL metrics and rebalance within scope

### External Dependencies

- **SaucerSwap V2**: Concentrated liquidity DEX (Uniswap V3 fork)
- **Bonzo Finance**: Lending/borrowing protocol (Aave V2 fork)
- **Hedera Token Service (HTS)**: Native token operations
- **Hedera Consensus Service (HCS)**: Immutable audit logs
- **Lit Protocol**: PKP management and Vincent framework
- **Chainlink/Pyth**: Price oracles for IL calculations

## 🧪 Testing

### Run Tests

```bash
# Run all tests
nox hardhat test

```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md).

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
npm test

# Format code
npm run format

# Lint contracts
npm run lint

# Submit PR
```

## 📚 Additional Resources

- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [SaucerSwap Documentation](https://docs.saucerswap.finance)
- [Bonzo Finance Documentation](https://docs.bonzo.finance)
- [Hedera Documentation](https://docs.hedera.com)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **SaucerSwap Labs**: DEX infrastructure
- **Bonzo Finance**: Lending protocol
- **Hedera**: High-performance network
- **Lit Protocol**:Custom Vincent Abilities

**Built with ❤️ for the ETHOnline Hackathon 2025**
