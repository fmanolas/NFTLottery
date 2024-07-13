// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NFTLottery is ReentrancyGuard {
    struct NFT {
        uint256 id;
        uint256 rarityScore;
        string series;
    }

        address public owner;
    IERC20 public BIA_TOKEN;
    uint256 public currentJackpotBIA;
    uint256 public currentJackpotETH;
    uint256 public drawCount;
    uint256 public totalBIAAllocated;
    uint256 public totalETHAllocated;
    uint256 public minRarity = 10000;
    uint256 public maxRarity = 100000;

    uint256[] public nftIdsA;
    uint256[] public nftIdsB;
    mapping(uint256 => NFT) public nfts;
    mapping(uint256 => uint256) public rarityScores;
    mapping(uint256 => bool) public isNFTActive;
    mapping(uint256 => address) public nftOwners;
    mapping(address => uint256) public pendingWithdrawalsBIA;
    mapping(address => uint256) public pendingWithdrawalsETH;

    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);
    event FundsInjected(uint256 biaAmount, uint256 ethAmount);
    event FundsClaimed(address indexed claimer, uint256 amount, string currency);

    constructor(address _biaToken) {
        owner = msg.sender;
        BIA_TOKEN = IERC20(_biaToken);
        drawCount = 0;
        currentJackpotBIA = 0;
        currentJackpotETH = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function addNFTs(NFT[] memory _nfts, address[] memory _owners, string memory series) public onlyOwner {
        require(_nfts.length == _owners.length, "NFTs and owners length mismatch");
        for (uint256 i = 0; i < _nfts.length; i++) {
            require(_nfts[i].id >= 0 && _nfts[i].id <= 7679, "ID out of range");
            require(!isNFTActive[_nfts[i].id], "NFT already active");
            nfts[_nfts[i].id] = _nfts[i];
            rarityScores[_nfts[i].id] = _nfts[i].rarityScore;
            isNFTActive[_nfts[i].id] = true;
            nftOwners[_nfts[i].id] = _owners[i];

            if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("A"))) {
                nftIdsA.push(_nfts[i].id);
            } else if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("B"))) {
                nftIdsB.push(_nfts[i].id);
            }
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

    function generateRandomNumber(uint256 min, uint256 max) internal view returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (max - min + 1)) + min;
    }

    function calculateJackpot() internal view returns (uint256, string memory) {
        uint256 amount;
        string memory currency;

        if (drawCount < 6 || drawCount % 2 == 0) {
            currency = "$BIA";
            amount = (generateRandomNumber(5, 20) * currentJackpotBIA) / 100;
        } else {
            currency = "$ETH";
            amount = (generateRandomNumber(5, 20) * currentJackpotETH) / 100;
        }

        return (amount, currency);
    }

    function selectWinners() public onlyOwner {
        uint256 seriesSelection = generateRandomNumber(1, 2); // 1 for Series A, 2 for Series B
        uint256 drawType = generateRandomNumber(0, 1); // 0: Single, 1: Multiple
        uint256 rarityMode = generateRandomNumber(0, 2); // 0: Higher, 1: Lower, 2: In-Between

        uint256[] memory eligibleNFTs = new uint256[](nftIdsA.length + nftIdsB.length);
        uint256 eligibleCount = 0;
        uint256 threshold = generateRandomNumber(minRarity, maxRarity); // Random rarity threshold for comparison

        uint256[] storage seriesNFTs = seriesSelection == 1 ? nftIdsA : nftIdsB;

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
        uint256[] memory winners = new uint256[](drawType == 0 ? 1 : (eligibleCount > 2 ? generateRandomNumber(2, eligibleCount * 2 / 3) : eligibleCount));
    
        for (uint256 i = 0; i < winners.length; i++) {
            winners[i] = eligibleNFTs[generateRandomNumber(0, eligibleCount - 1)];
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
    }
    
     function claimFunds(uint256 nftId) public nonReentrant {
        require(isNFTActive[nftId], "NFT is not active");
        require(nftOwners[nftId] == msg.sender, "Not the owner of the NFT");

        uint256 biaAmount = pendingWithdrawalsBIA[msg.sender];
        uint256 ethAmount = pendingWithdrawalsETH[msg.sender];

        require(biaAmount > 0 || ethAmount > 0, "No funds to claim");

        if (biaAmount > 0) {
            pendingWithdrawalsBIA[msg.sender] -= biaAmount;  // Correct handling to subtract claimed amount
            require(BIA_TOKEN.transfer(msg.sender, biaAmount), "BIA transfer failed");
            emit FundsClaimed(msg.sender, biaAmount, "$BIA");
        }

        if (ethAmount > 0) {
            pendingWithdrawalsETH[msg.sender] -= ethAmount;  // Correct handling to subtract claimed amount
            payable(msg.sender).transfer(ethAmount);
            emit FundsClaimed(msg.sender, ethAmount, "$ETH");
        }
    }
}
