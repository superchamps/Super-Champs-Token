// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "../Utils/SCPermissionedAccess.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISCSeasonRewards.sol";

/// @title Token Rewards Faucet
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice This contract that allows arbitrary addresses to claim reward tokens by providing a valid signature
contract SCRewardsDispenser is EIP712, SCPermissionedAccess {
    using ECDSA for bytes32;

    struct Claim {
        uint256 amount_;
        uint256 signature_expiry_ts_;
    }

    ///@notice The reward token that this contract manages
    IERC20 immutable token;

    ///@notice A set of consumed message signature hashes
    ///@dev Members of the set are not valid signatures
    mapping(bytes => bool) private consumed_signatures;

    ///@notice Emitted when an account claims reward tokens
    event rewardClaimed(address recipient, uint256 amount);

    ///@param permissions_ The address of the protocol permissions registry. Must conform to IPermissionsManager.
    ///@param token_ The address of the rewawd token. Must conform to IERC20.
    constructor(address permissions_, address token_) 
        SCPermissionedAccess(permissions_) 
        EIP712("SCRewardsDispensor", "SCRDv1")
    {
        token = IERC20(token_);
    }

    function extractSigner712(
        uint256 amount_,
        uint256 signature_expiry_ts_,
        bytes memory signature_
    ) public view returns (address) 
    {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Claim(uint256 amount_,uint256 signature_expiry_ts_)"),
                    amount_,
                    signature_expiry_ts_
                )
            )
        );
        address signer = ECDSA.recover(digest, signature_);
        return signer;
    }

    function claim(
        Claim memory claim_,
        bytes memory signature_
    ) external 
    {
        require(claim_.signature_expiry_ts_ > block.timestamp, "INVALID EXPIRY");
        require(!consumed_signatures[signature_], "CONSUMED SIGNATURE");
        
        consumed_signatures[signature_] = true;

        address _signer = extractSigner712(claim_.amount_,claim_.signature_expiry_ts_,signature_);
        require(permissions.hasRole(IPermissionsManager.Role.SYSTEMS_ADMIN, _signer), "INVALID SIGNER");

        token.transfer(msg.sender, claim_.amount_);
        emit rewardClaimed(msg.sender, claim_.amount_);
    }

    function withdraw() 
        external isGlobalAdmin
    {
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }
}