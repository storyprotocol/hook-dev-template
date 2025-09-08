// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { BaseModule } from "@storyprotocol/core/modules/BaseModule.sol";
import { AccessControlled } from "@storyprotocol/core/access/AccessControlled.sol";
import { ILicensingHook } from "@storyprotocol/core/interfaces/modules/licensing/ILicensingHook.sol";
import { ILicenseTemplate } from "@storyprotocol/core/interfaces/modules/licensing/ILicenseTemplate.sol";

/// @title License Caller Whitelist Hook
/// @notice This hook enforces whitelist restrictions for license token minting.
///         Only addresses that have been whitelisted by the IP owner can call the mint function
///         for a specific license attached to an IP. To use this hook, set the `licensingHook` field
///         in the licensing config to the address of this hook.
/// @dev This hook whitelists the caller, not the receiver of the license tokens.
///      A whitelisted address can mint tokens for any receiver address.
contract LicenseCallerWhitelistHook is BaseModule, AccessControlled, ILicensingHook {
    string public constant override name = "LICENSE_CALLER_WHITELIST_HOOK";

    /// @notice Stores the whitelist status for addresses for a given license.
    /// @dev The key is keccak256(licensorIpId, licenseTemplate, licenseTermsId, minterAddress).
    /// @dev The value is true if the address is whitelisted, false otherwise.
    mapping(bytes32 => bool) private whitelist;

    /// @notice Emitted when an address is added to the whitelist
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address that was whitelisted
    event AddressWhitelisted(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address minter
    );

    /// @notice Emitted when an address is removed from the whitelist
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address that was removed from whitelist
    event AddressRemovedFromWhitelist(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address minter
    );

    error LicenseCallerWhitelistHook_AddressNotWhitelisted(address minter);
    error LicenseCallerWhitelistHook_AddressAlreadyWhitelisted(address minter);
    error LicenseCallerWhitelistHook_AddressNotInWhitelist(address minter);

    constructor(
        address accessController,
        address ipAssetRegistry
    ) AccessControlled(accessController, ipAssetRegistry) {}

    /// @notice Add an address to the whitelist for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address to add to the whitelist
    function addToWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address minter
    ) external verifyPermission(licensorIpId) {
        bytes32 key = keccak256(abi.encodePacked(licensorIpId, licenseTemplate, licenseTermsId, minter));
        if (whitelist[key]) revert LicenseCallerWhitelistHook_AddressAlreadyWhitelisted(minter);
        whitelist[key] = true;
        emit AddressWhitelisted(licensorIpId, licenseTemplate, licenseTermsId, minter);
    }

    /// @notice Remove an address from the whitelist for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address to remove from the whitelist
    function removeFromWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address minter
    ) external verifyPermission(licensorIpId) {
        bytes32 key = keccak256(abi.encodePacked(licensorIpId, licenseTemplate, licenseTermsId, minter));
        if (!whitelist[key]) revert LicenseCallerWhitelistHook_AddressNotInWhitelist(minter);
        whitelist[key] = false;
        emit AddressRemovedFromWhitelist(licensorIpId, licenseTemplate, licenseTermsId, minter);
    }

    /// @notice Check if an address is whitelisted for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address to check
    /// @return isWhitelisted True if the address is whitelisted, false otherwise
    function isWhitelisted(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address minter
    ) external view returns (bool isWhitelisted) {
        bytes32 key = keccak256(abi.encodePacked(licensorIpId, licenseTemplate, licenseTermsId, minter));
        return whitelist[key];
    }

    /// @notice This function is called when the LicensingModule mints license tokens.
    /// @dev The hook can be used to implement various checks and determine the minting price.
    /// The hook should revert if the minting is not allowed.
    /// @param caller The address of the caller who calling the mintLicenseTokens() function.
    /// @param licensorIpId The ID of licensor IP from which issue the license tokens.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template,
    /// which is used to mint license tokens.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver who receive the license tokens.
    /// @param hookData The data to be used by the licensing hook.
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens.
    function beforeMintLicenseTokens(
        address caller,
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata hookData
    ) external returns (uint256 totalMintingFee) {
        _checkWhitelist(licensorIpId, licenseTemplate, licenseTermsId, caller);
        return _calculateFee(licenseTemplate, licenseTermsId, amount);
    }

    /// @notice This function is called before finalizing LicensingModule.registerDerivative(), after calling
    /// LicenseRegistry.registerDerivative().
    /// @dev The hook can be used to implement various checks and determine the minting price.
    /// The hook should revert if the registering of derivative is not allowed.
    /// @param childIpId The derivative IP ID.
    /// @param parentIpId The parent IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template.
    /// @param hookData The data to be used by the licensing hook.
    /// @return mintingFee The minting fee to be paid when register child IP to the parent IP as derivative.
    function beforeRegisterDerivative(
        address caller,
        address childIpId,
        address parentIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        bytes calldata hookData
    ) external returns (uint256 mintingFee) {
        _checkWhitelist(parentIpId, licenseTemplate, licenseTermsId, caller);
        return _calculateFee(licenseTemplate, licenseTermsId, 1);
    }

    /// @notice This function is called when the LicensingModule calculates/predict the minting fee for license tokens.
    /// @dev The hook should guarantee the minting fee calculation is correct and return the minting fee which is
    /// the exact same amount with returned by beforeMintLicenseTokens().
    /// The hook should revert if the minting fee calculation is not allowed.
    /// @param caller The address of the caller who calling the mintLicenseTokens() function.
    /// @param licensorIpId The ID of licensor IP from which issue the license tokens.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template,
    /// which is used to mint license tokens.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver who receive the license tokens.
    /// @param hookData The data to be used by the licensing hook.
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens.
    function calculateMintingFee(
        address caller,
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata hookData
    ) external view returns (uint256 totalMintingFee) {
        return _calculateFee(licenseTemplate, licenseTermsId, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseModule, IERC165) returns (bool) {
        return interfaceId == type(ILicensingHook).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev checks if an address is whitelisted for a given license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param minter The address to check
    function _checkWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address minter
    ) internal view {
        bytes32 key = keccak256(abi.encodePacked(licensorIpId, licenseTemplate, licenseTermsId, minter));
        if (!whitelist[key]) {
            revert LicenseCallerWhitelistHook_AddressNotWhitelisted(minter);
        }
    }

    /// @dev calculates the minting fee for a given license
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param amount The amount of license tokens to mint
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens
    function _calculateFee(
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount
    ) internal view returns (uint256 totalMintingFee) {
        (, , uint256 mintingFee, ) = ILicenseTemplate(licenseTemplate).getRoyaltyPolicy(licenseTermsId);
        return amount * mintingFee;
    }
}
