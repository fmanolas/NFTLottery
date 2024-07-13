// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract NFTLottery {
    struct NFT {
        uint256 id;
        uint256 rarityScore;
        string series; // Either "A" or "B"
    }

    address public owner;
    uint256 public currentJackpotBIA;
    uint256 public currentJackpotETH;
    uint256 public drawCount;
    uint256 public totalBIAAllocated;
    uint256 public totalETHAllocated;
    uint256 public minRarity = 10000; // Adjusted minimum rarity
    uint256 public maxRarity = 100000; // Fixed maximum rarity
    uint256 public Total_Funds_BIA = 12_000_000_000 * 1e18; // 12B BIA with 18 decimal places

    mapping(uint256 => NFT) public nfts;
    mapping(uint256 => uint256) public rarityScores;
    mapping(uint256 => bool) public isNFTActive;  // Use a boolean mapping to track active NFTs

    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);

    constructor(NFT[] memory seriesA, NFT[] memory seriesB) {
        owner = msg.sender;
        drawCount = 0;

        // Initialize NFTs for Series A
        for (uint256 i = 0; i < seriesA.length; i++) {
            NFT memory nft = seriesA[i];
            require(nft.id >= 0 && nft.id <= 7679, "ID out of range");
            nfts[nft.id] = nft;
            rarityScores[nft.id] = nft.rarityScore;
            isNFTActive[nft.id] = true;

            if (nft.rarityScore < minRarity) {
                minRarity = nft.rarityScore;
            }
        }

        // Initialize NFTs for Series B
        for (uint256 i = 0; i < seriesB.length; i++) {
            NFT memory nft = seriesB[i];
            require(nft.id >= 0 && nft.id <= 7679, "ID out of range");
            nfts[nft.id] = nft;
            rarityScores[nft.id] = nft.rarityScore;
            isNFTActive[nft.id] = true;

            if (nft.rarityScore < minRarity) {
                minRarity = nft.rarityScore;
            }
        }

        // Set initial BIA and ETH jackpot amounts
        currentJackpotBIA = (Total_Funds_BIA * 1) / 100; // 1% of Total Funds as initial BIA jackpot
        currentJackpotETH = 0; // Start with no ETH in the jackpot
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function injectFunds(uint256 biaAmount, uint256 ethAmount) public onlyOwner {
        require(biaAmount > 0 || ethAmount > 0, "At least one amount must be greater than zero");
        currentJackpotBIA += biaAmount;
        currentJackpotETH += ethAmount;
        totalBIAAllocated += biaAmount;
        totalETHAllocated += ethAmount;
    }

    function generateRandomNumber(uint256 min, uint256 max) internal view returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (max - min + 1)) + min;
    }

    function calculateJackpot() internal view returns (uint256, string memory) {
        uint256 amount;
        string memory currency;

        // Determine jackpot based on the draw count
        if (drawCount < 6 || drawCount % 2 == 0) {
            currency = "$BIA";
            // Jackpot amount is a percentage of the current BIA jackpot
            amount = (generateRandomNumber(10, 20) * currentJackpotBIA) / 100;
        } else {
            currency = "$ETH";
            // Jackpot amount is a percentage of the current ETH jackpot
            amount = (generateRandomNumber(10, 20) * currentJackpotETH) / 100;
        }

        // Modify the jackpot amount based on draw type
        if (drawCount % 2 == 0) {
            // Multi-winner draw
            amount = (amount * 2) / 3; // 2/3 of the calculated jackpot amount for multi-winner
        } else {
            // Single winner draw
            amount = amount / 3; // 1/3 of the calculated jackpot amount for single winner
        }

        return (amount, currency);
    }

    function selectWinners(string memory series) public onlyOwner {
        uint256 randomRarity = generateRandomNumber(minRarity, maxRarity);
        uint256 mode = generateRandomNumber(0, 2); // 0: Above, 1: Below, 2: Between
        uint256[] memory eligibleNFTs = new uint256[](7680);
        uint256 eligibleCount = 0;

        for (uint256 i = 0; i <= 7679; i++) {
            if (isNFTActive[i] && keccak256(bytes(nfts[i].series)) == keccak256(bytes(series))) {
                if ((mode == 0 && rarityScores[i] > randomRarity) ||
                    (mode == 1 && rarityScores[i] < randomRarity) ||
                    (mode == 2 && rarityScores[i] >= randomRarity / 2 && rarityScores[i] <= randomRarity * 1.5)) {
                    eligibleNFTs[eligibleCount] = i;
                    eligibleCount++;
                }
            }
        }

        require(eligibleCount > 0, "No eligible NFTs found");

        (uint256 jackpotAmount, string memory currency) = calculateJackpot();
        uint256[] memory winners;

        if (drawCount % 2 == 0) {
            // Multi-winner draw
            uint256 maxWinners = eligibleCount > 2 ? generateRandomNumber(2, eligibleCount * 2 / 3) : eligibleCount;
            winners = new uint256[](maxWinners);
            for (uint256 i = 0; i < maxWinners; i++) {
                winners[i] = eligibleNFTs[generateRandomNumber(0, eligibleCount - 1)];
            }
        } else {
            // Single winner draw
            winners = new uint256 ;
            winners[0] = eligibleNFTs[generateRandomNumber(0, eligibleCount - 1)];
        }

        drawCount++;
        if (keccak256(bytes(currency)) == keccak256(bytes("$BIA"))) {
            require(currentJackpotBIA >= jackpotAmount, "Insufficient BIA in jackpot");
            currentJackpotBIA -= jackpotAmount;
        } else {
            require(currentJackpotETH >= jackpotAmount, "Insufficient ETH in jackpot");
            currentJackpotETH -= jackpotAmount;
        }

        emit DrawWinner(winners, jackpotAmount, currency);
    }
}
