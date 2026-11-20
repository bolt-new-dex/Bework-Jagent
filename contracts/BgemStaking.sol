// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title BgemStaking — stake BEWORK NFTs, earn BGEM.
/// @notice BNB Smart Chain (chain ID 56). Holders stake BEWORK NFTs
/// (0x78eDD42101e889cC3Ce4B24CBb0Fc774082BcAee) into this contract and earn
/// the BGEM token over time. The BEWORK NFT contract itself is NOT modified
/// in any way — staking works through standard ERC-721 approvals/transfers.
///
/// Economics (initial values, all owner-adjustable except where noted):
/// - Reward rate: 10 BGEM per staked NFT per hour (240 BGEM / day / NFT).
/// - Claim: reward tokens are transferred DIRECTLY to the claimer's wallet
///   inside the claim transaction. There is no manual distribution — the
///   owner only funds the reward reserve (a BGEM balance held by this
///   contract) up front and tops it up when it runs low.
/// - Claim fee: every claim must attach 0.00022 BNB (native). The fee stays
///   in this contract and can be withdrawn by the owner (withdrawFees). A
///   reverted claim does NOT consume the fee.
/// - Minimum claim: 10 BGEM of settled rewards.
/// - If the reserve holds less than a user's settled rewards, claim pays
///   what is available and the remainder stays recorded as pending — rewards
///   are never lost, and unstaking is never blocked by the reward balance.
/// - Unstake is always free and always available: a user's NFTs are never
///   locked by fees or by the reserve state.
///
/// Reward accounting: a global per-NFT cumulative index (accPerNft, scaled
/// by 1e18) grows by rewardRatePerHour over time; each user's rewards are
/// settled lazily against their snapshot whenever they stake, unstake or
/// claim. Changing the rate only affects future accrual.
contract BgemStaking is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    uint256 private constant ACC_SCALE = 1e18;

    /// @notice The BEWORK NFT collection that can be staked.
    IERC721 public immutable nft;
    /// @notice The BGEM reward token paid out by claims.
    IERC20 public immutable rewardToken;

    /// @notice BGEM (in wei) earned by one staked NFT per hour.
    uint256 public rewardRatePerHour;
    /// @notice Native BNB (in wei) that must accompany every claim.
    uint256 public claimFee;
    /// @notice Minimum settled rewards (BGEM wei) required to claim.
    uint256 public minClaim;

    /// @notice Cumulative BGEM wei earned per staked NFT, scaled by 1e18.
    uint256 public accPerNft;
    /// @notice Last timestamp accPerNft was brought up to date.
    uint256 public lastAccUpdate;
    /// @notice Total NFTs currently staked by everyone.
    uint256 public totalStaked;

    /// @notice tokenId -> the wallet that staked it (zero if not staked here).
    mapping(uint256 => address) public stakerOf;
    /// @notice user -> tokenIds they currently have staked.
    mapping(address => uint256[]) private _stakedIds;
    /// @notice tokenId -> its index inside the staker's _stakedIds array.
    mapping(uint256 => uint256) private _indexInStakedIds;
    /// @notice user -> accPerNft snapshot at their last settlement.
    mapping(address => uint256) private _snapAcc;
    /// @notice user -> settled but not yet claimed BGEM wei.
    mapping(address => uint256) public pending;

    event Staked(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId);
    event Claimed(address indexed user, uint256 paid, uint256 feePaid);
    event RewardRateChanged(uint256 newRatePerHour);
    event ClaimFeeChanged(uint256 newClaimFee);
    event MinClaimChanged(uint256 newMinClaim);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event NftRescued(uint256 indexed tokenId, address indexed to);

    constructor(
        address nft_,
        address rewardToken_,
        uint256 rewardRatePerHour_,
        uint256 claimFee_,
        uint256 minClaim_
    ) {
        require(nft_ != address(0) && rewardToken_ != address(0), "zero address");
        nft = IERC721(nft_);
        rewardToken = IERC20(rewardToken_);
        rewardRatePerHour = rewardRatePerHour_;
        claimFee = claimFee_;
        minClaim = minClaim_;
        lastAccUpdate = block.timestamp;
    }

    /* ------------------------- reward accounting ------------------------ */

    function _accNow() internal view returns (uint256) {
        if (block.timestamp <= lastAccUpdate) return accPerNft;
        return accPerNft + (rewardRatePerHour * (block.timestamp - lastAccUpdate) * ACC_SCALE) / 3600;
    }

    function _updateAcc() internal {
        accPerNft = _accNow();
        lastAccUpdate = block.timestamp;
    }

    function _settle(address user) internal {
        _updateAcc();
        uint256 count = _stakedIds[user].length;
        if (count > 0 && accPerNft > _snapAcc[user]) {
            pending[user] += (count * (accPerNft - _snapAcc[user])) / ACC_SCALE;
        }
        _snapAcc[user] = accPerNft;
    }

    /// @notice Settled + still-accruing claimable rewards for a user (BGEM wei).
    function pendingReward(address user) public view returns (uint256) {
        uint256 acc = _accNow();
        uint256 extra = 0;
        uint256 count = _stakedIds[user].length;
        if (count > 0 && acc > _snapAcc[user]) {
            extra = (count * (acc - _snapAcc[user])) / ACC_SCALE;
        }
        return pending[user] + extra;
    }

    /* ------------------------------ staking ----------------------------- */

    /// @notice Stake BEWORK NFTs. The caller must own them and must have
    /// approved this contract (approve or setApprovalForAll on the NFT).
    function stake(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length > 0, "no token ids");
        _settle(msg.sender);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            require(stakerOf[id] == address(0), "already staked");
            stakerOf[id] = msg.sender;
            _indexInStakedIds[id] = _stakedIds[msg.sender].length;
            _stakedIds[msg.sender].push(id);
            totalStaked += 1;
            nft.transferFrom(msg.sender, address(this), id);
            emit Staked(msg.sender, id);
        }
    }

    /// @notice Unstake NFTs. Rewards accrued so far are settled into the
    /// pending balance (claim them separately). Never blocked, never fee'd.
    function unstake(uint256[] calldata tokenIds) external nonReentrant {
        require(tokenIds.length > 0, "no token ids");
        _settle(msg.sender);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            require(stakerOf[id] == msg.sender, "not your stake");
            uint256 idx = _indexInStakedIds[id];
            uint256 lastId = _stakedIds[msg.sender][_stakedIds[msg.sender].length - 1];
            _stakedIds[msg.sender][idx] = lastId;
            _indexInStakedIds[lastId] = idx;
            _stakedIds[msg.sender].pop();
            delete _indexInStakedIds[id];
            delete stakerOf[id];
            totalStaked -= 1;
            nft.transferFrom(address(this), msg.sender, id);
            emit Unstaked(msg.sender, id);
        }
    }

    /* ------------------------------ claiming ---------------------------- */

    /// @notice Claim settled BGEM rewards straight into your wallet.
    /// Must attach at least claimFee BNB. If the reserve is short, pays what
    /// is available; the rest stays pending for a later claim.
    function claim() external payable nonReentrant {
        require(msg.value >= claimFee, "claim fee required");
        _settle(msg.sender);
        uint256 amt = pending[msg.sender];
        require(amt >= minClaim, "below min claim");
        uint256 bal = rewardToken.balanceOf(address(this));
        uint256 pay = amt <= bal ? amt : bal;
        require(pay > 0, "reserve empty");
        pending[msg.sender] = amt - pay;
        rewardToken.safeTransfer(msg.sender, pay);
        emit Claimed(msg.sender, pay, msg.value);
    }

    /* ------------------------------- views ------------------------------ */

    function stakedOf(address user) external view returns (uint256[] memory) {
        return _stakedIds[user];
    }

    function stakedCountOf(address user) external view returns (uint256) {
        return _stakedIds[user].length;
    }

    function reserveBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    /* --------------------------- owner controls -------------------------- */

    /// @notice Change the reward rate. Only future accrual uses the new rate.
    function setRewardRate(uint256 newRatePerHour) external onlyOwner {
        _updateAcc();
        rewardRatePerHour = newRatePerHour;
        emit RewardRateChanged(newRatePerHour);
    }

    function setClaimFee(uint256 newClaimFee) external onlyOwner {
        claimFee = newClaimFee;
        emit ClaimFeeChanged(newClaimFee);
    }

    function setMinClaim(uint256 newMinClaim) external onlyOwner {
        minClaim = newMinClaim;
        emit MinClaimChanged(newMinClaim);
    }

    /// @notice Withdraw the accumulated native claim fees to the owner.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        require(amount > 0, "no fees");
        (bool ok, ) = owner().call{value: amount}("");
        require(ok, "withdraw failed");
        emit FeesWithdrawn(owner(), amount);
    }

    /// @notice Withdraw BGEM from the reward reserve (owner reserve management).
    function withdrawReserve(uint256 amount) external onlyOwner {
        rewardToken.safeTransfer(owner(), amount);
        emit ReserveWithdrawn(owner(), amount);
    }

    /// @notice Rescue a BEWORK NFT that reached this contract without being
    /// staked (e.g. sent by a plain transfer). Recorded stakes cannot be rescued.
    function rescueNft(uint256 tokenId, address to) external onlyOwner nonReentrant {
        require(stakerOf[tokenId] == address(0), "token is staked");
        require(to != address(0), "zero address");
        nft.transferFrom(address(this), to, tokenId);
        emit NftRescued(tokenId, to);
    }

    /* --------------------------- ERC721 receiver ------------------------- */

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(msg.sender == address(nft), "only BEWORK NFTs");
        return IERC721Receiver.onERC721Received.selector;
    }
}
