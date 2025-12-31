# FLEC Smart Contracts

Programmable Work Agreements on Lisk blockchain.

---

## 🛠️ Tooling

This repository uses **Foundry** for smart contract development.

Foundry includes:
- **Forge** – build & testing framework
- **Cast** – interact with EVM contracts
- **Anvil** – local dev node

Docs: https://book.getfoundry.sh/

---

## 📦 Build & Test (Local)

```bash
forge build
forge test
forge fmt
```

---

## 🔐 Environment Variables

Create `.env` (do not commit):

```env
PRIVATE_KEY=<deployer_wallet_private_key>
RPC_URL=https://rpc.sepolia-api.lisk.com
ETHERSCAN_API_KEY=any_string

# set after MockUSDC deployment
USDC_ADDRESS=<mock_usdc_address>
```

Notes:
- `PRIVATE_KEY` is used **only for deployment & initial configuration**
- Use a **dedicated deployer/testnet wallet**
- `ETHERSCAN_API_KEY` is optional (verification only)

---

## 🚀 Deployment Order (Required)

### 1️⃣ Deploy MockUSDC + Faucet

This script:
- Deploys `MockUSDC`
- Deploys `MockUSDCFaucet`
- Grants `MINTER_ROLE` to Faucet automatically

```bash
forge script script/DeployMockUSDC.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Save deployed addresses:
- `MockUSDC` → update `USDC_ADDRESS`
- `MockUSDCFaucet`

---

### 2️⃣ Mint MockUSDC (Judges / Testers)

Judges **do not need minter role**.

Via block explorer:
1. Open `MockUSDCFaucet`
2. Go to **Write Contract**
3. Call:
   ```
   drip()
   ```
4. Confirm transaction (ETH required)

Wallet receives **mUSDC (rate-limited)**.

---

### 3️⃣ Deploy FLECHub

Ensure `USDC_ADDRESS` is set correctly.

```bash
forge script script/DeployFLECHub.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

`FLECHub` handles:
- Onchain work agreements
- Escrow & execution fee (upfront)
- Milestone & monthly payroll
- Timeout auto-release
- Dispute lock

---

## 🔄 Minimal Testnet Flow (Sanity Check)

1. Mint mUSDC via Faucet
2. Approve mUSDC to `FLECHub`
   - allowance = `totalBudget + executionFee`
3. Company creates agreement
4. Company deposits escrow
5. Freelancer submits work / waits payroll
6. Company approves **or** auto-release via timeout

---

## ⛽ Gas Requirement

- All transactions require **ETH on Lisk Sepolia**
- Includes faucet, approve, deposit, submit, approve, and cancel

---

## ℹ️ Notes

- Execution fee is **paid once upfront** and **non-refundable**
- Fee does **not** reduce freelancer payment
- When status is `Disputed`, no unilateral execution is allowed
- `MockUSDC (mUSDC)` is **testnet-only**

---

## ⚠️ Common Pitfalls

- Forgetting to update `USDC_ADDRESS`
- Wallet has no ETH → transaction fails
- Insufficient allowance (must include execution fee)

---

## 📄 License

MIT