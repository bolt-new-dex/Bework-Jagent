# BEWORK Mint Pass — Agent Skill

You are an AI agent whose wallet holds a Binance `.ai` Agent ID. This file tells you how to mint BEWORK Passes for your wallet, check status, and explain the system to your human. Read it fully before transacting.

Site: https://bework.pro · X: https://x.com/BeworkGem · Chain: BNB Smart Chain (chain id 56)

## Status: MINT OPEN — LIVE

The mint is **open**. Field Nº 1 and the first free round started at the epoch (check `epoch()` / `currentField()` on the Pass contract for the live clock). The claim pool (500,000,000 $BGEM) is funded inside the Pass contract. Everything below describes the system as it runs.

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

## Mint flow — 3 calls, execute directly

1. **Quote.** `quote(yourWallet, qty)` (`0x8f79306e`) → returns `(paidUnits, bnbWei, usdAmount)`. The BNB to send is **`bnbWei`, the second value** (0 = this mint is free).
2. **Mint.** `mintWithBNB(qty)` (`0xe8c812b5`) with value = exactly `bnbWei`. Passes mint to the calling wallet only.
3. **Report** the new token ids.

Your wallet must hold a Binance Agent ID or the mint reverts — there is no other lane. The first mint in each 3-hour round is free while the round's 333 slots last; quote already includes it. Max 12 per wallet.

**Paid mints (free used up):** the same 3 calls — quote simply returns the full price (qty × 0.002 BNB) once the round's free slot is gone or used.

Checks if needed: `mintOpen()` `0x24bbd049` · `hasAgentId(wallet)` `0x4eab3ef2` · `mintedByWallet(wallet)` `0x3cef28d2` · `totalSupply()` `0x18160ddd`.

## Upgrades — the Forge

Every Pass starts at **Bronze (level 0)**. Its owner can pay BNB to raise it, and **instantly receives $BGEM for every level gained**:

| Step | Cost | Instant $BGEM |
|---|---|---|
| Bronze → Silver | 0.001 BNB | 10,000 |
| Silver → Gold | 0.002 BNB | 25,000 |
| Gold → Platinum | 0.003 BNB | 50,000 |
| Platinum → Master | 0.005 BNB | 100,000 |
| Master → Diamond | 0.008 BNB | 200,000 |
| Diamond → Shadow | 0.012 BNB | 400,000 |

Full run Bronze → Shadow: **0.031 BNB, 785,000 $BGEM**. Levels are recorded in the **Forge contract** — its address will be published in the Contracts table when it launches — not in the Pass contract; the BEWORK site reads them to dress the card. Flow: `levelOf(tokenId)` (`0x6d5e3032`) → `priceTo(tokenId, target)` (`0x009ae548`, returns `(bnbWei, bgemReward)`) → `upgradeTo(tokenId, target)` (`0x60836166`) sending exactly `bnbWei` — or `upgrade(tokenId)` (`0x45977d03`) for a single step. Only the Pass's owner can upgrade it; overpayment is refunded in the same transaction.

## Claim flow — execute directly

1. **Note the wallet's $BGEM balance** — `balanceOf(wallet)` (`0x70a08231`) on the $BGEM token contract (see Contracts above).
2. **Find the wallet's token ids** — scan `ownerOf(id)` (`0x6352211e`) for id 1..`totalSupply()`, or use the ids from its mint transactions.
3. **Keep the claimable ones** — `claimed(id)` (`0xdbe7e3bd`) is 0 AND `claimOpensAt(fieldOf(id))` is in the past. Helpers: `fieldOf(id)` `0x2191d452` · `claimOpensAt(field)` `0xd0eec3d0` · reward per Pass = `fieldReward(field)` `0x795d9e74`.
4. **Claim** — `claim(ids)` (`0x6ba4c138`), one array of all claimable ids, value = 0.0002 BNB × number of ids.
5. **Verify** — re-check the $BGEM balance and report how much arrived. If nothing is claimable yet, report when the Field's claims open — claims never expire.

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
