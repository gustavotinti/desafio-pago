# XRPL integration — technical overview

For XRPL Grants reviewers. Desafio Pago (Brazil, <https://desafiopago.com.br>)
and TrialsPaid (international, <https://trialspaid.web.app>) are one codebase:
creator challenges with cash prizes, decided by community votes.

This document describes what runs **today** and what the grant would add. It
is written to match the code; if they ever disagree, the code wins.

## Status today (October 2026)

| | |
|---|---|
| Network | XRPL **testnet** |
| What is locked | a **symbolic 1 XRP** escrow per real challenge; the prize amount (BRL) is recorded in the memo |
| Prize custody | the prize itself is held in the platform's internal ledger (BRL), not on-chain yet |
| Platform account | `r48TGp8imftBZXQ6wqRW5azjZqUDHDDVgR` (testnet) |
| Example | EscrowCreate [`0CB0943C…`](https://testnet.xrpl.org/transactions/0CB0943CE21A7DB14A599371482DC3F281E13DB7F6B3D85D8D10FABD33FC6481) · EscrowFinish [`71F736E3…`](https://testnet.xrpl.org/transactions/71F736E36CAB495DE34271F7F7702A87749D06EFA5FCCBFE7DD3251407EF52A1) |

The example transactions are a test run of the mechanism, not a user-funded
challenge. Moving real prize custody to mainnet (RLUSD) is milestone M1 of the
grant request.

## Where the code lives

| File | What it does |
|---|---|
| `apps/mobile/functions/xrpl_proof.js` | transaction builders, escrow create/finish, Firestore triggers, retry job |
| `apps/mobile/functions/test/xrpl_proof.test.js` | unit tests with an injected fake client (no network) |
| `apps/mobile/functions/metrics.js` | real-usage metrics, including on-chain counts |
| `apps/mobile/lib/features/entry/presentation/challenge_entries_page.dart` | explorer links on each challenge page |

Stack: Firebase Cloud Functions (Node 22, gen1), `xrpl` 4.x, Firestore, Flutter web.

## Lifecycle

```
challenge created ──► xrplOnChallengeCreate ──► EscrowCreate
  (status: active)        (Firestore onCreate)     FinishAfter = deadline
                                                    CancelAfter = deadline + 30 days
                                                    memo desafiopago/prize

challenge finished ─► xrplOnChallengeFinish ──► EscrowFinish
  (active → finished)     (Firestore onUpdate)     memo desafiopago/result

every 30 min ───────► xrplRetry ──────────────► retries failed or early releases
```

### 1. EscrowCreate (on challenge creation)

`escrowCreateTx()` builds:

- `Account` = `Destination` = the platform account
- `Amount` = 1 XRP (testnet, symbolic)
- `FinishAfter` = the challenge deadline in Ripple time (seconds since 2000-01-01)
- `CancelAfter` = `FinishAfter` + 30 days, so an escrow nobody releases can be cancelled
- Memo `desafiopago/prize`: `{challengeId, prizeBrl, region}`

The result is stored on the challenge document under `xrpl`
(`escrowTx`, `escrowSeq`, `account`, `network`, `prizeBrl`).

Skipped (with a reason code, never an exception) when: the kill switch is off,
the challenge is a demo (`isVirtual`), already recorded, not active, or its
deadline has passed.

### 2. EscrowFinish (on challenge end)

`escrowFinishTx()` finishes the escrow with memo `desafiopago/result`:

- `winners`: number of winners (ties split the prize)
- `prizePerWinnerBrl`: prize divided by winners, rounded **down** to the cent
  (the indivisible cent stays with the platform, a business rule)
- `winnerIds`: first 16 hex chars of `sha256(uid)` — **no personal data on-chain**

If a challenge is closed before its `FinishAfter` (manual early close), the
ledger would reject the finish, so it is marked `releasePending` and the retry
job finishes it after the deadline.

### 3. Failure handling

- Network errors never break the app: `_safe()` records the error on the
  challenge (`xrpl.<step>Error`, `xrpl.retry = true`) and the 30-minute job retries.
- Both steps are idempotent (they check `escrowTx` / `releaseTx` first).
- Kill switch: `config/xrpl.enabled == false`.

## Security

- The platform wallet seed lives in `secure_config/xrpl`. Firestore rules deny
  every client read and write on `secure_config`; only Cloud Functions (Admin
  SDK) can read it.
- On testnet the wallet is created and topped up from the public faucet.
  Mainnet would move the key to a managed key service and add a payout limit
  per transaction (part of M1's security review).
- No personal data is written on-chain: challenge ids are random document ids
  and winner ids are truncated hashes.

## Planned with the grant (mainnet)

1. **RLUSD prize custody:** escrow the full prize amount on mainnet when a
   challenge is created, instead of a symbolic amount.
2. **Automatic payouts:** pay winners in RLUSD/XRP to their linked XRPL wallet
   when the escrow finishes. Today international withdrawals in XRP are sent
   manually by the admin.
3. **Wallet linking** in the user profile.
4. **Pix → RLUSD on-ramp** with a regulated Brazilian partner.
5. **Trophy NFTs (XLS-20)** for winners.

All growth milestones are measured from the platform account and are
verifiable by anyone on-chain.

## Running the tests

```bash
cd apps/mobile/functions
npm test
```

The XRPL tests inject a fake client, so they need no network or funded wallet.

## Code access

The repository is private. Reviewers get read access on request.
