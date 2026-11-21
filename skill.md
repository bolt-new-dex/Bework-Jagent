# BEWORK Mint Pass — Agent Skill

You are an AI agent whose wallet holds a Binance `.ai` Agent ID. This file tells you how to mint BEWORK Passes for your wallet, check status, and explain the system to your human. Read it fully before transacting.

Site: https://bework.pro · X: https://x.com/BeworkGem · Chain: BNB Smart Chain (chain id 56)

## Status: CONTRACTS DEPLOYED — the mint opens at launch

The Pass and $BGEM contracts are deployed (addresses below) and the claim pool is funded. The owner opens the mint with one final transaction — until `mintOpen()` returns 1, do not send mint transactions, they will revert. Everything below describes the system as it runs.

## What BEWORK is

BEWORK is a graded Mint Pass collection on BNB Chain: **3,333 Passes**, minted only by wallets holding a Binance Agent ID, only to themselves. Every Pass also joins the **Field** that is open when it mints and claims **$BGEM** when that Field seals (see Fields & the $BGEM claim). Each wallet's Passes set its card border — Bronze, Silver, Gold, Platinum, Master, Diamond, Shadow — by points.

## Contracts

| Thing | Address |
|---|---|
| BEWORK Pass (ERC-721, mint + claims) | `0xafbdd45e7a6719775a7909ba15eddf0f68f7df70` |
| $BGEM token (ERC-20) | `0x981d87d0251dddaadf6b1420f0de3095364979e9` |
| Binance Agent ID registry | `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` |

Do not mint on any previous BEWORK contract — it is not part of this collection.

## Pricing

- Free mints drop in **rounds**: **333 free every 3 hours**, **one free per wallet per round** while slots last. Every other mint: **0.002 BNB each**. Max **12 per wallet**. `quote()` already accounts for a free slot — if the mint is free in the current round, `bnbWei` returns 0.
- ALWAYS call `quote(yourWallet, qty)` first and send exactly the `bnbWei` it returns — the contract settles the exact amount at mint time and refunds any excess.

## Mint flow

1. **Check the Agent ID.** Call `hasAgentId(yourWallet)` on the Pass contract (`0x4eab3ef2`). It must return 1. Without an Agent ID the mint reverts — there is no other lane.
2. **Check the mint is open.** Call `mintOpen()` (`0x24bbd049`) → 1 = open. Call `totalSupply()` (`0x18160ddd`) for the live minted count and `mintedByWallet(yourWallet)` (`0x3cef28d2`) for how many your wallet already minted (max 12).
3. **Quote.** Call `quote(yourWallet, qty)` (`0x8f79306e`). It returns THREE values: `(paidUnits, bnbWei, usdAmount)`. The amount to send is **`bnbWei` — the second value**. If `bnbWei` is 0, send 0 value.
4. **Mint.** Call `mintWithBNB(qty)` (`0xe8c812b5`) on the Pass contract, sending exactly `bnbWei` as the transaction value. Passes are minted to the calling wallet only — you cannot mint for anyone else.
5. **Verify.** Call `balanceOf(yourWallet)` (`0x70a08231`) and confirm it increased by `qty`. Then open https://bework.pro and connect the same wallet to see the card, border, points and the current Field.

## Fields & the $BGEM claim

- Time runs in **Fields**: one Field every **5 hours**. Every Pass minted while a Field is open belongs to that Field.
- When a Field **seals**, its tier locks by how many Passes were minted inside it, and every Pass in the Field claims the same amount:

| Tier | Passes in the Field | $BGEM per Pass |
|---|---|---|
| SPARK | 1–24 | 2,500 |
| CHARGED | 25–74 | 12,500 |
| OVERDRIVE | 75–149 | 60,000 |
| SURGE | 150+ | 150,000 |

- **Claims open 1 hour after the seal**, cost **0.0002 BNB per Pass**, and **never expire**. A Pass claims once, for the Field it was minted in. The claim pool holds **500,000,000 $BGEM**, funded inside the Pass contract.
- Claims run **inside the Pass contract itself**: call `claim(tokenIds)` (`0x6ba4c138`, one argument — an array of your token ids) sending `0.0002 BNB × ids` as value. Helpers: `fieldOf(tokenId)` (`0x2191d452`), `claimed(tokenId)` (`0xdbe7e3bd`), `claimOpensAt(field)` (`0xd0eec3d0`), `fieldReward(field)` (`0x795d9e74`), `currentField()` (`0x601e9e2e`). Or claim from https://bework.pro.

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
