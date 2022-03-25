// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IProxyVault.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/IFraxFarmERC20.sol";
import "./interfaces/IRewards.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract StakingProxyERC20 is IProxyVault{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant vefxsProxy = address(0x59CFCD384746ec3035299D90782Be065e466800B);

    address public owner;
    address public feeRegistry; //todo: can convert to const
    address public stakingAddress;
    address public stakingToken;
    address public rewards;

    uint256 public constant FEE_DENOMINATOR = 10000;


    //initialize vault
    function initialize(address _owner, address _feeRegistry, address _stakingAddress, address _stakingToken, address _rewardsAddress) external{
        require(owner == address(0),"already init");

        //set variables
        owner = _owner;
        feeRegistry = _feeRegistry;
        stakingAddress = _stakingAddress;
        stakingToken = _stakingToken;
        rewards = _rewardsAddress;

        //set proxy address on staking contract
        IFraxFarmERC20(stakingAddress).stakerSetVeFXSProxy(vefxsProxy);

        //set infinite approval
        IERC20(stakingToken).approve(stakingAddress, type(uint256).max);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!auth");
        _;
    }

    //create a new locked state of _secs timelength
    function stakeLocked(uint256 _liquidity, uint256 _secs) external onlyOwner{
        if(_liquidity > 0){
            //pull tokens from user
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _liquidity);

            //stake
            IFraxFarmERC20(stakingAddress).stakeLocked(_liquidity, _secs);
        }
        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            IRewards(rewards).deposit(owner,_liquidity);
        }
    }

    //add to a current lock
    function lockAdditional(bytes32 _kek_id, uint256 _addl_liq) external onlyOwner{
        if(_addl_liq > 0){
            //pull tokens from user
            IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _addl_liq);

            //add stake
            IFraxFarmERC20(stakingAddress).lockAdditional(_kek_id, _addl_liq);
        }
        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            IRewards(rewards).deposit(owner,_addl_liq);
        }
    }

    //withdraw a staked position
    function withdrawLocked(bytes32 _kek_id) external onlyOwner{
        //take note of amount liquidity staked
        uint256 userLiq = IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));

        //withdraw directly to owner(msg.sender)
        IFraxFarmERC20(stakingAddress).withdrawLocked(_kek_id, msg.sender);

        //if rewards are active, checkpoint
        if(IRewards(rewards).active()){
            //get difference of liquidity after withdrawn
            userLiq -= IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));
            IRewards(rewards).withdraw(owner,userLiq);
        }
    }

    //helper function to combine earned tokens on staking contract and any tokens that are on this vault
    function earned() external view returns (address[] memory token_addresses, uint256[] memory total_earned) {
        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();
        uint256[] memory stakedearned = IFraxFarmERC20(stakingAddress).earned(address(this));
        
        token_addresses = new address[](rewardTokens.length + IRewards(rewards).rewardTokenLength());
        total_earned = new uint256[](rewardTokens.length + IRewards(rewards).rewardTokenLength());
        //add any tokens that happen to be already claimed but sitting on the vault
        //(ex. withdraw claiming rewards)
        for(uint256 i = 0; i < rewardTokens.length; i++){
            token_addresses[i] = rewardTokens[i];
            total_earned[i] = stakedearned[i] + IERC20(rewardTokens[i]).balanceOf(address(this));
        }

        IRewards.EarnedData[] memory extraRewards = IRewards(rewards).claimableRewards(address(this));
        for(uint256 i = 0; i < extraRewards.length; i++){
            token_addresses[i+rewardTokens.length] = extraRewards[i].token;
            total_earned[i+rewardTokens.length] = extraRewards[i].amount;
        }
    }

    //helper function to get weighted reward rates (rate per weight unit)
    function weightedRewardRates() public view returns (uint256[] memory weightedRates) {
        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();
        //get total weight of all stakers
        uint256 totalWeight = IFraxFarmERC20(stakingAddress).totalCombinedWeight();

        //calc weighted reward rates
        weightedRates = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++){ 
            weightedRates[i] = IFraxFarmERC20(stakingAddress).rewardRates(i) * 1e18 / totalWeight;
        }
    }

    //helper function to get boosted reward rate of user.
    //returns amount user receives per second based on weight/liq ratio
    //to get %return, multiply this value by the ratio of (price of reward / price of lp token)
    function userBoostedRewardRates() external view returns (uint256[] memory boostedRates) {
        //get list of reward tokens
        uint256[] memory wrr = weightedRewardRates();

        //get user liquidity and weight
        uint256 userWeight = IFraxFarmERC20(stakingAddress).combinedWeightOf(address(this));

        //calc boosted rates
        boostedRates = new uint256[](wrr.length);
        for (uint256 i = 0; i < wrr.length; i++){ 
            boostedRates[i] = wrr[i] * userWeight / 1e18;
        }
    }

    /*
    claim flow:
        claim rewards directly to the vault
        calculate fees to send to fee deposit
        send fxs to booster for fees
        get reward list of tokens that were received
        send all remaining tokens to owner

    A slightly less gas intensive approach could be to send rewards directly to booster and have it sort everything out.
    However that makes the logic a bit more complex as well as runs a few future proofing risks
    */
    function getReward() external onlyOwner{

        //claim
        IFraxFarmERC20(stakingAddress).getReward(address(this));

        //process fxs fees
        _processFxs();

        //get list of reward tokens
        address[] memory rewardTokens = IFraxFarmERC20(stakingAddress).getAllRewardTokens();

        //transfer
        _transferTokens(rewardTokens);

        //get extra rewards
        if(IRewards(rewards).active()){
            //check if there is a balance because the reward contract could have be activated later
            uint256 bal = IRewards(rewards).balanceOf(address(this));
            if(bal == 0){
                //bal == 0 and liq > 0 can only happen if rewards were turned on after staking
                uint256 userLiq = IFraxFarmERC20(stakingAddress).lockedLiquidityOf(address(this));
                IRewards(rewards).deposit(owner,userLiq);
            }
            IRewards(rewards).getReward(owner);
        }
    }

    //auxiliary function to supply token list(same a bit of gas + dont have to claim everything)
    //_claim bool is for the off chance that rewardCollectionPause is true so getReward() fails but
    //there are tokens on this vault for cases such as withdraw() also calling claim.
    //can also be used to rescue tokens on the vault
    function getReward(bool _claim, address[] calldata _rewardTokenList) external onlyOwner{

        //claim
        if(_claim){
            IFraxFarmERC20(stakingAddress).getReward(address(this));
        }

        //process fxs fees
        _processFxs();

        //transfer
        _transferTokens(_rewardTokenList);

        //todo: extra rewards
    }

    //apply fees to fxs and send remaining to owner
    function _processFxs() internal{

        //get fee rate from booster
        uint256 totalFees = IFeeRegistry(feeRegistry).totalFees();

        //send fxs fees to fee deposit
        uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
        uint256 feesToSend = fxsBalance * totalFees / FEE_DENOMINATOR;
        IERC20(fxs).transfer(IFeeRegistry(feeRegistry).feeDeposit(), feesToSend);

        //transfer remaining fxs to owner
        IERC20(fxs).transfer(msg.sender, IERC20(fxs).balanceOf(address(this)));
    }

    //transfer other reward tokens besides fxs(which needs to have fees applied)
    function _transferTokens(address[] memory _tokens) internal{
        //transfer all tokens
        for(uint256 i = 0; i < _tokens.length; i++){
            if(_tokens[i] != fxs){
                IERC20(_tokens[i]).transfer(msg.sender, IERC20(_tokens[i]).balanceOf(address(this)));
            }
        }
    }
}
