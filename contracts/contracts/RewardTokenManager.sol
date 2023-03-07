// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IConvexWrapperV2.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
// import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './RewardToken.sol';
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RewardTokenManager is ERC20{
    using SafeERC20 for IERC20;
    ///
    /**
    *   This contract will pass through the vault deposits to convex token wrappers. 
    *   With this being the only address that is earning cvx & crv rewards, the weekly familial gauge sync
    *     - will pull in all yields for all deposited assets (other than FXS) 
    *       and distribute them to the farm for user claiming
    *     - write the reward rate to the farm for the given week
    *   The farm will pay out rewards directly to the vaults, where fees can be processed as needed. 
    *   This will eliminate the need for rewards claiming logic to be ran before & after stake transfers.
    *     - As all rewards for the wrapper will be owned by this contract, the checkpoint function within 
    *        the wrapper can be bypassed, saving gas. 
    *   THIS MIGHT ALSO NEED TO MINT AN ERC20 TO GIVE BACK TO THE VAULT TO STAKE TO FARM
    *     - this would effectively allow separation of underlying redemption from yields
    *     - the token to deposit to the farm would be THIS ERC20
    *     - this contract would get all of the rewards & send to farm, yet vault can still transfer claim on LP
    *   NOTE 
    *   This is effectively an erc20
    */

    // mapping(address => uint256) public vaultBalance; // todo handled by the erc20 component
    address public stakingToken;
    address public curveLpToken;
    address public poolRegistry;

    bool public isInit;
    address public owner;

    // function isVault(address _vault) public view returns(bool){
    //     IPoolRegistry(poolRegistry).isVault(_vault);
    // }

    function initialize(address _stakingToken, string memory _name, string memory _symbol) public {
        require(!isInit,"already init");
        owner = msg.sender;

        __ERC20_init(_name, _symbol);
        stakingToken = _stakingToken;

        isInit = true;
    }

    function depositConvexToken(uint256 _amount) external {
        /// TODO To prevent circumventing the vault rewards processing, check that caller is a vault

        //pull tokens from user
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
    
        // mint this wrapper & send to the vault
        _mint(msg.sender, _amount);
    }

    function depositCurveLp(uint256 _amount) external {
        /// TODO To prevent circumventing the vault rewards processing, check that caller is a vault

        //pull tokens from user
        IERC20(curveLpToken).safeTransferFrom(msg.sender, address(this), _amount);

        //deposit into wrapper
        IConvexWrapperV2(stakingToken).deposit(_amount, address(this));
    
        // mint this wrapper & send to the vault
        _mint(msg.sender, _amount);
    }

    function withdrawConvexToken(uint256 _amount) external {
        /// TODO To prevent circumventing the vault rewards processing, check that caller is a vault

        //burn this wrapper
        _burn(msg.sender, _amount);

        //send tokens to user
        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
    }

    function withdrawCurveLp(uint256 _amount) external {
        /// TODO To prevent circumventing the vault rewards processing, check that caller is a vault

        //burn this wrapper
        _burn(msg.sender, _amount);

        //withdraw from wrapper
        IConvexWrapperV2(stakingToken).withdraw(_amount);

        //send tokens to user
        IERC20(curveLpToken).safeTransfer(msg.sender, _amount);
    }

    /// Reward Token Manager functions

    // will be called by the Familial Gauge ONLY once per week
    function checkpointEpoch() external {
        /// require(msg.sender == familialGauge, "!FamilalGauge")
        /// calls the claimEpochYields & updateRewardRates functions
        /// This will all be triggered by the familial gauge
        /// and will write & deposit to the farm
        /// This will happen on the first iteration through the farm updates
        /// and it will only happen once per week
    }
    
    function claimEpochYields() internal returns(address[] memory rwdTkns, uint256[] memory tknAmts){
        /// draws in the accrued yields of CRV & CVX (and any extra rewards)
        /// returns the tokens and amounts
        //get all rewards from the wrapper
        IConvexWrapperV2(stakingToken).getReward(address(this));

        //get all rewards from the wrapper
        IConvexWrapperV2(stakingToken).getReward(address(this), address(this));

        //send all rewards to the frax famr
        IERC20(stakingToken).safeTransfer(msg.sender, IERC20(stakingToken).balanceOf(address(this)));
    }

    function updateRewardRates() internal {
        /// write the reward token rates to the farm for the coming week
        /// distribute the reward tokens to the farm
    }
}