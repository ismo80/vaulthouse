```markdown
# Orion Vaulthouse V1

A Clarity smart contract for Stacks that enables time-locked STX vaults with optional beneficiary claims and emergency withdrawal capabilities.

## Overview

Vaulthouse allows users to create secure, time-locked vaults for their STX tokens. Vault owners can:
- Deposit and withdraw STX after the lock period expires
- Designate optional beneficiaries who can claim funds after unlock
- Extend lock periods
- Perform emergency withdrawals before unlock (with a configurable fee)
- Close vaults when empty

Administrators can:
- Initialize the contract
- Pause/unpause vault operations
- Set emergency withdrawal fees (capped at 20%)

## Features

### Vault Management
- **Create Vault**: Initialize a new time-locked vault with custom memo
- **Deposit**: Add STX to an open vault
- **Extend Lock**: Increase the lock period (owner only)
- **Withdraw**: Claim funds after the lock period expires (owner only)
- **Close Vault**: Mark vault as closed when balance reaches zero (owner only)

### Beneficiary System
- **Set Beneficiary**: Designate an optional beneficiary (owner only)
- **Enable/Disable Claims**: Control whether beneficiary can claim funds (owner only)
- **Beneficiary Claim**: Beneficiary can withdraw funds after lock period if enabled

### Emergency Operations
- **Emergency Withdraw**: Owner can withdraw before lock period with a fee penalty
- **Fee System**: Configurable emergency fee (basis points, max 20%)

### Administrative Controls
- **Init Admin**: Set contract administrator
- **Pause/Unpause**: Halt all vault operations
- **Set Emergency Fee**: Configure withdrawal penalty (capped at 2000 bps = 20%)

## Data Structures

### Vault Map
Each vault stores:
```clarity
{
  owner: principal,                    ;; Vault owner
  beneficiary: (optional principal),   ;; Optional designated beneficiary
  beneficiary-enabled: bool,           ;; Whether beneficiary can claim
  lock-until: uint,                    ;; Block height until funds are locked
  created-at: uint,                    ;; Creation block height
  balance: uint,                       ;; Current STX balance
  status: uint,                        ;; STATUS-OPEN (0) or STATUS-CLOSED (1)
  memo: (string-ascii 64)             ;; Optional vault description
}
```

### State Variables
- `vault-nonce`: Counter for vault IDs
- `admin`: Optional principal with administrative privileges
- `paused`: Boolean to halt operations
- `emergency-fee-bps`: Emergency withdrawal fee in basis points

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 200 | ERR-NOT-AUTHORIZED | Caller is not authorized for this action |
| 201 | ERR-VAULT-NOT-FOUND | Vault ID does not exist |
| 202 | ERR-VAULT-NOT-OPEN | Vault is not in open status |
| 203 | ERR-INVALID-AMOUNT | Amount is zero or invalid |
| 204 | ERR-LOCK-NOT-REACHED | Lock period has not expired |
| 205 | ERR-INVALID-LOCK | Lock period is invalid |
| 206 | ERR-INSUFFICIENT-BAL | Vault has insufficient balance |
| 207 | ERR-BENEFICIARY-DISABLED | Beneficiary claims are disabled |
| 208 | ERR-PAUSED | Contract is paused |
| 209 | ERR-ADMIN-NOT-SET | Administrator not initialized |
| 210 | ERR-ADMIN-ALREADY-SET | Administrator already set |
| 211 | ERR-FEE-TOO-HIGH | Fee exceeds maximum (20%) |

## Usage Examples

### Create a Vault
```clarity
(contract-call? .vaulthouse create-vault 
  u100000  ;; lock-until (block height)
  "My Emergency Fund"  ;; memo
)
```

### Deposit STX
```clarity
(contract-call? .vaulthouse deposit 
  u0        ;; vault-id
  u1000000  ;; amount in microSTX
)
```

### Set Beneficiary
```clarity
(contract-call? .vaulthouse set-beneficiary 
  u0
  (some 'SP2EXAMPLE123...)  ;; beneficiary address
)
```

### Enable Beneficiary Claims
```clarity
(contract-call? .vaulthouse set-beneficiary-enabled 
  u0
  true
)
```

### Withdraw After Lock Expires
```clarity
(contract-call? .vaulthouse withdraw 
  u0        ;; vault-id
  u500000   ;; amount to withdraw
)
```

### Emergency Withdraw (with fee)
```clarity
(contract-call? .vaulthouse emergency-withdraw 
  u0        ;; vault-id
  u500000   ;; amount to withdraw
)
```

## Read-Only Functions

- `get-vault (vault-id)`: Retrieve vault details
- `get-next-vault-id`: Get the next available vault ID
- `get-admin`: Get current administrator
- `is-paused`: Check if contract is paused
- `get-contract-balance`: Get total STX held by contract
- `preview-emergency-fee (amount)`: Calculate emergency fee for an amount

## Security Considerations

1. **Access Control**: All vault operations require owner authorization
2. **Time Locks**: Enforced through burn block height validation
3. **Fee Caps**: Emergency fees capped at 20% to prevent excessive penalties
4. **Pause Mechanism**: Admin can pause operations in case of emergency
5. **Response Types**: All functions return proper Result types for error handling
6. **Treasury Model**: Emergency fees sent to admin address

## Admin Setup

1. **Initialize Admin** (any caller, first time only):
   ```clarity
   (contract-call? .vaulthouse init-admin)
   ```

2. **Configure Emergency Fee** (admin only):
   ```clarity
   (contract-call? .vaulthouse set-emergency-fee-bps u250)  ;; 2.5%
   ```

3. **Pause if Needed** (admin only):
   ```clarity
   (contract-call? .vaulthouse set-paused true)
   ```

## File Structure

```
vaulthouse/
├── contracts/
│   └── vaulthouse.clar    ;; Main contract
├── tests/
│   └── vaulthouse_test.ts ;; Unit tests
└── README.md              ;; This file
```

## Testing

Run tests using Clarity test framework:
```bash
clarinet test
```


Unlicensed - Open source
