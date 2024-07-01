// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;
import "../Utils/SCPermissionedAccess.sol";

/// @title SuperChamps Game Events Logger
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice A permissioned events logger. Used for tracking virtual asset transactions on chain, via events only.
contract SCVirtualAssetEvents {
    ISCVirtualAssetEventsFactory _factory;
    string public game;

    event GameUserAsset(string user_id, string asset_id, int256 delta, string data);
    event GameUserActivity(string user_id, string data);

    modifier isPermissionedUser() {
        require(_factory.permissions_users(msg.sender), "NOT PERMISSIONED USER");
        _;
    }

    constructor(ISCVirtualAssetEventsFactory factory_, string memory game_) {
        _factory = factory_;
        game = game_;
    }

    function EmitGameUserAsset(string memory user_id, string memory asset_id, int256 delta, string memory data) external isPermissionedUser {
        emit GameUserAsset(user_id, asset_id, delta, data);
    }

    function EmitGameUserActivity(string memory user_id, string memory data) external isPermissionedUser {
        emit GameUserActivity(user_id, data);
    }
}

interface ISCVirtualAssetEventsFactory {
    function permissions_users(address user) external view returns (bool);
}

/// @title SuperChamps Game Events Logger Factory
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Used to deploy game specific events loggers. Tracks users who are permissioned to emit events.
contract SCVirtualAssetEventsFactory is SCPermissionedAccess, ISCVirtualAssetEventsFactory {
    mapping(address => bool) public permissions_users;
    mapping(string => SCVirtualAssetEvents) public game_events;
    string[] private _games; 

    constructor(address permissions_) SCPermissionedAccess(permissions_) { }

    function permissionUser(address[] memory users, bool state) external isSystemsAdmin {
        uint256 len = users.length;
        for(uint256 i = 0; i < len; i++) {
            permissions_users[users[i]] = state;
        }
    }

    function deployGameEvents(string memory game_id) external isSystemsAdmin {
        require(game_events[game_id] == SCVirtualAssetEvents(address(0)), "GAME EXISTS");
        game_events[game_id] = new SCVirtualAssetEvents(this, game_id);
        _games.push(game_id);
    }

    function games() external view returns (string[] memory _games_) {
        uint len = _games.length;
        _games_ = new string[](len);
        for(uint i = 0; i < len; i++) {
            _games_[i] = _games[i];
        }
    }
}