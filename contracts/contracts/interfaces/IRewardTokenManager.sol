// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IRewardTokenManager {
    ///
    function initialize(address _owner, address _stakingAddress, address _stakingToken, address _rewardsAddress) external;
    function depositConvexToken(uint256 _amount) external;
    function depositCurveLp(uint256 _amount) external;
}