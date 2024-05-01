// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import { StakingRewards } from "../../../Synthetix/contracts/StakingRewards.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/ISCMetagameRegistry.sol";
import "../../interfaces/ISCAccessPass.sol";

/// @title House membership gated extension of a Synthetix StakingRewards contract
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Requires that a contributor belong to the associated house, as defined by the protocol metadata registry.
contract SCMetagameHouseRewards is StakingRewards {
    /// @dev The key of the house id metadata tag. Used to retrieve house membership data of addresses from the metadata registry. 
    string constant HOUSE_ID_KEY = "house_id";

    /// @notice The metadata registry
    ISCMetagameRegistry immutable metadata;

    /// @notice The name of the associated house
    string public house_id;

    /// @notice The access pass SBT
    ISCAccessPass public access_pass;

    /// @dev Hash of the name of the house, used for comparison with the house names retrieved from the metadata registry
    bytes32 house_hash;
    
    /// @param token_ Address of the emissions token.
    /// @param metadata_ Address of the protocol metadata registry. Must conform to ISCMetagameRegistry.
    /// @param house_id_ String representation of the name of the associated "House"
    /// @param access_pass_ Address of the protocol access pass SBT
    constructor(
        address token_,
        address metadata_,
        string memory house_id_,
        address access_pass_
    ) StakingRewards(address(msg.sender), address(msg.sender), token_, token_) {
        metadata = ISCMetagameRegistry(metadata_);
        house_id = house_id_;
        house_hash = keccak256(bytes(house_id));
        access_pass = ISCAccessPass(access_pass_);
    }

    /// @notice Identical to base contract except that only specific users may deposit tokens. See {StakingRewards-stake}.
    function stake(uint256 amount_) external override nonReentrant notPaused updateReward(msg.sender) {
        bytes32 _sender_house_hash = keccak256(abi.encodePacked(metadata.metadataFromAddress(msg.sender, HOUSE_ID_KEY)));
        require(_sender_house_hash == house_hash, "MUST BE IN HOUSE");
        require(access_pass.isVerified(msg.sender), "MUST HAVE VERIFIED ACCESS PASS");
        require(amount_ > 0, "CANNOT STAKE 0");

        _totalSupply = _totalSupply + amount_;
        _balances[msg.sender] = _balances[msg.sender] + amount_;
        stakingToken.transferFrom(msg.sender, address(this), amount_);

        emit Staked(msg.sender, amount_);
    }
}