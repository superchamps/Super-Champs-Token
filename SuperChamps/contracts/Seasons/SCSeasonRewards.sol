// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCSeasonRewards.sol";
import "../../interfaces/ISCAccessPass.sol";
import "../../interfaces/ISCMetagamePool.sol";

/// @title Manager for the seasonal player rewards program.
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @dev Season rewards pulled from a treasury contract that must have a token allowance set for this contract.
/// @notice Allows System Admins to set up and report scores for Seasons.
contract SCSeasonRewards is ISCSeasonRewards, SCPermissionedAccess{
    ///@notice The address of the rewards token. (The CHAMP token)
    IERC20 immutable token;

    ///@notice The traeasury from which Seasons pull their reward tokens.
    address treasury;

    /// @notice The access pass SBT
    ISCAccessPass public access_pass;

    /// @notice The metagame staking pool
    ISCMetagamePool public staking_pool;

    ///@notice A list of seasons. A season's ID is its index in the list.
    ISCSeasonRewards.Season[] public seasons;

    ///@notice A mapping of scores reported for each user by address for each season by ID.
    mapping(uint256 => mapping(address => uint256)) public season_rewards;

    ///@notice A mapping of quantity of tokens claimed for each user by address for each season by ID.
    mapping(uint256 => mapping(address => uint256)) public claimed_rewards;

    ///@notice A set of signatures which have already been used.
    ///@dev Member signatures are no longer valid.
    mapping(bytes => bool) private consumed_signatures;

    ///@notice A mapping of the last used signature timestamp, by user address.
    ///@dev This acts as the nonce for the signatures. Signatures with timestamps earlier than the value set are not valid.
    mapping(address => uint256) public player_last_signature_timestamp;

    event TreasurySet(address treasury);
    event StakedRewards(address staker, uint256 rewards);

    ///@param permissions_ The address of the protocol permissions registry. Must conform to IPermissionsManager.
    ///@param token_ The address of the reward token. (The CHAMP token)
    ///@param treasury_ The address of the account/contract that the Seasons reward system pulls reward tokens from.
    /// @param access_pass_ Address of the protocol access pass SBT
    constructor(
        address permissions_, 
        address token_, 
        address treasury_,
        address access_pass_,
        address staking_pool_) 
        SCPermissionedAccess(permissions_)
    {
        token = IERC20(token_);
        treasury = treasury_;
        access_pass = ISCAccessPass(access_pass_);
        staking_pool = ISCMetagamePool(staking_pool_);
    }

    ///@notice Updates the address of the account/contract that the Seasons reward system pulls reward tokens from.
    ///@dev Only callable by Global Admins.
    ///@param treasury_ The address of the new treasury.
    function setTreasury(address treasury_) external isGlobalAdmin {
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    ///@notice Initializes a new Season of the rewards program.
    ///@dev Only callable by Systems Admins. It is permissable to create Seasons with overlapping times.
    ///@param start_time_ The start time of the new season.
    ///@return season_ ISCSeasonRewards.Season The Season struct that was initialized.
    function startSeason(
        uint256 start_time_
    ) external isSystemsAdmin returns(ISCSeasonRewards.Season memory season_)
    {
        require(start_time_ > 0, "CANNOT START AT 0");
        season_.start_time = start_time_;
        season_.end_time = type(uint256).max;
        season_.id = uint32(seasons.length);
        seasons.push(season_);
    }

    ///@notice Queries the active status of a season.
    ///@param season_ The season struct to query from.
    ///@param timestamp_ The timestamp to query the active status at.
    ///@return _active bool The active status of the provided season
    function isSeasonActive(
        Season memory season_,
        uint256 timestamp_
    ) public pure returns(bool _active) 
    {
        _active = season_.end_time >= timestamp_ && timestamp_ > season_.start_time;
    }

    ///@notice Queries the finalized status of a season.
    ///@dev A season is finalized if its claim time is set.
    ///@param season_ The season struct to query from.
    ///@return _finalized bool The finalized status of the provided season.
    function isSeasonFinalized(
        Season memory season_
    ) public pure returns(bool _finalized) 
    {
        _finalized = season_.claim_end_time > 0;
    }

    ///@notice Queries if a season has ended.
    ///@param season_ The season struct to query from.
    ///@param timestamp_ The timestamp to query the ended status at.
    ///@return _ended bool True if the season has ended at the provided timestamp
    function isSeasonEnded(
        Season memory season_,
        uint256 timestamp_
    ) public pure returns(bool _ended) 
    {
        _ended = season_.end_time < timestamp_;
    }

    ///@notice Queries if a season has been finalized and can have rewards claimed from it.
    ///@param season_ The season struct to query from.
    ///@param timestamp_ The timestamp to query the ended status at.
    ///@return _active bool True if the season has ended at the provided timestamp
    function isSeasonClaimingActive(
        Season memory season_,
        uint256 timestamp_
    ) public pure returns(bool _active) 
    {
        _active = isSeasonFinalized(season_) && season_.claim_end_time >= timestamp_;
    }

    ///@notice Queries if a season has been finalized and the claim period has already elapsed.
    ///@param season_ The season struct to query from.
    ///@param timestamp_ The timestamp to query the ended status at.
    ///@return _ended bool True if the season's rewards claim period has elapsed.
    function isSeasonClaimingEnded(
        Season memory season_,
        uint256 timestamp_
    ) public pure returns(bool _ended) 
    {
        _ended = isSeasonFinalized(season_) && season_.claim_end_time < timestamp_;
    }

    ///@notice Ends a season.
    ///@dev Callable only by Systems Admins.
    ///@param id_ The id of the season to end.
    function endSeason(
        uint256 id_
    ) external isSystemsAdmin
    {
        Season storage _season = seasons[id_];
        require(_season.start_time > 0, "SEASON NOT FOUND");
        require(isSeasonActive(_season, block.timestamp), "SEASON NOT ACTIVE");
        _season.end_time = block.timestamp;
    }

    ///@notice Revokes unclaimed reward tokens into the treasury.
    ///@dev Callable only by Systems Admins and only after the season's claim period has elapsed.
    ///@param id_ The id of the season to end.
    function revokeUnclaimedReward(
        uint256 id_
    ) external isSystemsAdmin
    {
        Season storage _season = seasons[id_];
        uint256 _remaining_reward_amount = _season.remaining_reward_amount;
        require(_season.start_time > 0, "SEASON NOT FOUND");
        require(isSeasonClaimingEnded(_season, block.timestamp), "SEASON_CLAIM_NOT_ENDED");
        require(_remaining_reward_amount > 0, "ZERO_REMAINING_AMOUNT");

        bool transfer_success = token.transfer(treasury, _remaining_reward_amount);
        require(transfer_success, "FAILED TRANSFER");
        _season.remaining_reward_amount -= uint128(_remaining_reward_amount);
    }

    ///@notice Finalizes a season, setting its rewards quantity and claim period.
    ///@dev Callable only by Systems Admins and only after the season has been ended by calling the endSeason(...) function.
    ///@param id_ The id of the season to finalize.
    ///@param reward_amount_ The quantity of reward tokens to split between season participants. This quantity must be able to be transferred from the treasury.
    ///@param claim_duration_ The duration of the claim period.
    function finalize(
        uint256 id_,
        uint256 reward_amount_,
        uint256 claim_duration_
    ) external isSystemsAdmin
    {
        Season storage _season = seasons[id_];
        require(_season.start_time > 0, "SEASON NOT FOUND");
        require(isSeasonEnded(_season, block.timestamp), "SEASON_NOT_ENDED");
        require(!isSeasonFinalized(_season), "SEASON_FINALIZED");
        require(reward_amount_ == _season.reward_amount, "REWARD AMOUNT DOESN'T MATCH");
        require(claim_duration_ >= 7 days && claim_duration_ < 1000 days, "CLAIM DURATION OUT OF BOUNDS");

        bool transfer_success = token.transferFrom(treasury, address(this), reward_amount_);
        require(transfer_success, "FAILED TRANSFER");
        
        _season.remaining_reward_amount = reward_amount_;
        _season.claim_end_time = block.timestamp + claim_duration_;
    }

    ///@notice Reports an list of players' scores for the specified season.
    ///@dev Callable only by Systems Admins.
    ///@param season_id_ The ID of the season.
    ///@param players_ The list of player addresses.
    ///@param rewards_ The list of player's total current rewards.
    function reportRewards(
        uint256 season_id_,
        address[] calldata players_,
        uint256[] calldata rewards_
    ) external isSystemsAdmin
    {
        require(players_.length == rewards_.length, "ARRAYS  MISMATCH");

        Season storage _season = seasons[season_id_];
        require(_season.start_time > 0, "SEASON NOT FOUND");
        require(!isSeasonFinalized(_season), "SEASON FINALIZED");
        
        uint256 _increase = 0;
        uint256 _decrease = 0;

        for (uint256 i = 0; i < players_.length; i++) {
            _increase += rewards_[i];
            _decrease += season_rewards[season_id_][players_[i]];
            season_rewards[season_id_][players_[i]] = rewards_[i];
        }

        _season.reward_amount += _increase;
        _season.reward_amount -= _decrease;
    }

    ///@notice Claim tokens rewarded to msg.sender in the specified season. Must have a verified Access Pass.
    ///@dev Callable only on seasons which have been finalized and whose claim duration has not elapsed.
    ///@param season_id_ The season to claim reward tokens from.
    function _preClaim(
        uint256 season_id_
    ) internal 
        returns (uint256)
    {
        require(claimed_rewards[season_id_][msg.sender] == 0, "REWARD CLAIMED");
        //require(access_pass.isVerified(msg.sender), "MUST HAVE VERIFIED AN ACCESS PASS");

        Season storage _season = seasons[season_id_];
        require(isSeasonClaimingActive(_season, block.timestamp), "SEASON_CLAIM_ENDED");

        uint256 _reward = season_rewards[season_id_][msg.sender];
        require(_reward > 0, "MUST HAVE A NON ZERO REWARD");

        _season.remaining_reward_amount -= _reward;
        claimed_rewards[season_id_][msg.sender] = _reward;

        return _reward;
    }

    ///@notice Claim tokens to msg.sender
    ///@dev Callable only on seasons which have been finalized and whose claim duration has not elapsed.
    ///@param season_id_ The season to claim reward tokens from.
    function claimReward(
        uint256 season_id_
    ) external
    {
        uint256 _reward = _preClaim(season_id_);
        bool transfer_success = token.transfer(msg.sender, _reward);
        require(transfer_success, "FAILED TRANSFER");
    }

    ///@notice Stake tokens claimed.
    ///@dev Callable only on seasons which have been finalized and whose claim duration has not elapsed.
    ///@param season_id_ The season to claim reward tokens from.
    function stakeReward(
        uint256 season_id_
    ) external
    {
        uint256 _reward = _preClaim(season_id_);
        token.approve(address(staking_pool), _reward);
        staking_pool.stakeFor(msg.sender, _reward);
        emit StakedRewards(msg.sender, _reward);
    }

    ///@notice get reward tokens claimable by a player in the specified season.
    ///@param season_id_ The season to get reward tokens from.
    function getClaimableReward(
        uint256 season_id_
    ) public view returns(uint256 _reward) 
    {
        _reward = season_rewards[season_id_][msg.sender] - claimed_rewards[season_id_][msg.sender];
        Season storage _season = seasons[season_id_];
        if( !isSeasonClaimingActive(_season, block.timestamp) ) //|| 
            //!access_pass.isVerified(msg.sender)) 
        {
            _reward = 0;
        }
    }

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }
}