// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../Utils/SCPermissionedAccess.sol";

/// @title Shop Sales Manager
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @notice Used by the Super Champs Shop system to transfer tokens from user accounts. 
/// @dev Allows the transfer of tokens from user accounts before token unlock.
contract SCShop is SCPermissionedAccess {
    ///@notice The token used by the shop. (The CHAMP token.)
    IERC20 immutable token;

    ///@notice Emitted when a call to saleTransaction(...) completes.
    event saleReceipt(address buyer, uint256 amount, string subsystem, string metadata);

    ///@param permissions_ Address of the protocol permissions registry. Must conform to IPermissionsManager.
    ///@param token_ Address of the sales token. Must conform to IERC20.
    constructor(address permissions_, address token_) SCPermissionedAccess(permissions_) {
        token = IERC20(token_);
    }

    ///@notice Transfers tokens from one user to a "till" account.
    ///@dev Purpose is to emit a saleReceipt event and to allow transfer of tokens from user wallets by the Shop system before token unlock.
    ///@param buyer_ Address that is sending tokens.
    ///@param recipient_ Address that is receiving the tokens.
    ///@param amount_ The quantity of tokens sent.
    ///@param subsystem_ The string ID of the Shop subsystem calling this function.
    ///@param metadata_ An optional string parameter that may be populated with arbitrary metadata.
    function saleTransaction (
        address buyer_,
        address recipient_,
        uint256 amount_, 
        string memory subsystem_, 
        string calldata metadata_
    ) public isSystemsAdmin
    {
        bool success = token.transferFrom(buyer_, recipient_, amount_);
        require(success);

        emit saleReceipt(buyer_, amount_, subsystem_, metadata_);
    }

    ///@notice Transfers tokens from one user to a "till" account.
    ///@dev Purpose is to emit a saleReceipt event and to allow transfer of tokens from user wallets by the Shop system before token unlock.
    ///@param buyer_ Address that is sending tokens.
    ///@param seller_ Address that is receiving the tokens.
    ///@param price_ The quantity of tokens sent.
    ///@param token_id_ The token ID of the NFT being sold.
    ///@param sale_metadata_ An optional string parameter that may be populated with arbitrary metadata.
    ///@param sale_metadata_ An optional bytes parameter that is fed to the onERC721Received(...) call, post transfer to a valid receiver contract.
    function nftChampTrade (
        address buyer_,
        address seller_,
        uint256 price_,
        IERC721 nft_,
        uint256 token_id_,
        string calldata sale_metadata_,
        bytes calldata transfer_metadata_
    ) public isSystemsAdmin
    {
        saleTransaction(buyer_, seller_, price_, "NFT", sale_metadata_);
        nft_.safeTransferFrom(seller_, buyer_, token_id_, transfer_metadata_);
    }

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }
}