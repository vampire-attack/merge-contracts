// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMerge} from "./interfaces/IMerge.sol";

/**
 * @title The contract handles multiple merges
 */
contract Merge is IMerge, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public mergeAsset; // VAMP token address
    mapping(address => Merge) public merges; // targetAsset => merge params
    mapping(address => mapping(address => uint256)) public vested; // targetAsset => user => vested balances
    mapping(address => mapping(address => uint256)) public released; // targetAsset => user => released balances

    constructor(address _mergeAsset) {
        mergeAsset = IERC20Metadata(_mergeAsset);
    }

    modifier onlyValidTargetAsset(address targetAsset) {
        if (merges[targetAsset].params.targetAsset == address(0)) {
            revert InvalidTargetAsset(targetAsset);
        }
        _;
    }

    function depositMergeTokens(MergeParams calldata params, uint256 allocatedAmount) external onlyOwner {
        if (params.targetAsset == address(0)) {
            revert ZeroAddress();
        }

        if (merges[params.targetAsset].allocatedAmount > 0) {
            revert MergeAlreadyConfigured(params.targetAsset);
        }

        if (allocatedAmount == 0) {
            revert ZeroAmount();
        }

        if (params.swapRate == 0) {
            revert ZeroRate();
        }

        if (params.depositPeriod == 0) {
            revert ZeroDepositPeriod();
        }

        if (params.mergeCliff == 0) {
            revert ZeroCliff();
        }

        if (params.mergePeriod == 0) {
            revert ZeroMergePeriod();
        }

        // Transfer VAMP(merge) tokens
        mergeAsset.safeTransferFrom(msg.sender, address(this), allocatedAmount); // msg.sender will be owner

        // Save merge params
        merges[params.targetAsset] = Merge(params, allocatedAmount, allocatedAmount, 0, 0, false, false, false);
    }

    function withdrawTargetAssets(
        address targetAsset,
        address destination
    ) external onlyOwner onlyValidTargetAsset(targetAsset) nonReentrant {
        if (destination == address(0)) {
            revert ZeroAddress();
        }

        Merge storage merge = merges[targetAsset];

        if (merge.targetWithdrawn) {
            revert AlreadyWithdrawn();
        }

        if (block.timestamp <= merge.params.startTimestamp + merge.params.depositPeriod) {
            revert DepositInProgress();
        }

        merge.targetWithdrawn = true;
        IERC20Metadata(targetAsset).safeTransfer(destination, merge.depositedAmount);
    }

    function postDepositClawBack(
        address targetAsset,
        address destination
    ) external onlyOwner onlyValidTargetAsset(targetAsset) nonReentrant {
        if (destination == address(0)) {
            revert ZeroAddress();
        }

        Merge storage merge = merges[targetAsset];

        // Withdraw only after deposit period
        if (block.timestamp <= merge.params.startTimestamp + merge.params.depositPeriod) {
            revert DepositInProgress();
        }

        if (merge.withdrawnAfterDeposit) {
            revert AlreadyWithdrawn();
        }

        merge.withdrawnAfterDeposit = true;
        // Withdraw available amounts
        IERC20Metadata(targetAsset).safeTransfer(destination, merge.availableAmount);
    }

    function postMergeClawback(
        address targetAsset,
        address destination
    ) external onlyOwner onlyValidTargetAsset(targetAsset) nonReentrant {
        if (destination == address(0)) {
            revert ZeroAddress();
        }

        Merge storage merge = merges[targetAsset];

        // Withdraw only after deposit period
        if (block.timestamp <= merge.params.startTimestamp + merge.params.mergePeriod) {
            revert MergeInProgress();
        }

        if (merge.withdrawnAfterMerge) {
            revert AlreadyWithdrawn();
        }

        merge.withdrawnAfterMerge = true;
        // Withdraw remaining amounts
        IERC20Metadata(targetAsset).safeTransfer(
            destination,
            merge.allocatedAmount - merge.availableAmount - merge.claimedAmount
        );
    }

    function deposit(address targetAsset, uint256 targetAmount) external onlyValidTargetAsset(targetAsset) {
        Merge storage merge = merges[targetAsset];

        if (targetAmount == 0) {
            revert ZeroAmount();
        }

        // Deposit only during deposit period
        if (block.timestamp < merge.params.startTimestamp) {
            revert DepositNotStarted();
        }
        if (block.timestamp > merge.params.startTimestamp + merge.params.depositPeriod) {
            revert DepositEnded();
        }

        // Calculate merge amount
        uint8 mergeDecimals = mergeAsset.decimals();
        uint8 targetDecimals = IERC20Metadata(targetAsset).decimals();
        uint256 mergeAmount = (targetAmount * merge.params.swapRate * 10 ** mergeDecimals) / 10 ** targetDecimals;

        if (merge.availableAmount < mergeAmount) {
            revert NotEnoughMergeAssetAvailable();
        }

        // Transfer target asset
        merge.availableAmount = merge.availableAmount - mergeAmount;
        merge.depositedAmount = merge.depositedAmount + targetAmount;
        IERC20Metadata(targetAsset).safeTransferFrom(msg.sender, address(this), targetAmount);

        // targetAsset => user => vested balances
        vested[targetAsset][msg.sender] += mergeAmount;
    }

    function withdraw(
        address targetAsset,
        uint256 mergeAmount
    ) external onlyValidTargetAsset(targetAsset) nonReentrant {
        Merge storage merge = merges[targetAsset];

        if (mergeAmount == 0) {
            revert ZeroAmount();
        }

        // Merge only after merge cliff and during merge period
        uint256 mergeStartTimestamp = merge.params.startTimestamp + merge.params.mergeCliff;
        if (block.timestamp < mergeStartTimestamp) {
            revert MergeNotStarted();
        }
        if (block.timestamp > merge.params.startTimestamp + merge.params.mergePeriod) {
            revert MergeEnded();
        }

        // Calculate current vested amount
        uint256 currentVested = _vestedAmount(
            vested[targetAsset][msg.sender],
            block.timestamp,
            mergeStartTimestamp,
            merge.params.mergePeriod
        );

        uint256 unreleased = currentVested - released[targetAsset][msg.sender];
        if (unreleased < mergeAmount) {
            revert NotEnoughMergeAssetAvailable();
        }

        mergeAsset.safeTransfer(msg.sender, mergeAmount);
        released[targetAsset][msg.sender] += mergeAmount;
    }

    function _vestedAmount(
        uint256 totalAmount,
        uint256 currentTime,
        uint256 start,
        uint256 duration
    ) internal pure returns (uint256) {
        if (currentTime < start) {
            return 0;
        } else if (currentTime >= start + duration) {
            return totalAmount;
        } else {
            return (totalAmount * (currentTime - start)) / duration;
        }
    }
}
