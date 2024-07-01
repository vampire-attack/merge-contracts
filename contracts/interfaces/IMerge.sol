// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IMerge {
    struct MergeParams {
        address targetAsset; // The token to be merged
        uint256 swapRate; // ratio of merge:target in qty of tokens. Using 6 decimals
        uint256 depositPeriod; // E.g: 60 days After which targetAsset can no longer be deposited.
        uint256 mergeCliff; // // 3 months, cannot withdraw until after
        uint256 mergePeriod; // 12 months, linear vesting
        uint256 startTimestamp; // Merge start timestamp
    }

    struct Merge {
        MergeParams params;
        uint256 allocatedAmount; // The total number of VAMP tokens allocated for this merge
        uint256 availableAmount; // Remaining VAMP token amount
        uint256 claimedAmount; // Claimed VAMP token amount
        uint256 depositedAmount; // The total number of target assets deposited during the deposit period
        bool targetWithdrawn; // If targetAsset already withdrawn after deposit period
        bool withdrawnAfterDeposit; // If targetAsset already withdrawn after deposit period
        bool withdrawnAfterMerge; // If targetAsset already withdrawn after deposit period
    }

    // Errors for merge param creation
    error ZeroAddress();
    error MergeAlreadyConfigured(address targetAsset);
    error ZeroAmount();
    error ZeroRate();
    error ZeroDepositPeriod();
    error ZeroCliff();
    error ZeroMergePeriod();

    // Errors for withdraw target assets
    error InvalidTargetAsset(address targetAsset);
    error AlreadyWithdrawn();
    error DepositInProgress();
    error MergeInProgress();

    // Errors for deposit target asset
    error DepositNotStarted();
    error DepositEnded();
    error NotEnoughMergeAssetAvailable();

    // Errors for withdraw merge asset
    error MergeNotStarted();
    error MergeEnded();
}
