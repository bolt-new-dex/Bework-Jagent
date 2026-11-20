// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bework Gem (BGEM) — the BEWORK Gems ecosystem token (BEP-20).
/// @notice BNB Smart Chain (chain ID 56). Fixed supply, minted once at deploy:
/// - TOTAL_SUPPLY = 1,000,000,000 BGEM (1 billion), 18 decimals.
/// - The ENTIRE supply is minted to the deployer (the project owner) in the
///   constructor. There is NO mint function after deployment and no burn
///   function — the supply can never change.
/// - BGEM replaces the earlier WORK token as the ecosystem reward token:
///   BEWORK NFT holders earn BGEM by staking in BgemStaking. The WORK token
///   and its staking contract keep working untouched; BGEM runs beside them
///   with its own staking contract and reserve.
/// - Intended allocation (executed by the owner from their wallet, not
///   enforced on-chain): 50% staking reserve (funded into BgemStaking),
///   40% liquidity (LP), 10% treasury.
/// - No taxes, no fees, no blacklist, no proxy — a plain OpenZeppelin ERC-20.
/// - This token is separate from the BEWORK NFT (0x78eDD42101e889cC3Ce4B24CBb0Fc774082BcAee).
contract BgemToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Bework Gem", "BGEM") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
