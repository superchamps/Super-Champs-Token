// SPDX-License-Identifier: None
// Super Champs Foundation 2024
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCMetagameRegistry.sol";
import "../../interfaces/ISCMetagameDataSource.sol";
import "../../interfaces/ISCAccessPass.sol";
import "./SCMetagameLocationRewards.sol";

/// @title Manager for "Location Cup" token metagame
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Allows system to add locations, report scores for locations, assign awards tier percentages and distribute emissions tokens to location contribution contracts.
contract SCMetagameLocations is ISCMetagameDataSource {

    /// @notice Stores data related to each epoch of the location cup metagame
    struct EpochData {
        /// @notice Maps names of locations to their score
        mapping(string => uint256) location_scores;
        /// @notice Maps names of locations to their rank order
        /// @dev Order of 0 is used to indicate an uninitialized score. "1" is top score rank order.
        mapping(string => uint256) location_orders;
    }

    /// @notice The metadata registry.
    /// @dev Stores location membership information for users.
    ISCMetagameRegistry public immutable metadata;

    /// @notice The permissions registry.
    IPermissionsManager public immutable permissions;

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
    
    /// @notice List of the existant location names
    string[] public locations;

    /// @notice List of award tiers, measured in proportional basis points
    /// @dev The top scoring location receives prorata share of emissions from entry 0
    uint256[] public award_tiers_bps;

    /// @notice Mapping of epoch state information by epoch number
    mapping(uint256 => EpochData) private epoch_data;

    /// @notice The numeric id (start timestamp) of the current epoch
    uint256 public current_epoch = 0;

    /// @notice The numeric id (start timestamp) of the next epoch 
    uint256 public next_epoch = 0;

    /// @notice Function modifier which requires the sender to possess the systems admin permission as recorded in "permissions"
    modifier isSystemsAdmin() {
        require(permissions.hasRole(IPermissionsManager.Role.SYSTEMS_ADMIN, msg.sender));
        _;
    }

    /// @notice Function modifier which requires the sender to possess the global admin permission as recorded in "permissions"
    modifier isGlobalAdmin() {
        require(permissions.hasRole(IPermissionsManager.Role.GLOBAL_ADMIN, msg.sender));
        _;
    }

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
    ) {
        permissions = IPermissionsManager(permissions_);
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

        location_rewards[location_name_].setRewardsDistribution(address(this));

        locations.push(location_name_);
    }

    /// @notice Retreives the address of the contribution repository of the specified "Location".
    /// @param location_name_ The name of the "Location". Must be the same string used by the metadata registry system.
    function getLocationRewardsStaker(string memory location_name_) public view returns (address) {
        return address(location_rewards[location_name_]);
    }

    /// @notice Assigns reward tiers for locations. Awards will be based on location rank each epoch.
    /// @dev Only callable by address with System Admin permissions.
    /// @param tiers_ List of award tiers, in basis points. Length must match the quantity of locations. Total of all tiers must equal 1000.
    function assignAwardTiers(uint256[] memory tiers_) external isSystemsAdmin {
        require(tiers_.length == locations.length, "AWARD TIERS MISMATCH");

        uint256 _totalBPS = 0;
        delete award_tiers_bps;

        for(uint256 i = 0 ; i < tiers_.length; i++) {
            award_tiers_bps.push(tiers_[i]);
            _totalBPS += tiers_[i];
        }

        require(_totalBPS == 1000, "DOES NOT TOTAL TO 1000 BPS");
    }

    /// @notice Report the scores for each location for the 
    /// @dev Only callable by address with System Admin permissions. Overwrites previous score reports for current epoch. Must report scores for each existant location.
    /// @param epoch_ The epoch the report is for
    /// @param scores_ List of score values in descending order
    /// @param locations_ List of locations that correspond to the list of scores_
    function reportLocationScores(uint256 epoch_, uint256[] memory scores_, string[] memory locations_) external isSystemsAdmin {
        require(epoch_ == current_epoch, "REPORT FOR INCORRECT EPOCH");
        require(scores_.length == locations_.length, "MISMATHCED INPUTS");
        require(locations_.length == locations.length, "NOT A FULL REPORT");

        EpochData storage _epoch_data = epoch_data[current_epoch];

        uint256 _lastScore = type(uint256).max;
        for(uint256 i = 0; i < scores_.length; i++) {
            string memory _location = locations_[i];
            require(getLocationRewardsStaker(_location) != address(0), "HOUSE DOESNT EXIST");
            require(_lastScore > scores_[i], "HOUSES OUT OF ORDER");

            _lastScore = scores_[i];
            _epoch_data.location_scores[_location] = _lastScore;
            _epoch_data.location_orders[_location] = i + 1; //_order of 0 is used to indicate an uninitialized score. 
        }
    }

    /// @notice Retrieves the score and rank order of a specified location for a given epoch. 
    /// @param epoch_ The epoch the request is for
    /// @param location_ The location the request is for
    function getLocationScoreAndOrder(uint256 epoch_, string memory location_) public view returns (uint256 score, uint256 order) {
        score = epoch_data[epoch_].location_scores[location_];
        order = epoch_data[epoch_].location_orders[location_];
    }

    /// @notice Distribute emissions tokens to each locations contributions contract and initializes the next epoch.
    /// @dev Only callable by address with System Admin permissions. Must be called after the epoch has elapsed. Must be called after a score report is generated for each location (or no locations for equal split). Pulls as many tokens as able from the treasury to split between location contribution emissions contracts.
    function distributeRewards() external isSystemsAdmin {
        require(next_epoch <= block.timestamp, "NOT YET NEXT EPOCH");

        EpochData storage _epoch_data = epoch_data[current_epoch];
        require(award_tiers_bps.length == locations.length, "AWARD TIERS MISMATCH");

        uint256 _amount = token.balanceOf(treasury);
        if(_amount > token.allowance(treasury, address(this))) {
            _amount = token.allowance(treasury, address(this));
        }
        require(_amount > 0, "NOTHING TO DISTRIBUTE");
        
        bool _success = token.transferFrom(treasury, address(this), _amount);
        require(_success);
        
        uint256 _balance = token.balanceOf(address(this));
        uint256 _duration = EPOCH; //If somehow the epoch was not initialized for an entire epoch span, default to 1 EPOCH in the future
        if((next_epoch + EPOCH) > block.timestamp) {
            _duration = (next_epoch + EPOCH) - block.timestamp;
        }

        require(_balance > 0, "NOTHING TO DISTRIBUTE");
        
        bool _any_zero_order = false;
        for(uint256 i = 0; i < locations.length; i++) {
            string memory _location = locations[i];
            require(address(location_rewards[_location]) != address(0), "HOUSE DOESNT EXIST");

            uint256 _order = _epoch_data.location_orders[_location];
            uint256 _share = _balance / locations.length; //_share defaults to an even split
            if(_order > 0) { //_order is expected to be zero if the location does not have a reported score
                require(!_any_zero_order, "MISSING HOUSE SCORE");
                _share = (_balance * award_tiers_bps[_order - 1]) / 1000;
            } else if(!_any_zero_order) {  //_order of 0 is acceptable if ALL entry's _order is zero 
                require(i == 0, "MISSING HOUSE SCORE");
                _any_zero_order = true;
            }

            location_rewards[_location].setRewardsDuration(_duration);
            token.transfer(address(location_rewards[_location]), _share);
            location_rewards[_location].notifyRewardAmount(_share);
        }

        current_epoch = next_epoch;
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