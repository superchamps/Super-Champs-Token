// SPDX-License-Identifier: None
// Super Champs Foundation 2024
pragma solidity ^0.8.24;


import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCMetagameRegistry.sol";
import "../../interfaces/ISCMetagameDataSource.sol";
import "../../interfaces/ISCAccessPass.sol";

/// @title Metagame data view for determining metagame multipliers and membership, by address
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
contract SCMetagameGenericDataView is ISCMetagameDataSource, SCPermissionedAccess {
    /// @dev The key of the house id metadata tag. Used to retrieve house membership data of addresses from the metadata registry. 
    string constant HOMETOWN_ID = "hometown";

    ISCMetagameRegistry public metadata_registry;

    /// @notice A mapping of ISCMetagameDataSource by location id.
    mapping(string => ISCMetagameDataSource) public location_views;

    constructor(address permissions_, address metadata_registry_) SCPermissionedAccess(permissions_) {
        metadata_registry = ISCMetagameRegistry(metadata_registry_);
    }

    /// @notice Sets the ISCMetagameDataSource view for a specified location.
    /// @param view_ The ISCMetagameDataSource view address.
    /// @param location_ The location id.
    function setLocationView(address view_, string memory location_) public isSystemsAdmin {
        location_views[location_] = ISCMetagameDataSource(view_);
    }

    /// @notice Queries the base multiplier of a specfied address.
    /// @param addr_ The address to query.
    /// @return _result uint256 Returns the numeric metadata mapped to that address, in basis points
    function getBaseMultiplier(address addr_) public view returns (uint256) {
        return location_views[""].getMultiplier(addr_, "");
    }

    /// @notice Queries the bonus multiplier of a specfied address at a specified location.
    /// @param addr_ The address to query.
    /// @param location_ The location id to query.
    /// @return _result uint256 Returns the numeric metadata mapped to that address, in basis points
    function getMultiplier(address addr_, string memory location_) external view returns (uint256) {
        return 10_000 + getBaseMultiplier(addr_) + location_views[location_].getMultiplier(addr_, location_);
    }

    /// @notice Queries if a specfied address is a member of a specified location.
    /// @param addr_ The address to query.
    /// @param location_ The location id to query.
    /// @return _result bool Returns true if the address is a member of the location.
    function getMembership(address addr_, string memory location_) external view returns (bool) {
        if(location_views[location_] == ISCMetagameDataSource(address(0))) {
            //Default to check and see if player's hometown matches the location
            return keccak256(bytes(metadata_registry.metadataFromAddress(addr_, HOMETOWN_ID))) == 
                   keccak256(bytes(location_));
        } else {
            return location_views[location_].getMembership(addr_, location_);
        }
    }
}