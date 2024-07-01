// SPDX-License-Identifier: None
// Super Champs Foundation 2024

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Utils/SCPermissionedAccess.sol";
import "./SCGenericRenderer.sol";
import "../../interfaces/IPermissionsManager.sol";
import "../../interfaces/ISuperChampsToken.sol";
import "../../interfaces/IERC721MetadataRenderer.sol";

/// @title Super Champs (CHAMP) Temporarily Transfer Locked NFT
/// @author Chance Santana-Wees (Coelacanth/Coel.eth)
/// @dev Token transfers are restricted to addresses that have the Transer Admin permission until the CHAMP token is unlocked.
/// @notice This is a standard ERC721 token contract that restricts token transfers before the protocol token is unlocked. Trades still possible via Shop/Marketplace system, but limited to sales denominated in CHAMP.
contract SCTempLockedNFT is ERC721, SCPermissionedAccess {
    /// @notice The metadata renderer contract.
    IERC721MetadataRenderer private _renderer;
    
    ///@notice The protocol token;
    ISuperChampsToken public immutable champ_token;

    /// @notice The token ID counter
    uint256 private _tokenIdCounter = 1;

    ///@notice A function modifier that restricts to Transfer Admins until transfersLocked is set to true.
    modifier isAdminOrUnlocked() {
        require(!champ_token.transfersLocked() || 
                permissions.hasRole(IPermissionsManager.Role.TRANSFER_ADMIN, _msgSender()) ||
                permissions.hasRole(IPermissionsManager.Role.TRANSFER_ADMIN, tx.origin),
                "NOT YET UNLOCKED");
        _;
    }

    ///@param name_ String representing the token's name.
    ///@param symbol_ String representing the token's symbol.
    ///@param champ_token_ The protocol token.
    constructor(
        string memory name_,
        string memory symbol_,
        string memory uri_,
        ISuperChampsToken champ_token_
    ) 
        ERC721(name_, symbol_) SCPermissionedAccess(address(champ_token_.permissions()))
    {
        champ_token = champ_token_;
        permissions = champ_token_.permissions();
        _renderer = new SCGenericRenderer(permissions, name_, symbol_, uri_);
    }

    /// @notice Sets a new renderer contract.
    /// @dev Only callable by a systems admin.
    /// @param renderer_ The new renderer contract. Must conform to IERC721MetadataRenderer.
    function setRenderer(address renderer_) external isSystemsAdmin {
        _renderer = IERC721MetadataRenderer(renderer_);
        
    }

    /// @notice Mints an NFT to a recipient.
    /// @dev Callable only by Systems Admin. Sales costs and administration should be performed off-chain or in a separate sales contract.
    /// @param recipient_ The token recipient.
    function mintTo(address recipient_) external isSystemsAdmin {
        uint256 _tokenId = _tokenIdCounter;
        _safeMint(recipient_, _tokenId);
        _tokenIdCounter++;
    }

    ///@notice Identical to standard transferFrom function, except that transfers are restricted to Admins until transfersLocked is set. 
    function transferFrom(
        address from_, 
        address to_, 
        uint256 token_id_
    ) public override isAdminOrUnlocked {
        return super.transferFrom(from_, to_, token_id_);
    }

    /// @notice Transfer tokens that have been sent to this contract by mistake.
    /// @dev Only callable by address with Global Admin permissions. Cannot be called to withdraw emissions tokens.
    /// @param tokenAddress_ The address of the token to recover
    /// @param tokenAmount_ The amount of the token to recover
    function recoverERC20(address tokenAddress_, uint256 tokenAmount_) external isGlobalAdmin {
        IERC20(tokenAddress_).transfer(msg.sender, tokenAmount_);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view override returns (string memory) {
        return _renderer.name();
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view override returns (string memory) {
        return _renderer.symbol();
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _renderer.tokenURI(tokenId);
    }
}