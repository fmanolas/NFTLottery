// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTLottery is ReentrancyGuard {
    struct NFT {
        uint256 id;
        uint256 rarityScore;
        string series;
    }

    address public owner;
    IERC20 public BIA_TOKEN;
    IERC721 public NFT_CONTRACT;
    uint256 public currentJackpotBIA;
    uint256 public currentJackpotETH;
    uint256 public drawCount;
    uint256 public totalBIAAllocated;
    uint256 public totalETHAllocated;
    uint256 public minRarity = 10000;
    uint256 public maxRarity = 100000;
    uint256 public nonce;
    uint256 public targetBlockNumber;
    uint256 public finalizeBlockNumber;

    uint256[] public nftIdsA;
    uint256[] public nftIdsB;
    mapping(uint256 => NFT) public nfts;
    mapping(uint256 => uint256) public rarityScores;
    mapping(uint256 => bool) public isNFTActive;
    mapping(uint256 => address) public nftOwners;
    mapping(address => uint256) public pendingWithdrawalsBIA;
    mapping(address => uint256) public pendingWithdrawalsETH;

    uint256 public gameMode;
    uint256 public numberOfWinners;
    uint256 public jackpotSize;
    uint256 public seriesSelection;
    uint256 public rarityMode;
    uint256 public threshold;

    event DrawInitialized(uint256 gameMode, uint256 numberOfWinners, uint256 jackpotSize, uint256 seriesSelection, uint256 rarityMode, uint256 threshold);
    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);
    event FundsInjected(uint256 biaAmount, uint256 ethAmount);
    event FundsClaimed(address indexed claimer, uint256 amount, string currency);
    event NFTAdded(uint256 id, uint256 rarityScore, string series, address owner);

    bytes32 public lastRandomHash;

    constructor(address _biaToken, address _nftContract) {
        owner = msg.sender;
        BIA_TOKEN = IERC20(_biaToken);
        NFT_CONTRACT = IERC721(_nftContract);
        drawCount = 0;
        currentJackpotBIA = 0;
        currentJackpotETH = 0;
        nonce = 0;
        targetBlockNumber = 0;
        finalizeBlockNumber = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier onlyNFTOwner(uint256 nftId) {
        require(NFT_CONTRACT.ownerOf(nftId) == msg.sender, "Not the owner of the specified NFT");
        _;
    }

    function addNFTs(NFT[] memory _nfts, address[] memory _owners, string memory series) public onlyOwner {
        require(_nfts.length == _owners.length, "NFTs and owners length mismatch");
        for (uint256 i = 0; i < _nfts.length; i++) {
            require(_nfts[i].id >= 0 && _nfts[i].id <= 7679, "ID out of range");
            require(!isNFTActive[_nfts[i].id], "NFT already active");
            require(NFT_CONTRACT.ownerOf(_nfts[i].id) == _owners[i], "Owner does not own the specified NFT");
            nfts[_nfts[i].id] = _nfts[i];
            rarityScores[_nfts[i].id] = _nfts[i].rarityScore;
            isNFTActive[_nfts[i].id] = true;
            nftOwners[_nfts[i].id] = _owners[i];

            if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("A"))) {
                nftIdsA.push(_nfts[i].id);
            } else if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("B"))) {
                nftIdsB.push(_nfts[i].id);
            }

            emit NFTAdded(_nfts[i].id, _nfts[i].rarityScore, series, _owners[i]);
        }
    }

    function injectBIAFunds(uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(BIA_TOKEN.transferFrom(msg.sender, address(this), amount), "BIA transfer failed");
        currentJackpotBIA += amount;
        totalBIAAllocated += amount;
        emit FundsInjected(amount, 0);
    }

    function injectETHFunds() public payable onlyOwner {
        require(msg.value > 0, "Amount must be greater than zero");
        currentJackpotETH += msg.value;
        totalETHAllocated += msg.value;
        emit FundsInjected(0, msg.value);
    }

    function randomFunction1() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp)));
    }

    function randomFunction2(uint256 localNonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(msg.sender, localNonce)));
    }

    function randomFunction3() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, gasleft())));
    }

    function combinedRandomNumber() internal returns (uint256) {
        uint256 rand1 = randomFunction1();
        uint256 rand2 = randomFunction2(nonce);
        uint256 rand3 = randomFunction3();
        lastRandomHash = keccak256(abi.encodePacked(rand1, rand2, rand3));
        nonce++;
        return uint256(lastRandomHash);
    }

    function calculateJackpot() internal view returns (uint256, string memory) {
        uint256 amount;
        string memory currency;

        if (drawCount < 6 || drawCount % 2 == 0) {
            currency = "$BIA";
            amount = (uint256(lastRandomHash) % 16 + 5) * currentJackpotBIA / 100;
        } else {
            currency = "$ETH";
            amount = (uint256(lastRandomHash) % 16 + 5) * currentJackpotETH / 100;
        }

        return (amount, currency);
    }

    function initializeDraw() public onlyOwner {
        require(targetBlockNumber == 0 && finalizeBlockNumber == 0, "A draw is already in progress");

        uint256 initialRandom = combinedRandomNumber();

        // Determine the mode of the game
        gameMode = initialRandom % 2; // 0 for single winner, 1 for multiple winners
        // Determine the number of winners
        numberOfWinners = (initialRandom / 2 % 10) + 1; // 1 to 10 winners
        // Determine the size of the jackpot
        jackpotSize = (initialRandom / 12 % 20) + 1; // 1% to 20% of the current jackpot

        seriesSelection = (initialRandom / 32 % 2) + 1; // 1 for Series A, 2 for Series B
        rarityMode = (initialRandom / 64 % 3); // 0: Higher, 1: Lower, 2: In-Between
        threshold = (initialRandom / 128 % (maxRarity - minRarity + 1)) + minRarity; // Random rarity threshold for comparison

        targetBlockNumber = block.number + (initialRandom / 256 % 20) + 5; // Random delay of 5 to 25 blocks

        emit DrawInitialized(gameMode, numberOfWinners, jackpotSize, seriesSelection, rarityMode, threshold);
    }

    function finalizeDraw() public onlyOwner {
        require(targetBlockNumber > 0 && block.number >= targetBlockNumber, "Cannot finalize draw yet");
        require(finalizeBlockNumber == 0, "Winner selection already in progress");

        finalizeBlockNumber = block.number + (combinedRandomNumber() % 20) + 5; // Random delay of 5 to 25 blocks
    }

    function selectWinners() public onlyOwner {
        require(finalizeBlockNumber > 0 && block.number >= finalizeBlockNumber, "Cannot select winners yet");

        uint256 finalRandom = combinedRandomNumber();

        uint256[] storage seriesNFTs = seriesSelection == 1 ? nftIdsA : nftIdsB;

        uint256[] memory eligibleNFTs = new uint256[](seriesNFTs.length);
        uint256 eligibleCount = 0;

        for (uint256 i = 0; i < seriesNFTs.length; i++) {
            uint256 id = seriesNFTs[i];
            uint256 rarity = rarityScores[id];

            bool isEligible = false;
            if (rarityMode == 0 && rarity > threshold) { // Higher
                isEligible = true;
            } else if (rarityMode == 1 && rarity < threshold) { // Lower
                isEligible = true;
            } else if (rarityMode == 2 && rarity >= threshold / 2 && rarity <= (maxRarity * 3) / 2) { // In-Between
                isEligible = true;
            }

            if (isEligible && isNFTActive[id]) {
                eligibleNFTs[eligibleCount++] = id;
            }
        }

        require(eligibleCount > 0, "No eligible NFTs found");

        (uint256 jackpotAmount, string memory currency) = calculateJackpot();
        jackpotAmount = (jackpotAmount * jackpotSize) / 100; // Adjust jackpot size

        uint256[] memory winners = new uint256[](gameMode == 0 ? 1 : (eligibleCount > numberOfWinners ? numberOfWinners : eligibleCount));

        for (uint256 i = 0; i < winners.length; i++) {
            winners[i] = eligibleNFTs[finalRandom % eligibleCount];
            finalRandom = uint256(keccak256(abi.encodePacked(finalRandom, i))); // Update finalRandom for next selection
        }

        if (keccak256(bytes(currency)) == keccak256(bytes("$BIA"))) {
            require(currentJackpotBIA >= jackpotAmount, "Insufficient BIA in jackpot");
            currentJackpotBIA -= jackpotAmount;
            totalBIAAllocated -= jackpotAmount;
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsBIA[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        } else {
            require(currentJackpotETH >= jackpotAmount, "Insufficient ETH in jackpot");
            currentJackpotETH -= jackpotAmount;
            totalETHAllocated -= jackpotAmount;
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsETH[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        }

        emit DrawWinner(winners, jackpotAmount, currency);

        // Reset targetBlockNumber and finalizeBlockNumber for next draw
        targetBlockNumber = 0;
        finalizeBlockNumber = 0;
    }

    function claimFunds(uint256 nftId) public nonReentrant onlyNFTOwner(nftId) {
        require(isNFTActive[nftId], "NFT is not active");

        uint256 biaAmount = pendingWithdrawalsBIA[msg.sender];
        uint256 ethAmount = pendingWithdrawalsETH[msg.sender];

        require(biaAmount > 0 || ethAmount > 0, "No funds to claim");

        if (biaAmount > 0) {
            pendingWithdrawalsBIA[msg.sender] = 0;
            require(BIA_TOKEN.transfer(msg.sender, biaAmount), "BIA transfer failed");
            emit FundsClaimed(msg.sender, biaAmount, "$BIA");
        }

        if (ethAmount > 0) {
            pendingWithdrawalsETH[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit FundsClaimed(msg.sender, ethAmount, "$ETH");
        }
    }
}
