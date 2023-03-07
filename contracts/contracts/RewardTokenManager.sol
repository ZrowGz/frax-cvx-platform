// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IConvexWrapperV2.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
// import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './RewardToken.sol';
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFraxFarmERC20TransferByIndex.sol";

contract RewardTokenManager is ERC20,IConvexWrapperV2{
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

    // struct EarnedData {
    //     address token;
    //     uint256 amount;
    // }

    // mapping(address => uint256) public vaultBalance; // todo handled by the erc20 component
    address public stakingToken;
    address public curveLpToken;
    address public poolRegistry;

    bool public isInit;
    address public owner;

    address[] public rewardTokens;

    // function isVault(address _vault) public view returns(bool){
    //     IPoolRegistry(poolRegistry).isVault(_vault);
    // }

    function initialize(address _stakingToken, address[] calldata _rewardTokens, string memory _name, string memory _symbol) public {
        require(!isInit,"already init");
        owner = msg.sender;

        rewardTokens = _rewardTokens;

        __ERC20_init(_name, _symbol);
        stakingToken = _stakingToken;

        isInit = true;
    }

    function balanceOf(address account) public view override(ERC20, IConvexWrapperV2) returns (uint256) {
        return balanceOf(account);
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
        /// draws in the accrued yields of CRV & CVX (and any extra rewards)
        /// returns the tokens and amounts

        //get address & amounts of rewards
        EarnedData[] memory earnedRwds = IConvexWrapperV2(stakingToken).earned(address(this));
        address[] memory rwdTkns; 
        uint256[] memory tknAmts;

        //claim rewards from wrapper
        IConvexWrapperV2(stakingToken).getReward(address(this));

        //send all rewards to the frax farm
        for(uint256 i; i < rwdTkns.length; i++){
            /// TODO if reward token is on the original list, send to the farm
            /// if not, add to balance of this contract for later payout...
            /// TODO: Farm cannot have new tokens added as reward tokens!
            //add the reward token & amount to the arrays
            rwdTkns[i] = earnedRwds[i].token;
            tknAmts[i] = earnedRwds[i].amount;
            //send all rewards to the frax farm
            IERC20(stakingToken).safeTransfer(msg.sender, IERC20(stakingToken).balanceOf(address(this)));
        }
    }

    function writeRewardRate(address rwdTkn, uint256 rwdAmt) external {
        //calculate reward rate (tknAamt / 1 week in seconds)
        uint256 rwdRate = rwdAmt / 604800;

        //write the reward rate to the farm
        /// TODO: Farm cannot have new tokens added as reward tokens!
        /// This means that if there are more tokens in the rwdTkns than initially set on the farm, 
        //    all attempts to distribute would revert & no payouts would happen... 
        /**
            So, we could potentially just make those claimable to the vault directly?
            - or have that be paid based on combined_weight values from the farm &
                have the vault claim those during the pre transfer hook? Though then we would need a whole
                system to track user balances over time...
            - maybe it'd work to claim extra rewards to here on vault interactions, then have the vault
                claim those on balance changing calls?
        */
        IFraxFarmERC20(msg.sender).setRewardVars(rwdTkn, rwdRate, address(0), address(0));
    }

    /// Overrides to make warning go away
    function collateralVault() external view override returns(address vault) {}
    function convexPoolId() external view returns(uint256 _poolId) {}
    function curveToken() external view returns(address) {}
    function convexToken() external view returns(address) {}
    // function balanceOf(address _account) external view returns(uint256) {}
    function totalBalanceOf(address _account) external view returns(uint256) {}
    function deposit(uint256 _amount, address _to) external {}
    function stake(uint256 _amount, address _to) external {}
    function withdraw(uint256 _amount) external {}
    function withdrawAndUnwrap(uint256 _amount) external {}
    function getReward(address _account) external {}
    function getReward(address _account, address _forwardTo) external {}
    function rewardLength() external view returns(uint256) {}
    function rewards(uint256 _index) external view returns(RewardType memory rewardInfo) {}
    function earned(address _account) external returns(EarnedData[] memory claimable) {}
    function earnedView(address _account) external view returns(EarnedData[] memory claimable) {}
    function setVault(address _vault) external {}
    function user_checkpoint(address[2] calldata _accounts) external returns(bool) {}
}