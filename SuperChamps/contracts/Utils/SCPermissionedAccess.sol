// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "../../interfaces/IPermissionsManager.sol";

contract SCPermissionedAccess {
    IPermissionsManager public immutable permissions;

    /// @notice Function modifier which requires the sender to possess the global admin permission as recorded in "permissions"
    modifier isGlobalAdmin() {
        require(permissions.hasRole(IPermissionsManager.Role.GLOBAL_ADMIN, msg.sender), "Not a Global Admin");
        _;
    }

    /// @notice Function modifier which requires the sender to possess the systems admin permission as recorded in "permissions"
    modifier isSystemsAdmin() {
        require(permissions.hasRole(IPermissionsManager.Role.SYSTEMS_ADMIN, msg.sender), "Not a Systems Admin");
        _;
    }

    constructor(address _permissions){
        permissions = IPermissionsManager(_permissions);
    }
}