// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract NFTLottery {
    struct NFT {
        uint256 id;
        uint256 rarityScore;
        string series; // Either "A" or "B"
    }

    address public owner;
    IERC20 public BIA_TOKEN;
    uint256 public currentJackpotBIA;
    uint256 public currentJackpotETH;
    uint256 public drawCount;
    uint256 public totalBIAAllocated;
    uint256 public totalETHAllocated;
    uint256 public minRarity = 10000; // Minimum rarity
    uint256 public maxRarity = 100000; // Fixed maximum rarity
    uint256 public Total_Funds_BIA = 12_000_000_000 * 1e18; // 12B BIA with 18 decimal places

    // Data Structures for NFTs
    mapping(uint256 => NFT) public nfts;
    mapping(uint256 => uint256) public rarityScores;
    mapping(uint256 => bool) public isNFTActive;
    mapping(uint256 => address) public nftOwners; // Store the owner of each NFT
    mapping(address => uint256) public pendingWithdrawalsBIA;
    mapping(address => uint256) public pendingWithdrawalsETH;

    uint256[] public nftIdsA; // Store IDs of Series A NFTs
    uint256[] public nftIdsB; // Store IDs of Series B NFTs

    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);
    event FundsInjected(uint256 biaAmount, uint256 ethAmount);
    event FundsClaimed(address winner, uint256 amount, string currency);

    constructor(address _biaTokenAddress) {
        owner = msg.sender;
        drawCount = 0;
        BIA_TOKEN = IERC20(_biaTokenAddress);
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
        if (biaAmount > 0) {
            require(BIA_TOKEN.transferFrom(msg.sender, address(this), biaAmount), "BIA transfer failed");
            currentJackpotBIA += biaAmount;
            totalBIAAllocated += biaAmount;
        }
        if (ethAmount > 0) {
            currentJackpotETH += ethAmount;
            totalETHAllocated += ethAmount;
        }
        emit FundsInjected(biaAmount, ethAmount);
    }

    function addNFTs(NFT[] memory _predefinedNFTsA, NFT[] memory _predefinedNFTsB) public onlyOwner {
        for (uint256 i = 0; i < _predefinedNFTsA.length; i++) {
            NFT memory nft = _predefinedNFTsA[i];
            require(nft.id >= 0 && nft.id <= 7679, "ID out of range");
            nfts[nft.id] = nft;
            rarityScores[nft.id] = nft.rarityScore;
            isNFTActive[nft.id] = true;
            nftIdsA.push(nft.id);
            if (nft.rarityScore < minRarity) {
                minRarity = nft.rarityScore;
            }
        }

        for (uint256 i = 0; i < _predefinedNFTsB.length; i++) {
            NFT memory nft = _predefinedNFTsB[i];
            require(nft.id >= 0 && nft.id <= 7679, "ID out of range");
            nfts[nft.id] = nft;
            rarityScores[nft.id] = nft.rarityScore;
            isNFTActive[nft.id] = true;
            nftIdsB.push(nft.id);
            if (nft.rarityScore < minRarity) {
                minRarity = nft.rarityScore;
            }
        }
    }

    function generateRandomNumber(uint256 min, uint256 max) internal view returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % (max - min + 1)) + min;
    }

    function calculateJackpot() public view returns (uint256, string memory) {
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

        drawCount++;
        if (keccak256(bytes(currency)) == keccak256(bytes("$BIA"))) {
            require(currentJackpotBIA >= jackpotAmount, "Insufficient BIA in jackpot");
            currentJackpotBIA -= jackpotAmount;
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsBIA[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        } else {
            require(currentJackpotETH >= jackpotAmount, "Insufficient ETH in jackpot");
            currentJackpotETH -= jackpotAmount;
            for (uint256 i = 0; i < winners.length; i++) {
                pendingWithdrawalsETH[nftOwners[winners[i]]] += jackpotAmount / winners.length;
            }
        }

        emit DrawWinner(winners, jackpotAmount, currency);
    }

    function claimFunds() public {
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
            payable(msg.sender).transfer(ethAmount);
            emit FundsClaimed(msg.sender, ethAmount, "$ETH");
        }
    }

    // Function to receive ETH
    receive() external payable {}
}
