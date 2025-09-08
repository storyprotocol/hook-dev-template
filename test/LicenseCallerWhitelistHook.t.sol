// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IIPAssetRegistry } from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import { IPILicenseTemplate } from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { ILicensingModule } from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import { ILicenseToken } from "@storyprotocol/core/interfaces/ILicenseToken.sol";
import { PILFlavors } from "@storyprotocol/core/lib/PILFlavors.sol";
import { Licensing } from "@storyprotocol/core/lib/Licensing.sol";
import { ModuleRegistry } from "@storyprotocol/core/registries/ModuleRegistry.sol";
import { MockERC20 } from "@storyprotocol/test/mocks/token/MockERC20.sol";

import { LicenseCallerWhitelistHook } from "../contracts/LicenseCallerWhitelistHook.sol";
import { BaseTest } from "@storyprotocol/periphery/test/utils/BaseTest.t.sol";

// Run this test:
// forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/LicenseCallerWhitelistHook.t.sol
contract LicenseCallerWhitelistHookTest is BaseTest {
    address internal alice = address(0xa11ce);
    address internal bob = address(0xb0b);
    address internal charlie = address(0xc4a11e);
    address internal david = address(0xd4a11e);

    // For addresses, see https://docs.story.foundation/docs/deployed-smart-contracts
    // Protocol Core - IPAssetRegistry
    IIPAssetRegistry internal IP_ASSET_REGISTRY = IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    // Protocol Core - LicensingModule
    ILicensingModule internal LICENSING_MODULE = ILicensingModule(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);
    // Protocol Core - PILicenseTemplate
    IPILicenseTemplate internal PIL_TEMPLATE = IPILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    // Protocol Core - RoyaltyPolicyLAP
    address internal ROYALTY_POLICY_LAP = 0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;
    // Protocol Core - AccessController
    address internal ACCESS_CONTROLLER = 0xcCF37d0a503Ee1D4C11208672e622ed3DFB2275a;
    // Protocol Core - ModuleRegistry
    address internal MODULE_REGISTRY = 0x022DBAAeA5D8fB31a0Ad793335e39Ced5D631fa5;
    // Revenue Token - MERC20
    MockERC20 internal MERC20 = MockERC20(0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E);

    LicenseCallerWhitelistHook public LICENSE_CALLER_WHITELIST_HOOK;
    uint256 public tokenId;
    address public ipId;
    uint256 public licenseTermsId;

    function setUp() public override {
        super.setUp();

        LICENSE_CALLER_WHITELIST_HOOK = new LicenseCallerWhitelistHook(ACCESS_CONTROLLER, address(IP_ASSET_REGISTRY));

        // Make the registry *think* the hook is registered everywhere in this test
        vm.mockCall(
            MODULE_REGISTRY,
            abi.encodeWithSelector(ModuleRegistry.isRegistered.selector, address(LICENSE_CALLER_WHITELIST_HOOK)),
            abi.encode(true)
        );

        tokenId = mockNft.mint(alice);
        ipId = IP_ASSET_REGISTRY.register(block.chainid, address(mockNft), tokenId);

        licenseTermsId = PIL_TEMPLATE.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 100, // 100 wei minting fee
                commercialRevShare: 0,
                royaltyPolicy: ROYALTY_POLICY_LAP,
                currencyToken: address(MERC20)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 100,
            licensingHook: address(LICENSE_CALLER_WHITELIST_HOOK),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(alice);
        LICENSING_MODULE.attachLicenseTerms(ipId, address(PIL_TEMPLATE), licenseTermsId);
        LICENSING_MODULE.setLicensingConfig(ipId, address(PIL_TEMPLATE), licenseTermsId, licensingConfig);
        vm.stopPrank();
    }

    function test_LicenseCallerWhitelistHook_addToWhitelistSuccess() public {
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        assertTrue(LICENSE_CALLER_WHITELIST_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_LicenseCallerWhitelistHook_revert_addToWhitelistWhenAlreadyWhitelisted() public {
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                LicenseCallerWhitelistHook.LicenseCallerWhitelistHook_AddressAlreadyWhitelisted.selector,
                bob
            )
        );
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_LicenseCallerWhitelistHook_revert_addToWhitelistWhenNoPermission() public {
        vm.expectRevert(); // AccessControlled will revert
        vm.prank(bob); // bob doesn't have permission for alice's IP
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, charlie);
    }

    function test_LicenseCallerWhitelistHook_removeFromWhitelistSuccess() public {
        // First add to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Then remove
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.removeFromWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        assertFalse(LICENSE_CALLER_WHITELIST_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_LicenseCallerWhitelistHook_revert_removeFromWhitelistWhenNotInWhitelist() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LicenseCallerWhitelistHook.LicenseCallerWhitelistHook_AddressNotInWhitelist.selector,
                bob
            )
        );
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.removeFromWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_LicenseCallerWhitelistHook_revert_removeFromWhitelistWhenNoPermission() public {
        // First add to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        vm.expectRevert(); // AccessControlled will revert
        vm.prank(bob); // bob doesn't have permission for alice's IP
        LICENSE_CALLER_WHITELIST_HOOK.removeFromWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_LicenseCallerWhitelistHook_isWhitelistedReturnsFalseByDefault() public {
        assertFalse(LICENSE_CALLER_WHITELIST_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_LicenseCallerWhitelistHook_beforeMintLicenseTokensSuccess() public {
        // Add bob to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob should be able to mint
        uint256 fee = LICENSE_CALLER_WHITELIST_HOOK.beforeMintLicenseTokens(
            bob,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            1,
            bob,
            ""
        );

        assertEq(fee, 100); // minting fee from license terms
    }

    function test_LicenseCallerWhitelistHook_revert_beforeMintLicenseTokensWhenNotWhitelisted() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                LicenseCallerWhitelistHook.LicenseCallerWhitelistHook_AddressNotWhitelisted.selector,
                bob
            )
        );
        LICENSE_CALLER_WHITELIST_HOOK.beforeMintLicenseTokens(
            bob,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            1,
            bob,
            ""
        );
    }

    function test_LicenseCallerWhitelistHook_beforeMintLicenseTokensMultipleTokens() public {
        // Add bob to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob should be able to mint multiple tokens
        uint256 fee = LICENSE_CALLER_WHITELIST_HOOK.beforeMintLicenseTokens(
            bob,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            5,
            bob,
            ""
        );

        assertEq(fee, 500); // 5 * 100 wei minting fee
    }

    function test_LicenseCallerWhitelistHook_whitelistIsolationDifferentLicenses() public {
        // Create a second license terms
        uint256 licenseTermsId2 = PIL_TEMPLATE.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 200,
                commercialRevShare: 0,
                royaltyPolicy: ROYALTY_POLICY_LAP,
                currencyToken: address(MERC20)
            })
        );
        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 200,
            licensingHook: address(LICENSE_CALLER_WHITELIST_HOOK),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(alice);
        LICENSING_MODULE.attachLicenseTerms(ipId, address(PIL_TEMPLATE), licenseTermsId2);
        LICENSING_MODULE.setLicensingConfig(ipId, address(PIL_TEMPLATE), licenseTermsId2, licensingConfig);
        // Add bob to whitelist for first license
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
        vm.stopPrank();

        // Bob should be whitelisted for first license but not second
        assertTrue(LICENSE_CALLER_WHITELIST_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
        assertFalse(LICENSE_CALLER_WHITELIST_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId2, bob));
    }

    function test_LicenseCallerWhitelistHook_beforeMintLicenseTokensToDifferentReceiver() public {
        // Add bob to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob should be able to mint
        uint256 fee = LICENSE_CALLER_WHITELIST_HOOK.beforeMintLicenseTokens(
            bob,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            1,
            alice,
            ""
        );

        assertEq(fee, 100); // minting fee from license terms
    }

    function test_LicenseCallerWhitelistHook_revert_beforeMintLicenseTokensWhenCallerNotWhitelisted() public {
        // Add bob to whitelist
        vm.prank(alice);
        LICENSE_CALLER_WHITELIST_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob should be able to mint
        vm.expectRevert(
            abi.encodeWithSelector(
                LicenseCallerWhitelistHook.LicenseCallerWhitelistHook_AddressNotWhitelisted.selector,
                alice
            )
        );
        LICENSE_CALLER_WHITELIST_HOOK.beforeMintLicenseTokens(
            alice,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            1,
            bob,
            ""
        );
    }
}
