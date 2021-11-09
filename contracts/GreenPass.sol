// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract LL420GreenPass is ERC1155, ReentrancyGuard, Ownable {
    string private baseURI;

    uint256 public constant GREEN_PASS_FEE = 0.0420 ether;
    uint256 public constant BREEDER_PASS_FEE = 0.420 ether;
    uint256 public constant FARMER_PASS_FEE = 0.420 ether;
    uint256 public constant OG_TIME_LIMIT = 4 hours + 20 minutes;
    uint256 public constant GREEN_LIST_TIME_LIMIT = 4 hours + 20 minutes;
    uint8 public constant GREEN_PASS_TOKEN_ID = 0;
    uint8 public constant BREEDER_PASS_TOKEN_ID = 1;
    uint8 public constant FARMER_PASS_TOKEN_ID = 2;
    uint8 public constant OG_TOKEN_ID = 3;

    uint16[4] public supplyCaps = [10000, 2000, 2000, 420];

    bytes32 public immutable ogMerkleRoot;
    bytes32 public immutable greenListMerkleRoot;

    uint256 public startTimestamp;

    mapping(address => bool) public hasClaimed;
    mapping(address => bool) public hasOGClaimed;
    mapping(uint8 => uint16) public supplies;
    mapping(uint8 => string) public ipfsIds;

    event SetBaseURI(string indexed _baseURI);
    event SetStartTimestamp(uint256 indexed _timestamp);
    event ClaimOGNFT(address indexed _user);
    event ClaimGreenPassNFT(address indexed _user);

    modifier onlyUnclaimed() {
        require(hasClaimed[msg.sender] == false, "LL420GreenPass: Can't claim multiple times");

        _;
    }

    modifier onlyUnclaimedOG() {
        require(hasOGClaimed[msg.sender] == false, "LL420GreenPass: Can't claim multiple times");

        _;
    }

    modifier onlyStarted() {
        require(block.timestamp >= startTimestamp, "LL420GreenPass: Not started yet");

        _;
    }

    constructor(
        string memory _baseURI,
        uint256 _startTimestamp,
        bytes32 _ogMerkleRoot,
        bytes32 _greenListMerkleRoot
    ) ERC1155(_baseURI) {
        baseURI = _baseURI;
        ogMerkleRoot = _ogMerkleRoot;
        greenListMerkleRoot = _greenListMerkleRoot;
        startTimestamp = _startTimestamp;

        // TODO: Remove for mainnet launch
        ipfsIds[GREEN_PASS_TOKEN_ID] = "QmNbvABybV1fhYXawUTc72tYkBT9dd5ppZWhjTDfEarhnW";
        ipfsIds[BREEDER_PASS_TOKEN_ID] = "Qmf1dWtwvaNvDQ5YgknKK1vGbfae97KbKjbSaC1gBr457j";
        ipfsIds[FARMER_PASS_TOKEN_ID] = "QmT4QurVydbqJSKvxQAndXmE5QpV4kQdFnCgpjTRpj67ZA";
        ipfsIds[OG_TOKEN_ID] = "QmZNMdCzwQW4Bu8hrQoEgeSRtWzsYg3kEC5r12bDf58aYG";

        emit SetBaseURI(baseURI);
        emit SetStartTimestamp(startTimestamp);
    }

    function claim(bytes32[] calldata merkleProof) external payable nonReentrant onlyStarted onlyUnclaimed {
        require(msg.value == GREEN_PASS_FEE, "LL420GreenPass: Not enough fee");

        // Compute the node and verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        bool isOGVerified = MerkleProof.verify(merkleProof, ogMerkleRoot, node);
        uint256 timePeriod = block.timestamp - startTimestamp;

        if (timePeriod <= OG_TIME_LIMIT) {
            require(isOGVerified, "LL420GreenPass: Not allowed time");
        } else if (timePeriod <= OG_TIME_LIMIT + GREEN_LIST_TIME_LIMIT) {
            bool isGreenListVerified = MerkleProof.verify(merkleProof, greenListMerkleRoot, node);

            require(isOGVerified || isGreenListVerified, "LL420GreenPass: Not allowed time");
        }

        _mint(msg.sender, GREEN_PASS_TOKEN_ID, 1, "");
        hasClaimed[msg.sender] = true;

        emit ClaimGreenPassNFT(msg.sender);
    }

    function claimOG(bytes32[] calldata merkleProof) external nonReentrant onlyStarted onlyUnclaimedOG {
        // Compute the node and verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, ogMerkleRoot, node), "LL420GreenPass: Not OG address");

        _mint(msg.sender, OG_TOKEN_ID, 1, "");
        hasOGClaimed[msg.sender] = true;

        emit ClaimOGNFT(msg.sender);
    }

    function mintBreederPass() external payable nonReentrant onlyStarted {
        require(msg.value == BREEDER_PASS_FEE, "LL420GreenPass: Not enough fee");

        // TODO: allow muliple mints for single address?
        _mint(msg.sender, BREEDER_PASS_TOKEN_ID, 1, "");
    }

    function mintFarmerPass() external payable nonReentrant onlyStarted {
        require(msg.value == FARMER_PASS_FEE, "LL420GreenPass: Not enough fee");

        // TODO: allow muliple mints for single address?
        _mint(msg.sender, FARMER_PASS_TOKEN_ID, 1, "");
    }

    function setBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        startTimestamp = _startTimestamp;
        emit SetStartTimestamp(startTimestamp);
    }

    function uri(uint256 typeId) public view override returns (string memory) {
        require(
            typeId == GREEN_PASS_TOKEN_ID ||
                typeId == OG_TOKEN_ID ||
                typeId == BREEDER_PASS_TOKEN_ID ||
                typeId == FARMER_PASS_TOKEN_ID,
            "LL420GreenPass: URI requested for invalid token type"
        );
        require(bytes(baseURI).length > 0, "LL420GreenPass: base URI is not set");

        return string(abi.encodePacked(baseURI, ipfsIds[uint8(typeId)]));
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{ value: address(this).balance }("");

        require(success, "LL420GreenPass: Failed to withdraw to the owner");
    }

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal override {
        require(supplies[uint8(id)] < supplyCaps[uint8(id)], "LL420GreenPass: Suppy is limited");

        supplies[uint8(id)]++;
        super._mint(to, id, amount, data);
    }
}
