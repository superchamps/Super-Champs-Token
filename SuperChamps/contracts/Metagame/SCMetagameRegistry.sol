// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCMetagameRegistry.sol";

/// @title Metagame metadata registry.
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Used to store arbitrary metadata associated with specific user IDs and Addresses.
/// @dev Metadata is stored in a key-value store that maps string metadata keys to string values. Lookup can be indexed from user ID or from address.
contract SCMetagameRegistry is ISCMetagameRegistry, SCPermissionedAccess {    
    /// @notice Mapping of addresses to user id hashes
    mapping(address => bytes32) private address_to_uid_hash;

    /// @notice Mapping of user id hashes to user ids
    mapping(bytes32 => string) private uid_hash_to_user_id;

    /// @notice Mapping of user id hashes to a mapping of metadata keys to values
    mapping(bytes32 => mapping(string => string)) private metadata;

    /// @notice Stores consumed transaction signatures
    /// @dev Signatures are related to user-initiated metadata updates, which use a signature scheme to validate the update comes from a trusted source
    mapping(bytes => bool) private consumed_signatures;

    /// @notice Stores the last used nonce for signature-based metadata updates
    mapping(string => uint256) public uid_hash_last_nonce;

    /// @param permissions_ Address of the protocol permissions registry. Must conform to IPermissionsManager
    constructor(address permissions_) SCPermissionedAccess(permissions_) {}

    /// @notice Used to construct a message hash for signature-based metadata updates
    /// @param user_id_ The ID of the User
    /// @param add_address_ Address to add to the user's metadata (if any). Will be address(0) if no update is required.
    /// @param updated_key_ The metadata key to update (if any). Will be "" if no update is required.
    /// @param updated_value_ The metadata value to update for the specified key (if any). Will be "" if no update is required.
    /// @param signature_expiry_ts_ The latest timestamp that this signature can be considered valid
    /// @param signature_nonce_ The nonce of this signature. Used to prevent signature from being consumed out of order.
    /// @return bytes32 The hash of the packed update message data
    function hashMessage(
        string memory user_id_,
        address add_address_,
        string memory updated_key_,
        string memory updated_value_,
        uint256 signature_expiry_ts_,
        uint256 signature_nonce_
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            keccak256(abi.encodePacked(user_id_)),
            add_address_,
            keccak256(abi.encodePacked(updated_key_)),
            keccak256(abi.encodePacked(updated_value_)),
            signature_expiry_ts_,
            signature_nonce_
        ));
    }

    /// @notice Used to query a metadata value for a user by a specified address and key
    /// @param address_ Address of the user
    /// @param metadata_key_ String of the key being queried for the specified address's user
    /// @return string The stored value for the queried user/key pair. Returns "" if no data is stored for the user in that key, or, if there is no user associated with the address.
    function metadataFromAddress(
        address address_,
        string calldata metadata_key_
    ) public view returns(string memory) {
        return metadata[address_to_uid_hash[address_]][metadata_key_];
    }

    /// @notice Used to query a metadata value for a user by a specified user id and key
    /// @param user_id_ ID of the user
    /// @param metadata_key_ String of the key being queried for the specified user
    /// @return string The stored value for the queried user/key pair. Returns "" if no data is stored for that user in that key.
    function metadataFromUserID(
        string calldata user_id_,
        string calldata metadata_key_
    ) public view returns(string memory) {
        bytes32 _uid_hash =  keccak256(abi.encodePacked(user_id_));
        return metadata[_uid_hash][metadata_key_];
    }

    /// @notice Used to query a user ID from an address
    /// @param address_ Address to query a user ID from
    /// @return string The user ID associated with the specified address. Returns "" if not associated with a user.
    function addressToUserID(
        address address_
    ) public view returns(string memory) {
        return uid_hash_to_user_id[address_to_uid_hash[address_]];
    }

    /// @notice Used to update a user's metadata and/or associate an address with a user.
    /// @dev May be called by a non-systems admin address or contract by providing a valid signature. May be called by a systems admin by providing "" as the signature.
    /// @param user_id_ The ID of the User
    /// @param add_address_ Address to add to the user's metadata (if any). Will be address(0) if no update is required.
    /// @param updated_key_ The metadata key to update (if any). Will be "" if no update is required.
    /// @param updated_value_ The metadata value to update for the specified key (if any). Will be "" if no update is required.
    /// @param signature_expiry_ts_ The latest timestamp that this signature can be considered valid
    /// @param signature_nonce_ The nonce of this signature. Used to prevent signature from being consumed out of order.
    /// @param signature_ A signature used to validate that the update is authorized. May be empty if called by an address with Systems Admin permissions.
    function registerUserInfo (
        string memory user_id_,
        address add_address_,
        string memory updated_key_,
        string memory updated_value_,
        uint256 signature_expiry_ts_,
        uint256 signature_nonce_,
        bytes calldata signature_
    ) public {
        if(signature_.length > 0) {
            require(signature_expiry_ts_ > block.timestamp, "INVALID EXPIRY");
            require(uid_hash_last_nonce[user_id_] < signature_nonce_, "CONSUMED NONCE");
            require(!consumed_signatures[signature_], "CONSUMED SIGNATURE");
            
            uid_hash_last_nonce[user_id_] = signature_nonce_;
            consumed_signatures[signature_] = true;

            bytes32 _messageHash = hashMessage(
                user_id_,
                add_address_,
                updated_key_,
                updated_value_,
                signature_expiry_ts_,
                signature_nonce_
            );

            _messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
            
            (bytes32 _r, bytes32 _s, uint8 _v) = _splitSignature(signature_);
            address _signer = ecrecover(_messageHash, _v, _r, _s);
            require(permissions.hasRole(IPermissionsManager.Role.SYSTEMS_ADMIN, _signer), "INVALID SIGNER");
        } else {
            require(permissions.hasRole(IPermissionsManager.Role.SYSTEMS_ADMIN, msg.sender), "NOT AUTHORIZED");
        }

        bytes32 _uid_hash =  keccak256(abi.encodePacked(user_id_));
        uid_hash_to_user_id[_uid_hash] = user_id_;

        require(address_to_uid_hash[add_address_] == 0, "ADDRESS ALREADY REGISTERED");
        address_to_uid_hash[add_address_] = _uid_hash;

        mapping(string => string) storage user_metadata = metadata[_uid_hash];
        
        user_metadata[updated_key_] = updated_value_;
    }

    /// @notice Used to split a signature into r,s,v components which are required to recover a signing address.
    /// @param sig_ The signature to split
    /// @return _r bytes32 The r component
    /// @return _s bytes32 The s component
    /// @return _v bytes32 The v component
    function _splitSignature(bytes memory sig_)
        private pure
        returns (bytes32 _r, bytes32 _s, uint8 _v)
    {
        require(sig_.length == 65, "INVALID SIGNATURE LENGTH");

        assembly {
            _r := mload(add(sig_, 32))
            _s := mload(add(sig_, 64))
            _v := byte(0, mload(add(sig_, 96)))
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