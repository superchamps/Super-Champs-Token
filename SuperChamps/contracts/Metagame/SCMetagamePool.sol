// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCMetagamePool.sol";

/// @title Metagame staking pool.
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Staking pool for Super Champ tokens.
/// @dev This pool does not issue on-chain rewards. Rewards are tabulated off-chain.
contract SCMetagamePool is SCPermissionedAccess, ISCMetagamePool {
    IERC20 public immutable token;

    mapping(address => mapping(uint256 => uint256)) _user_to_checkpoint_to_balance;
    mapping(address => uint256[]) _user_checkpoints;

    mapping(address => mapping(address => uint256)) _user_to_approved_spend;

    /// @param permissions_ Address of the protocol permissions registry. Must conform to IPermissionsManager
    constructor(address permissions_, address token_) SCPermissionedAccess(permissions_) {
        token = IERC20(token_);
    }

    /// @notice Stake tokens directly
    /// @param amount_ Quantity of tokens to stake
    function stake(uint256 amount_) external {
        bool success = token.transferFrom(msg.sender, address(this), amount_);
        if(!success) {
            revert UnableToTransferTokens(msg.sender, amount_);
        }
        _stake(msg.sender, amount_);
    }

    /// @notice Stake tokens for another address
    /// @param staker_ The address to stake tokens for
    /// @param amount_ Quantity of tokens to stake
    /// @dev Tokens are transferred from msg.sender and credited to staker_
    function stakeFor(address staker_, uint256 amount_) external {
        bool success = token.transferFrom(msg.sender, address(this), amount_);
        if(!success) {
            revert UnableToTransferTokens(msg.sender, amount_);
        }
        _stake(staker_, amount_);
    }

    /// @notice Approve an address to spend staked tokens
    /// @param spender_ The address to approve
    /// @param amount_ Quantity of tokens to approve spending
    /// @dev This mirrors approve(...) defined in ERC20 standard
    function approve(address spender_, uint256 amount_) external {
        _user_to_approved_spend[msg.sender][spender_] += amount_;
    }

    /// @notice Spend tokens from a stakers staked tokens
    /// @param amount_ Quantity of tokens to unstake/spend
    /// @param staker_ The address of the staker
    /// @param receiver_ The address of the reciever of the spent tokens
    /// @dev This does NOT trigger an Unstake event, allowing stakers to spend tokens without penalty
    /// @dev This is expected to be called from the spending contract, which must be first permissioned through a direct call to approve(...)
    function spend(uint256 amount_, address staker_, address receiver_) external {
        if(staker_ != msg.sender) {
            _user_to_approved_spend[staker_][msg.sender] -= amount_;
        }

        uint256 _balance = _unstake(amount_, staker_, receiver_);
        emit SpendFromStake(staker_, amount_, _balance);
    }

    /// @notice Unstake tokens and transfer to staker
    /// @param amount_ Quantity of tokens to unstake
    /// @dev This triggers an Unstake event which can cause penalties in the metagame
    function unstake(uint256 amount_) external {
        uint256 _balance = _unstake(amount_, msg.sender, msg.sender);
        emit Unstake(msg.sender, amount_, _balance);
    }

    /// @notice Returns the list of all of the users staking checkpoint timestamps
    /// @param staker_ Address of the staker
    function checkpoint_timestamps(address staker_) public view returns (uint256[] memory) {
        return _user_checkpoints[staker_];
    }

    /// @notice Returns the list of all of the user's checkpoint balances from a list of timestamps
    /// @param staker_ Address of the staker
    /// @param checkpoint_timestamps_ A list of checkpoints timestamps, retrievable with checkpoint_timestamps(...)
    function checkpoints(address staker_, uint256[] memory checkpoint_timestamps_) public view returns (uint256[] memory _balances_) {
        _balances_ = new uint256[](checkpoint_timestamps_.length);
        uint256 len = checkpoint_timestamps_.length;
        for(uint256 i = 0; i < len; i++) {
            _balances_[i] = _user_to_checkpoint_to_balance[staker_][checkpoint_timestamps_[i]];
        }
    }

    function _unstake(uint256 amount_, address staker_, address receiver_) internal returns (uint256) {
        uint256[] storage _checkpoints = _user_checkpoints[staker_];
        
        uint256 _balance = 0;
        if(_checkpoints.length > 0) {
            uint256 _last_ts = _checkpoints[_checkpoints.length-1];
            _balance += _user_to_checkpoint_to_balance[staker_][_last_ts];
        }

        _balance -= amount_;
        bool success = token.transfer(receiver_, amount_);
        if(!success) {
            revert UnableToUnstakeTokens(staker_, amount_, token.balanceOf(address(this)));
        }

        uint256 _current_ts = block.timestamp;
        _checkpoints.push(_current_ts);
        _user_to_checkpoint_to_balance[staker_][_current_ts] = _balance;

        return _balance;
    }

    function _stake(address staker_, uint256 amount_) internal {
        uint256[] storage _checkpoints = _user_checkpoints[staker_];
        
        uint256 _balance = amount_;
        if(_checkpoints.length > 0) {
            uint256 _last_ts = _checkpoints[_checkpoints.length-1];
            _balance += _user_to_checkpoint_to_balance[staker_][_last_ts];
        }

        uint256 _current_ts = block.timestamp;
        _checkpoints.push(_current_ts);
        _user_to_checkpoint_to_balance[staker_][_current_ts] = _balance;

        emit Stake(staker_, msg.sender, amount_, _balance);
    }
}