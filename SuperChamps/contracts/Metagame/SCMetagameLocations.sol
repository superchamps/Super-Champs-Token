// SPDX-License-Identifier: None
// Super Champs Foundation 2024
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCMetagameRegistry.sol";
import "../../interfaces/ISCMetagameDataSource.sol";
import "../../interfaces/ISCAccessPass.sol";
import "./SCMetagameLocationRewards.sol";

/// @title Manager for "Location Cup" token metagame
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Allows system to add locations, report scores for locations, assign awards tier percentages and distribute emissions tokens to location contribution contracts.
contract SCMetagameLocations is ISCMetagameDataSource, SCPermissionedAccess {
    /// @notice The metadata registry.
    /// @dev Stores location membership information for users.
    ISCMetagameRegistry public immutable metadata;

    /// @notice The emissions token.
    IERC20 public immutable token;

    /// @notice The metagame data view.
    ISCMetagameDataSource public data_view;

    /// @notice The access pass SBT
    ISCAccessPass public access_pass;
    
    /// @notice The treasury that this contract pulls emissions tokens from.
    /// @dev An allowance must be set on the emissions token contract that permits this contract access to the treasury's tokens.
    address public treasury;

    /// @notice The duration of the emissions epochs.
    uint256 public EPOCH = 7 days;

    /// @notice A mapping of the emissions contribution contracts by location name
    mapping(string => SCMetagameLocationRewards) public location_rewards;
    
    /// @notice List of the existent location names
    string[] public locations;

    /// @notice List of award tiers, measured in proportional basis points
    /// @dev The top scoring location receives prorata share of emissions from entry 0
    uint256[] public award_tiers_bps;

    /// @notice The numeric id (start timestamp) of the current epoch
    uint256 public current_epoch = 0;

    /// @notice The numeric id (start timestamp) of the next epoch 
    uint256 public next_epoch = 0;

    event LocationAdded(string location);

    /// @param permissions_ Address of the protocol permissions registry. Must conform to IPermissionsManager.
    /// @param token_ Address of the emissions token.
    /// @param metadata_ Address of the protocol metadata registry. Must conform to ISCMetagameRegistry.
    /// @param treasury_ Address of the treasury which holds emissions tokens for use by the Location Cup metagame.
    /// @param access_pass_ Address of the protocol access pass SBT
    constructor(
        address permissions_,
        address token_,
        address metadata_,
        address treasury_,
        address access_pass_,
        address data_view_
    ) SCPermissionedAccess(permissions_) {
        token = IERC20(token_);
        metadata = ISCMetagameRegistry(metadata_);
        treasury = treasury_;
        access_pass = ISCAccessPass(access_pass_);
        data_view = ISCMetagameDataSource(data_view_);
    }

    /// @notice Assigns a new treasury from which the metagame system draws token rewards.
    /// @dev Only callable by address with Global Admin permissions. Ability to withdraw tokens from treasury_ must be set separately.
    /// @param treasury_ The new treasury's address. 
    function setTreasury(address treasury_) external isGlobalAdmin {
        treasury = treasury_;
    }

    /// @notice Assigns a new metagame data view
    /// @param data_view_ address The new data view address
    /// @dev Only callable by address with Systems Admin permissions. 
    function setDataView(address data_view_) external isSystemsAdmin {
        data_view = ISCMetagameDataSource(data_view_);
    }

    /// @notice Add a new "Location" to the metagame system.
    /// @dev Only callable by address with System Admin permissions. This creates a new contract which participants can contribute tokens to. This new entity is bound to one of the possible "Locations" that the participants accounts can belong to.
    /// @param location_name_ A name for the new "Location". Must be the same string used by the metadata registry system.
    function addLocation(string calldata location_name_) external isSystemsAdmin {
        require(address(location_rewards[location_name_]) == address(0), "HOUSE EXISTS");

        location_rewards[location_name_] = new SCMetagameLocationRewards(
            address(token),
            address(this),
            location_name_,
            address(access_pass)
        );

        locations.push(location_name_);
        
        emit LocationAdded(location_name_);
    }

    /// @notice Retreives the address of the contribution repository of the specified "Location".
    /// @param location_name_ The name of the "Location". Must be the same string used by the metadata registry system.
    /// @return address The address of the location's synthetix staking contract
    function getLocationRewardsStaker(string memory location_name_) public view returns (address) {
        return address(location_rewards[location_name_]);
    }

    /// @notice Distribute emissions tokens to each locations contributions contract and initializes the next epoch.
    /// @dev Only callable by address with System Admin permissions. Must be called after the epoch has elapsed. 
    function distributeRewards(uint256 epoch_, string[] memory locations_, uint256[] memory location_reward_shares_) external isSystemsAdmin {
        require(epoch_ == current_epoch, "INCORRECT EPOCH");
        
        uint256 _next_epoch = next_epoch;
        require(_next_epoch <= block.timestamp, "NOT YET NEXT EPOCH");

        uint256 _length = locations_.length;
        require(_length == location_reward_shares_.length, "INPUT MISMATCH");
        
        uint256 _amount;
        for(uint256 i = 0; i < _length; i++) {
            _amount += location_reward_shares_[i];
        }

        require(_amount > token.allowance(treasury, address(this)), "NOT ENOUGH TO DISTRIBUTE");
        
        bool _success = token.transferFrom(treasury, address(this), _amount);
        require(_success);
        
        uint256 _duration = EPOCH; //If somehow the epoch was not initialized for an entire epoch span, default to 1 EPOCH in the future
        if((_next_epoch + _duration) > block.timestamp) {
            _duration = (_next_epoch + _duration) - block.timestamp;
        }
        
        uint256 _num_locations = locations_.length;
        for(uint256 i = 0; i < _num_locations; i++) {
            string memory _location = locations_[i];
            SCMetagameLocationRewards _location_staker = location_rewards[_location];
            require(address(_location_staker) != address(0), "LOCATION DOESNT EXIST");
            require(_location_staker.periodFinish() < block.timestamp, "LOCATION STREAM NOT FINISHED");
            uint256 _share = location_reward_shares_[i];
            _location_staker.setRewardsDuration(_duration);
            bool success = token.transfer(address(_location_staker), _share);
            require(success, "TRANSFER FAILED");
            _location_staker.notifyRewardAmount(_share);
        }

        current_epoch = _next_epoch;
        next_epoch = block.timestamp + _duration;
    }

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        require(tokenAddress_ != address(token), "CANT WITHDRAW CHAMP");
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }

    /// @notice Transfer tokens that have been sent to a location staking contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param location_ The location name of the contract to recover tokens from
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20FromLocation(string calldata location_, address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        location_rewards[location_].recoverERC20(tokenAddress_, tokenAmount_);
    }

    /// @notice Set a new duration for subsequent epochs
    /// @dev Only callable by address with Systems Admin permissions. 
    /// @param duration_ The new duration in seconds
    function setEpochDuration(uint256 duration_) external isSystemsAdmin {
        EPOCH = duration_;
    }

    /// @notice Read the quantity of locations that exist
    function locationCount() public view returns (uint256 count) {
        count = locations.length;
    }

    /// @notice Queries the bonus multiplier of a specfied address at a specified location.
    /// @param addr_ The address to query.
    /// @param location_ The location id to query.
    /// @return _result uint256 Returns the numeric metadata mapped to that address, in basis points
    function getMultiplier(address addr_, string memory location_) external view returns (uint256) {
        return data_view.getMultiplier(addr_, location_);
    }

    /// @notice Queries if a specfied address is a member of a specified location.
    /// @param addr_ The address to query.
    /// @param location_ The location id to query.
    /// @return _result bool Returns true if the address is a member of the location.
    function getMembership(address addr_, string memory location_) external view returns (bool) {
        return data_view.getMembership(addr_, location_);
    }
}