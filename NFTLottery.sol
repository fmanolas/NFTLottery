// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBIA {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

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
    uint256 public minRarity = 10000; // Minimum rarity
    uint256 public maxRarity = 100000; // Fixed maximum rarity

    IBIA public BIA_TOKEN;

    mapping(uint256 => NFT) public nfts;
    mapping(uint256 => uint256) public rarityScores;
    mapping(uint256 => bool) public isNFTActive; // Use a boolean mapping to track active NFTs
    mapping(address => uint256) public pendingWithdrawalsBIA;
    mapping(address => uint256) public pendingWithdrawalsETH;
    mapping(uint256 => address) public nftOwners; // Mapping to track the owner of each NFT

    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);
    event FundsInjected(uint256 biaAmount, uint256 ethAmount);
    event FundsClaimed(address indexed claimer, uint256 amount, string currency);

    constructor(address _biaToken) {
        owner = msg.sender;
        BIA_TOKEN = IBIA(_biaToken);
        drawCount = 0;

        // Initialize NFT owners and rarity scores for predefined NFTs
        for (uint256 i = 0; i <= 7679; i++) {
            nfts[i] = NFT(i, (i % 100000) + 10000, i < 4223 ? "A" : "B"); // Assigning sample rarity scores and series
            rarityScores[i] = (i % 100000) + 10000;
            nftOwners[i] = owner;
            isNFTActive[i] = true;
        }

        // Set initial BIA and ETH jackpot amounts to zero
        currentJackpotBIA = 0;
        currentJackpotETH = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    function injectBIAFunds(uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than zero");
        require(BIA_TOKEN.transfer(address(this), amount), "BIA transfer failed");
        totalBIAAllocated += amount;
        emit FundsInjected(amount, 0);
    }

    function injectETHFunds() public payable onlyOwner {
        require(msg.value > 0, "Amount must be greater than zero");
        totalETHAllocated += msg.value;
        emit FundsInjected(0, msg.value);
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

        return (amount, currency);
    }

    function selectWinners() public onlyOwner {
        uint256 seriesSelection = generateRandomNumber(1, 2); // 1 for Series A, 2 for Series B
        uint256 drawType = generateRandomNumber(0, 1); // 0: Single, 1: Multiple
        uint256 rarityMode = generateRandomNumber(0, 2); // 0: Higher, 1: Lower, 2: In-Between

        uint256[] memory eligibleNFTs;
        uint256 eligibleCount = 0;

        // Choose the series based on equal probability
        if (seriesSelection == 1) {
            // Series A
            eligibleNFTs = new uint256[](nftIdsA.length);
            for (uint256 i = 0; i < nftIdsA.length; i++) {
                uint256 id = nftIdsA[i];
                if (isNFTActive[id] && rarityScores[id] >= minRarity && rarityScores[id] <= maxRarity) {
                    if ((rarityMode == 0 && rarityScores[id] > minRarity) ||
                        (rarityMode == 1 && rarityScores[id] < minRarity) ||
                        (rarityMode == 2 && rarityScores[id] >= minRarity / 2 && rarityScores[id] <= maxRarity * 1.5)) {
                        eligibleNFTs[eligibleCount] = id;
                        eligibleCount++;
                    }
                }
            }
        } else {
            // Series B
            eligibleNFTs = new uint256[](nftIdsB.length);
            for (uint256 i = 0; i < nftIdsB.length; i++) {
                uint256 id = nftIdsB[i];
                if (isNFTActive[id] && rarityScores[id] >= minRarity && rarityScores[id] <= maxRarity) {
                    if ((rarityMode == 0 && rarityScores[id] > minRarity) ||
                        (rarityMode == 1 && rarityScores[id] < minRarity) ||
                        (rarityMode == 2 && rarityScores[id] >= minRarity / 2 && rarityScores[id] <= maxRarity * 1.5)) {
                        eligibleNFTs[eligibleCount] = id;
                        eligibleCount++;
                    }
                }
            }
        }

        require(eligibleCount > 0, "No eligible NFTs found");

        (uint256 jackpotAmount, string memory currency) = calculateJackpot();
        uint256[] memory winners;
        if (drawType == 0) {
            // Single winner draw
            winners = new uint256 ;
            winners[0] = eligibleNFTs[generateRandomNumber(0, eligibleCount - 1)];
        } else {
            // Multiple winner draw
            uint256 maxWinners = eligibleCount > 2 ? generateRandomNumber(2, eligibleCount * 2 / 3) : eligibleCount;
            winners = new uint256[](maxWinners);
            for (uint256 i = 0; i < maxWinners; i++) {
                winners[i] = eligibleNFTs[generateRandomNumber(0, eligibleCount - 1)];
            }
        }

        // Reduce the jackpot amount and allocate funds to winners
        if (keccak256(bytes(currency)) == keccak256(bytes("$BIA"))) {
            require(currentJackpotBIA >= jackpotAmount, "Insufficient BIA in jackpot");
            currentJackpotBIA -= jackpotAmount;
            totalBIAAllocated -= jackpotAmount; // Deduct from total allocated BIA
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsBIA[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        } else {
            require(currentJackpotETH >= jackpotAmount, "Insufficient ETH in jackpot");
            currentJackpotETH -= jackpotAmount;
            totalETHAllocated -= jackpotAmount; // Deduct from total allocated ETH
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsETH[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        }

        emit DrawWinner(winners, jackpotAmount, currency);
    }

    function claimFunds() public {
        uint256 biaAmount = pendingWithdrawalsBIA[msg.sender];
        uint256 ethAmount = pendingWithdrawalsETH[msg.sender];

        if (biaAmount > 0) {
            pendingWithdrawalsBIA[msg.sender] = 0;
            require(BIA_TOKEN.transfer(msg.sender, biaAmount), "BIA transfer failed");
            emit FundsClaimed(msg.sender, biaAmount, "$BIA");
        }

        if (ethAmount > 0) {
            pendingWithdrawalsETH[msg.sender] = 0;
            payable(msg.sender).transfer(ethAmount);
            emit FundsClaimed(msg.sender, ethAmount, "$ETH");
        }
    }
}
