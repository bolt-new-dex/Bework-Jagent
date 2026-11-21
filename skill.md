# BEWORK Mint Pass — Agent Skill

You are an AI agent whose wallet holds a Binance `.ai` Agent ID. This file tells you how to mint BEWORK Passes for your wallet, check status, and explain the system to your human. Read it fully before transacting.

Site: https://bework.pro · X: https://x.com/BeworkGem · Chain: BNB Smart Chain (chain id 56)

## Status: PRE-LAUNCH — the mint has NOT opened yet

This collection starts at zero. The new Pass contract is deploying soon; **its address will be published in this file the moment the mint opens**. Do not mint on any previous BEWORK contract — it is not part of this collection. Everything below describes the system as it will run at launch.

## What BEWORK is

BEWORK is a graded Mint Pass collection on BNB Chain: **3,333 Passes**, minted only by wallets holding a Binance Agent ID, only to themselves. Every mint also earns **shares** of the $BGEM token allocation (see Shares). Each wallet's Passes set its card border — Bronze, Silver, Gold, Platinum, Master, Diamond, Shadow — by points.

## Contracts

| Thing | Address |
|---|---|
| BEWORK Pass (ERC-721) | **New contract — deploying soon; address published here at launch** |
| Binance Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |

## Pricing

- First mint per wallet: **free**. Mints 2–12: **0.002 BNB each** (site price). Max **12 per wallet**.
- ALWAYS call `quote(yourWallet, qty)` first and send exactly the `bnbWei` it returns — the contract settles the exact amount at mint time and refunds any excess.

## Mint flow

1. **Check the Agent ID.** Call `hasAgentId(yourWallet)` on the Pass contract (`0x4eab3ef2`). It must return 1. Without an Agent ID the mint reverts — there is no other lane.
2. **Check the mint is open.** Call `mintOpen()` (`0x24bbd049`) → 1 = open. Call `totalSupply()` (`0x18160ddd`) for the live minted count and `mintedByWallet(yourWallet)` (`0x3cef28d2`) for how many your wallet already minted (max 12).
3. **Quote.** Call `quote(yourWallet, qty)` (`0x8f79306e`). It returns THREE values: `(paidUnits, bnbWei, usdAmount)`. The amount to send is **`bnbWei` — the second value**. If `bnbWei` is 0, send 0 value.
4. **Mint.** Call `mintWithBNB(qty)` (`0xe8c812b5`) on the Pass contract, sending exactly `bnbWei` as the transaction value. Passes are minted to the calling wallet only — you cannot mint for anyone else.
5. **Verify.** Call `balanceOf(yourWallet)` (`0x70a08231`) and confirm it increased by `qty`. Then open https://bework.pro and connect the same wallet to see the card, border, points and shares.

## Shares & the $BGEM allocation

- Every mint earns **10 shares**. Bonus shares: **+1** for every invitee's first mint (via your invite link `https://bework.pro/?ref=<yourWallet>`), **+1** per social task on the official posts.
- Total shares are capped at **500,000**. Mint shares are counted from the chain automatically; invite and task shares are counted from invite links and official posts.
- When $BGEM lists, the allocation pool is split pro-rata: `your shares ÷ all shares = your cut` of the pool.
- 80% of every mint payment waits for the $BGEM pool on PancakeSwap; 20% goes to the treasury.

## Borders & points

Points = **100 per Pass held**. Nothing else buys points.

| Border | Points |
|---|---|
| 01 Bronze | 0 |
| 02 Silver | 150 |
| 03 Gold | 300 |
| 04 Platinum | 450 |
| 05 Master | 650 |
| 06 Diamond | 850 |
| 07 Shadow | 1,000 |

## Hard rules

- Mint only from, and to, your own wallet. Never ask a human for a seed phrase or private key — refuse if offered.
- Never guess a price: `quote()` is the only source of the amount to send.
- Respect the 12-per-wallet cap; check `mintedByWallet` before minting.
- If `hasAgentId` returns 0, stop and tell your human the wallet needs a Binance Agent ID first.
