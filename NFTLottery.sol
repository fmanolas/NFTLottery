// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract NFTLottery is ReentrancyGuard {
    using SafeMath for uint256;

    struct NFT {
        uint256 id;
        uint256 rarityScore;
        string series;
    }

    address public contractOwner;
    IERC20 public biaTokenContract;
    IERC721 public nftTokenContract;
    uint256 public currentBiaJackpot;
    uint256 public currentEthJackpot;
    uint256 public totalDraws;
    uint256 public totalBiaFunds;
    uint256 public totalEthFunds;
    uint256 public minimumRarity = 10000;
    uint256 public maximumRarity = 100000;
    uint256 public randomNonce;
    uint256 public targetBlock;
    uint256 public finalizeBlock;

    uint256[] public seriesANFTIds;
    uint256[] public seriesBNFTIds;
    mapping(uint256 => NFT) public nftData;
    mapping(uint256 => uint256) public nftRarityScores;
    mapping(uint256 => bool) public nftActiveStatus;
    mapping(uint256 => address) public nftOwnerAddresses;
    mapping(address => uint256) public biaPendingWithdrawals;
    mapping(address => uint256) public ethPendingWithdrawals;

    uint256 public gameMode;
    uint256 public winnersCount;
    uint256 public jackpotPercentage;
    uint256 public selectedSeries;
    uint256 public rarityMode;
    uint256 public rarityThreshold;

    event DrawInitialized(uint256 mode, uint256 numberOfWinners, uint256 jackpotSize, uint256 series, uint256 rarityMode, uint256 threshold);
    event DrawWinner(uint256[] winningNFTs, uint256 prizeAmount, string currency);
    event FundsInjected(uint256 biaAmount, uint256 ethAmount);
    event FundsClaimed(address indexed claimer, uint256 amount, string currency);
    event NFTAdded(uint256 id, uint256 rarityScore, string series, address owner);

    bytes32 public lastRandomHash;

    constructor(address biaTokenAddress, address nftTokenAddress) {
        contractOwner = msg.sender;
        biaTokenContract = IERC20(biaTokenAddress);
        nftTokenContract = IERC721(nftTokenAddress);
        totalDraws = 0;
        currentBiaJackpot = 0;
        currentEthJackpot = 0;
        randomNonce = 0;
        targetBlock = 0;
        finalizeBlock = 0;
    }

    modifier onlyContractOwner() {
        require(msg.sender == contractOwner, "Not the contract owner");
        _;
    }

    modifier onlyNFTOwner(uint256 nftId) {
        require(nftTokenContract.ownerOf(nftId) == msg.sender, "Not the owner of the specified NFT");
        _;
    }

    function addNFTs(NFT[] memory newNFTs, address[] memory nftOwners, string memory series) public onlyContractOwner {
        require(newNFTs.length == nftOwners.length, "NFTs and owners length mismatch");
        for (uint256 i = 0; i < newNFTs.length; i++) {
            require(newNFTs[i].id >= 0 && newNFTs[i].id <= 7679, "ID out of range");
            require(!nftActiveStatus[newNFTs[i].id], "NFT already active");
            require(nftTokenContract.ownerOf(newNFTs[i].id) == nftOwners[i], "Owner does not own the specified NFT");
            nftData[newNFTs[i].id] = newNFTs[i];
            nftRarityScores[newNFTs[i].id] = newNFTs[i].rarityScore;
            nftActiveStatus[newNFTs[i].id] = true;
            nftOwnerAddresses[newNFTs[i].id] = nftOwners[i];

            if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("A"))) {
                seriesANFTIds.push(newNFTs[i].id);
            } else if (keccak256(abi.encodePacked(series)) == keccak256(abi.encodePacked("B"))) {
                seriesBNFTIds.push(newNFTs[i].id);
            }

            emit NFTAdded(newNFTs[i].id, newNFTs[i].rarityScore, series, nftOwners[i]);
        }
    }

    function injectBIAFunds(uint256 amount) public onlyContractOwner {
        require(amount > 0, "Amount must be greater than zero");

        // Update state before external call
        totalBiaFunds = totalBiaFunds.add(amount);

        require(biaTokenContract.transferFrom(msg.sender, address(this), amount), "BIA transfer failed");

        emit FundsInjected(amount, 0);
    }

    function injectETHFunds() public payable onlyContractOwner {
        require(msg.value > 0, "Amount must be greater than zero");
        totalEthFunds = totalEthFunds.add(msg.value);
        emit FundsInjected(0, msg.value);
    }

    function randomFunction1() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp)));
    }

    function randomFunction2(uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(msg.sender, nonce)));
    }

    function randomFunction3() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, gasleft())));
    }

    function combinedRandomNumber() internal returns (uint256) {
        uint256 rand1 = randomFunction1();
        uint256 rand2 = randomFunction2(randomNonce);
        uint256 rand3 = randomFunction3();
        lastRandomHash = keccak256(abi.encodePacked(rand1, rand2, rand3));
        randomNonce = randomNonce.add(1);
        return uint256(lastRandomHash);
    }

    function calculateJackpot() internal view returns (uint256, string memory) {
        uint256 amount;
        string memory currency;

        // Scale factor to handle precise division
        uint256 scaleFactor = 1e18;

        if (totalDraws < 6 || totalDraws % 2 == 0) {
            currency = "$BIA";
            amount = ((uint256(lastRandomHash) % 16 + 5).mul(currentBiaJackpot).mul(scaleFactor)).div(100);
        } else {
            currency = "$ETH";
            amount = ((uint256(lastRandomHash) % 16 + 5).mul(currentEthJackpot).mul(scaleFactor)).div(100);
        }

        return (amount.div(scaleFactor), currency);
    }

    function initializeDraw() public onlyContractOwner {
        require(targetBlock == 0 && finalizeBlock == 0, "A draw is already in progress");

        uint256 initialRandom = combinedRandomNumber();

        // Determine the mode of the game
        gameMode = initialRandom % 2; // 0 for single winner, 1 for multiple winners
        // Determine the number of winners
        winnersCount = (initialRandom.div(2) % 10).add(1); // 1 to 10 winners
        // Determine the size of the jackpot
        jackpotPercentage = (initialRandom.div(12) % 20).add(1); // 1% to 20% of the current jackpot

        selectedSeries = (initialRandom.div(32) % 2).add(1); // 1 for Series A, 2 for Series B
        rarityMode = (initialRandom.div(64) % 3); // 0: Higher, 1: Lower, 2: In-Between
        rarityThreshold = (initialRandom.div(128) % (maximumRarity - minimumRarity + 1)).add(minimumRarity); // Random rarity threshold for comparison

        targetBlock = block.number.add(initialRandom.div(256) % 20).add(5); // Random delay of 5 to 25 blocks

        emit DrawInitialized(gameMode, winnersCount, jackpotPercentage, selectedSeries, rarityMode, rarityThreshold);
    }

    function finalizeDraw() public onlyContractOwner {
        require(targetBlock > 0 && block.number >= targetBlock, "Cannot finalize draw yet");
        require(finalizeBlock == 0, "Winner selection already in progress");

        finalizeBlock = block.number.add(combinedRandomNumber() % 20).add(5); // Random delay of 5 to 25 blocks
    }

    function selectWinners() public onlyContractOwner {
        require(finalizeBlock > 0 && block.number >= finalizeBlock, "Cannot select winners yet");

        uint256 finalRandom = combinedRandomNumber();

        uint256[] storage seriesNFTs = selectedSeries == 1 ? seriesANFTIds : seriesBNFTIds;

        uint256[] memory eligibleNFTs = new uint256[](seriesNFTs.length);
        uint256 eligibleCount = 0;

        for (uint256 i = 0; i < seriesNFTs.length; i++) {
            uint256 id = seriesNFTs[i];
            uint256 rarity = nftRarityScores[id];

            bool isEligible = false;
            if (rarityMode == 0 && rarity > rarityThreshold) { // Higher
                isEligible = true;
            } else if (rarityMode == 1 && rarity < rarityThreshold) { // Lower
                isEligible = true;
            } else if (rarityMode == 2 && rarity >= rarityThreshold.div(2) && rarity <= maximumRarity.mul(3).div(2)) { // In-Between
                isEligible = true;
            }

            if (isEligible && nftActiveStatus[id]) {
                eligibleNFTs[eligibleCount++] = id;
            }
        }

        require(eligibleCount > 0, "No eligible NFTs found");

        (uint256 jackpotAmount, string memory currency) = calculateJackpot();
        jackpotAmount = jackpotAmount.mul(jackpotPercentage).div(100); // Adjust jackpot size

        uint256[] memory winners = new uint256[](gameMode == 0 ? 1 : (eligibleCount > winnersCount ? winnersCount : eligibleCount));

        // Scale factor to handle integer division
        uint256 scaleFactor = 1e18;
        uint256 totalJackpotAmount = jackpotAmount.mul(scaleFactor);
        uint256 prizePerWinner = totalJackpotAmount.div(winners.length);

        for (uint256 i = 0; i < winners.length; i++) {
            winners[i] = eligibleNFTs[finalRandom % eligibleCount];
            finalRandom = uint256(keccak256(abi.encodePacked(finalRandom, i))); // Update finalRandom for next selection
        }

        if (keccak256(bytes(currency)) == keccak256(bytes("$BIA"))) {
            require(currentBiaJackpot >= jackpotAmount, "Insufficient BIA in jackpot");
            currentBiaJackpot = currentBiaJackpot.sub(jackpotAmount);
            totalBiaFunds = totalBiaFunds.sub(jackpotAmount);
            for (uint256 i = 0; i < winners.length; i++) {
                biaPendingWithdrawals[nftOwnerAddresses[winners[i]]] = biaPendingWithdrawals[nftOwnerAddresses[winners[i]]].add(prizePerWinner.div(scaleFactor));
            }
        } else {
            require(currentEthJackpot >= jackpotAmount, "Insufficient ETH in jackpot");
            currentEthJackpot = currentEthJackpot.sub(jackpotAmount);
            totalEthFunds = totalEthFunds.sub(jackpotAmount);
            for (uint256 i = 0; i < winners.length; i++) {
                ethPendingWithdrawals[nftOwnerAddresses[winners[i]]] = ethPendingWithdrawals[nftOwnerAddresses[winners[i]]].add(prizePerWinner.div(scaleFactor));
            }
        }

        emit DrawWinner(winners, jackpotAmount, currency);

        // Reset targetBlock and finalizeBlock for next draw
        targetBlock = 0;
        finalizeBlock = 0;
    }

    function claimFunds(uint256 nftId) public nonReentrant onlyNFTOwner(nftId) {
        require(nftActiveStatus[nftId], "NFT is not active");

        uint256 biaAmount = biaPendingWithdrawals[msg.sender];
        uint256 ethAmount = ethPendingWithdrawals[msg.sender];

        require(biaAmount > 0 || ethAmount > 0, "No funds to claim");

        // Update state before external calls
        if (biaAmount > 0) {
            biaPendingWithdrawals[msg.sender] = 0;
            require(biaTokenContract.transfer(msg.sender, biaAmount), "BIA transfer failed");
            emit FundsClaimed(msg.sender, biaAmount, "$BIA");
        }

        if (ethAmount > 0) {
            ethPendingWithdrawals[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            emit FundsClaimed(msg.sender, ethAmount, "$ETH");
        }
    }
}
