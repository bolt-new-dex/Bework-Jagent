// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IPassNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title BEWORK Forge — paid card upgrades for BEWORK PASS.
/// @notice Every Pass starts at level 0 (Bronze). The owner of a Pass can pay
///         BNB to raise it — 1 Silver, 2 Gold, 3 Platinum, 4 Master,
///         5 Diamond, 6 Shadow — and instantly receives a $BGEM reward from
///         this contract's pool for every level gained. Levels live here, not
///         in the Pass contract; the BEWORK site reads them to dress the card.
///         Overpayment is refunded in the same transaction.
contract BeworkForge is Ownable, ReentrancyGuard {
    IPassNFT public immutable pass;
    IERC20 public immutable bgem;
    bool public upgradesOpen;

    uint8 public constant MAX_LEVEL = 6;

    /// @notice PRICE[i] is the BNB cost of going from level i to level i+1.
    uint256[6] public PRICE = [
        0.001 ether, // Bronze   -> Silver
        0.002 ether, // Silver   -> Gold
        0.003 ether, // Gold     -> Platinum
        0.005 ether, // Platinum -> Master
        0.008 ether, // Master   -> Diamond
        0.012 ether  // Diamond  -> Shadow
    ];

    /// @notice REWARD[i] is the $BGEM paid out for going from level i to i+1.
    uint256[6] public REWARD = [
        10_000 ether,  // -> Silver
        25_000 ether,  // -> Gold
        50_000 ether,  // -> Platinum
        100_000 ether, // -> Master
        200_000 ether, // -> Diamond
        400_000 ether  // -> Shadow
    ];

    mapping(uint256 => uint8) public levelOf;

    event Upgraded(uint256 indexed tokenId, address indexed owner, uint8 newLevel, uint256 bgemReward);
    event UpgradesOpen(bool open);

    constructor(address pass_, address bgem_) {
        require(pass_ != address(0) && bgem_ != address(0), "zero address");
        pass = IPassNFT(pass_);
        bgem = IERC20(bgem_);
    }

    // ---------- views ----------

    function levelName(uint8 level) public pure returns (string memory) {
        if (level == 0) return "Bronze";
        if (level == 1) return "Silver";
        if (level == 2) return "Gold";
        if (level == 3) return "Platinum";
        if (level == 4) return "Master";
        if (level == 5) return "Diamond";
        return "Shadow";
    }

    /// @notice (bnbWei, bgemReward) to take a Pass from its current level to `target`.
    function priceTo(uint256 tokenId, uint8 target) public view returns (uint256 bnbWei, uint256 bgemReward) {
        uint8 cur = levelOf[tokenId];
        require(target > cur && target <= MAX_LEVEL, "bad target");
        for (uint8 i = cur; i < target; i++) {
            bnbWei += PRICE[i];
            bgemReward += REWARD[i];
        }
    }

    // ---------- upgrade ----------

    function _upgradeTo(uint256 tokenId, uint8 target) internal {
        require(upgradesOpen, "upgrades closed");
        require(pass.ownerOf(tokenId) == msg.sender, "not your Pass");
        (uint256 due, uint256 reward) = priceTo(tokenId, target);
        require(msg.value >= due, "not enough BNB");
        require(bgem.balanceOf(address(this)) >= reward, "reward pool empty");
        levelOf[tokenId] = target;
        require(bgem.transfer(msg.sender, reward), "reward failed");
        emit Upgraded(tokenId, msg.sender, target, reward);
        if (msg.value > due) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - due}("");
            require(ok, "refund failed");
        }
    }

    /// @notice Raise a Pass straight to `target` level in one transaction.
    function upgradeTo(uint256 tokenId, uint8 target) external payable nonReentrant {
        _upgradeTo(tokenId, target);
    }

    /// @notice Raise a Pass by exactly one level.
    function upgrade(uint256 tokenId) external payable nonReentrant {
        _upgradeTo(tokenId, levelOf[tokenId] + 1);
    }

    // ---------- owner ----------

    function setUpgradesOpen(bool open_) external onlyOwner {
        upgradesOpen = open_;
        emit UpgradesOpen(open_);
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "empty");
        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "withdraw failed");
    }

    function withdrawBgem(uint256 amount) external onlyOwner {
        require(bgem.transfer(owner(), amount), "BGEM transfer failed");
    }
}
