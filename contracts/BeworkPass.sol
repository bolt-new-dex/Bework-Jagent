// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

/// @title BEWORK PASS — the 3,333 graded Mint Passes of BEWORK (Genesis 2026)
/// @notice Minting (BNB Smart Chain):
///         - Only wallets holding a Binance Agent ID can mint, only to
///           themselves. Max 12 Passes per wallet, 3,333 total.
///         - Free mints drop in ROUNDS: 333 free slots every 3 hours, at most
///           1 free per wallet per round. Every other mint costs 0.002 BNB.
///           quote() already accounts for the round slot — when the wallet's
///           round free is available, bnbWei comes back reduced by one unit.
///           Overpayment is refunded.
///         - quote() returns (paidUnits, bnbWei, usdAmount); the amount to
///           send is bnbWei, the SECOND value (usdAmount is always 0 — the
///           price is BNB-only).
///
///         $BGEM claims (DOTFIELD model on a 5-hour cycle):
///         - Time runs in FIELDS of 5 hours, anchored at the moment the mint
///           first opens (epoch). Every Pass belongs to the Field that was
///           open when it minted.
///         - When a Field seals, its tier locks by the number of Passes
///           minted inside it: 1-24 SPARK 2,500 · 25-74 CHARGED 12,500 ·
///           75-149 OVERDRIVE 60,000 · 150+ SURGE 150,000 BGEM per Pass.
///         - Claims open 1 hour after the seal, cost 0.0002 BNB per Pass,
///           and never expire. The claim pool (500,000,000 BGEM) is held by
///           this contract — fund it with a plain BGEM transfer.
contract BeworkPass is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ---------- locked numbers ----------
    uint256 public constant MAX_SUPPLY = 3333;
    uint256 public constant MAX_PER_WALLET = 12;
    uint256 public constant PRICE = 0.002 ether;
    uint256 public constant ROUND_LEN = 3 hours;
    uint256 public constant ROUND_FREE = 333;
    uint256 public constant FIELD_LEN = 5 hours;
    uint256 public constant CLAIM_DELAY = 1 hours;
    uint256 public constant CLAIM_FEE = 0.0002 ether;
    uint256 public constant REWARD_SPARK = 2_500 ether;
    uint256 public constant REWARD_CHARGED = 12_500 ether;
    uint256 public constant REWARD_OVERDRIVE = 60_000 ether;
    uint256 public constant REWARD_SURGE = 150_000 ether;
    /// @notice Binance Agent ID registry on BNB Chain. Read-only check; the
    ///         registry itself is not owned or controlled by this contract.
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    // ---------- state ----------
    IERC20 public bgem;
    uint256 public totalMinted;
    bool public mintOpen;
    uint256 public epoch; // start of round 0 / Field 1 — set at first open
    string private _baseTokenURI;

    mapping(address => uint256) public mintedBy;
    mapping(uint256 => uint256) public freeInRound; // round => free mints used
    mapping(address => mapping(uint256 => bool)) public freeUsedInRound;
    mapping(uint256 => uint256) public tokenField; // tokenId => Field number
    mapping(uint256 => uint256) public fieldCount; // Field => Passes minted in it
    mapping(uint256 => bool) public claimed; // tokenId => $BGEM claimed

    event MintOpenSet(bool open);
    event BaseURISet(string uri);
    event BgemSet(address token);
    event PassMinted(address indexed minter, uint256 indexed tokenId, uint256 indexed field, bool free);
    event Claimed(address indexed owner, uint256 indexed tokenId, uint256 indexed field, uint256 amount);

    constructor(address bgem_, string memory baseURI_) ERC721("BEWORK PASS", "BPASS") {
        bgem = IERC20(bgem_);
        _baseTokenURI = baseURI_;
    }

    // ---------- views the site + agents use ----------
    function totalSupply() public view returns (uint256) {
        return totalMinted;
    }

    function hasAgentId(address wallet) public view returns (bool) {
        return IAgentId(AGENT_ID_REGISTRY).balanceOf(wallet) > 0;
    }

    function mintedByWallet(address wallet) public view returns (uint256) {
        return mintedBy[wallet];
    }

    function currentRound() public view returns (uint256) {
        return epoch == 0 ? 0 : (block.timestamp - epoch) / ROUND_LEN;
    }

    function currentField() public view returns (uint256) {
        return epoch == 0 ? 0 : (block.timestamp - epoch) / FIELD_LEN + 1;
    }

    function freeLeftInRound() public view returns (uint256) {
        uint256 used = freeInRound[currentRound()];
        return used >= ROUND_FREE ? 0 : ROUND_FREE - used;
    }

    function freeAvailable(address wallet) public view returns (bool) {
        return mintOpen && epoch != 0 && !freeUsedInRound[wallet][currentRound()] && freeLeftInRound() > 0;
    }

    /// @notice (paidUnits, bnbWei, usdAmount) — send exactly bnbWei.
    function quote(address wallet, uint256 qty)
        public
        view
        returns (uint256 paidUnits, uint256 bnbWei, uint256 usdAmount)
    {
        uint256 freeUnits = (qty > 0 && freeAvailable(wallet)) ? 1 : 0;
        paidUnits = qty - freeUnits;
        bnbWei = paidUnits * PRICE;
        usdAmount = 0;
    }

    // ---------- mint ----------
    function mintWithBNB(uint256 qty) external payable nonReentrant {
        require(mintOpen, "mint closed");
        require(qty >= 1, "qty 0");
        require(mintedBy[msg.sender] + qty <= MAX_PER_WALLET, "wallet max 12");
        require(totalMinted + qty <= MAX_SUPPLY, "sold out");
        require(hasAgentId(msg.sender), "no Agent ID");

        uint256 round = currentRound();
        uint256 freeUnits = 0;
        if (!freeUsedInRound[msg.sender][round] && freeInRound[round] < ROUND_FREE) {
            freeUnits = 1;
            freeUsedInRound[msg.sender][round] = true;
            freeInRound[round] += 1;
        }
        uint256 cost = (qty - freeUnits) * PRICE;
        require(msg.value >= cost, "insufficient BNB");

        uint256 field = currentField();
        for (uint256 i = 0; i < qty; i++) {
            totalMinted += 1;
            tokenField[totalMinted] = field;
            _safeMint(msg.sender, totalMinted);
            emit PassMinted(msg.sender, totalMinted, field, freeUnits == 1 && i == 0);
        }
        mintedBy[msg.sender] += qty;
        fieldCount[field] += qty;

        if (msg.value > cost) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - cost}("");
            require(ok, "refund failed");
        }
    }

    // ---------- fields & claims ----------
    /// @notice $BGEM per Pass for a Field, from its final mint count. For a
    ///         Field that is still open this is the running projection.
    function fieldReward(uint256 field) public view returns (uint256) {
        uint256 n = fieldCount[field];
        if (n == 0) return 0;
        if (n >= 150) return REWARD_SURGE;
        if (n >= 75) return REWARD_OVERDRIVE;
        if (n >= 25) return REWARD_CHARGED;
        return REWARD_SPARK;
    }

    function fieldSealAt(uint256 field) public view returns (uint256) {
        return epoch == 0 ? 0 : epoch + field * FIELD_LEN;
    }

    /// @notice Claims for a Field open at its seal + 1 hour, never expire.
    function claimOpensAt(uint256 field) public view returns (uint256) {
        uint256 seal = fieldSealAt(field);
        return seal == 0 ? 0 : seal + CLAIM_DELAY;
    }

    function fieldOf(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "no token");
        return tokenField[tokenId];
    }

    function claim(uint256[] calldata tokenIds) external payable nonReentrant {
        require(tokenIds.length > 0, "no ids");
        uint256 fee = CLAIM_FEE * tokenIds.length;
        require(msg.value >= fee, "claim fee missing");

        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            require(ownerOf(id) == msg.sender, "not your Pass");
            require(!claimed[id], "already claimed");
            uint256 f = tokenField[id];
            require(f > 0 && block.timestamp >= claimOpensAt(f), "claim not open yet");
            claimed[id] = true;
            uint256 amount = fieldReward(f);
            total += amount;
            emit Claimed(msg.sender, id, f, amount);
        }
        require(total > 0, "nothing to claim");
        require(bgem.transfer(msg.sender, total), "BGEM transfer failed");

        if (msg.value > fee) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "refund failed");
        }
    }

    // ---------- owner ----------
    /// @notice The first open anchors the rounds + Fields clock (epoch).
    function setMintOpen(bool open_) external onlyOwner {
        if (open_ && epoch == 0) epoch = block.timestamp;
        mintOpen = open_;
        emit MintOpenSet(open_);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _baseTokenURI = uri;
        emit BaseURISet(uri);
    }

    function setBgem(address token) external onlyOwner {
        bgem = IERC20(token);
        emit BgemSet(token);
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

    // ---------- metadata ----------
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "no token");
        string memory base = _baseURI();
        return bytes(base).length > 0
            ? string(abi.encodePacked(base, tokenId.toString(), ".json"))
            : "";
    }
}
