// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CrowdStakeDeployer} from "../src/CrowdStakeDeployer.sol";

import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {AbstractDistributionManager} from "../src/abstract/AbstractDistributionManager.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";
import {PoolNativeYield} from "../src/implementation/pool/PoolNativeYield.sol";
import {AbstractToken} from "../src/abstract/AbstractToken.sol";
import {IStakePool} from "../src/interfaces/IStakePool.sol";

interface IOwnable {
    function owner() external view returns (address);
}

interface IFamilyId {
    function familyId() external view returns (bytes32);
    function lastRegistryUpdateNonce() external view returns (uint256);
}

contract CrowdStakeDeployerTest is Test {
    CrowdStakeDeployer internal deployer;

    address internal constant WXDAI = address(0x11dA1);
    address internal constant SXDAI = address(0x5DA1);
    address internal constant OWNER = address(0xABCD);
    address internal constant FOUNDER = address(0xF00D);

    string internal constant TOKEN_IMG = "ipfs://bafyTokenImage";
    string internal constant BANNER_IMG = "https://example.org/banner.png";

    function setUp() public {
        CrowdStakeFactory factory = new CrowdStakeFactory(address(this));

        address cycleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), address(this)));
        address registryBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), address(this)));
        address votingRegistryBeacon =
            address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), address(this)));
        address tokenBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(WXDAI, SXDAI)), address(this)));
        address poolBeacon = address(new UpgradeableBeacon(address(new PoolNativeYield(WXDAI, SXDAI)), address(this)));
        address distBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), address(this)));
        address multiDistBeacon =
            address(new UpgradeableBeacon(address(new MultiStrategyDistributionManager()), address(this)));
        address stratBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), address(this)));
        address equalStratBeacon =
            address(new UpgradeableBeacon(address(new EqualDistributionStrategy()), address(this)));
        address votingBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), address(this)));

        address[] memory beacons = new address[](10);
        beacons[0] = cycleBeacon;
        beacons[1] = registryBeacon;
        beacons[2] = votingRegistryBeacon;
        beacons[3] = tokenBeacon;
        beacons[4] = poolBeacon;
        beacons[5] = distBeacon;
        beacons[6] = multiDistBeacon;
        beacons[7] = stratBeacon;
        beacons[8] = equalStratBeacon;
        beacons[9] = votingBeacon;
        factory.allowlistBeacons(beacons);

        deployer = new CrowdStakeDeployer(
            address(factory),
            cycleBeacon,
            registryBeacon,
            votingRegistryBeacon,
            tokenBeacon,
            poolBeacon,
            distBeacon,
            multiDistBeacon,
            stratBeacon,
            equalStratBeacon,
            votingBeacon
        );
    }

    function _adminParams(bytes32 salt) internal pure returns (CrowdStakeDeployer.Params memory) {
        return CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Admin Stake",
            tokenSymbol: "ADMN",
            maxVotingPoints: 10_000,
            salt: salt,
            registryKind: 0,
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            distributionKind: 0, // proportional
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: false,
            issueToken: true // token mode (these shared helpers keep asserting classic token behavior)
        });
    }

    function _votingParams(bytes32 salt, address[] memory founders, uint256 expiry)
        internal
        pure
        returns (CrowdStakeDeployer.Params memory)
    {
        return CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Demo Stake",
            tokenSymbol: "DEMO",
            maxVotingPoints: 10_000,
            salt: salt,
            registryKind: 1,
            initialRecipients: founders,
            proposalExpiry: expiry,
            distributionKind: 0, // proportional
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: false,
            issueToken: true // token mode (these shared helpers keep asserting classic token behavior)
        });
    }

    function test_DeploysAdminInstance() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("admin-1"));
        assertEq(IOwnable(i.registry).owner(), OWNER, "registry owner");
        assertEq(AdminRecipientRegistry(i.registry).getRecipientCount(), 0, "admin starts empty");
        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer wired");
        assertEq(AbstractCycleModule(i.cycleModule).getCurrentCycle(), 1, "cycle #1");
    }

    // ---- Pool mode (issueToken toggle) ----

    /// @dev supportsPoolMode() is the on-chain capability probe the wizard gates the toggle on.
    function test_SupportsPoolModeProbe() public view {
        assertTrue(deployer.supportsPoolMode(), "deployer advertises pool-mode support");
    }

    /// @dev issueToken=false (the zero-value default) deploys a pool, not a token, and wires the
    ///      DM's yieldModule = pool while baseToken = the underlying asset.
    function test_DeploysPoolInstance() public {
        CrowdStakeDeployer.Params memory p = _adminParams("pool-1");
        p.issueToken = false; // POOL MODE
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        assertTrue(IStakePool(i.token).isPool(), "instance.token is a pool");
        assertEq(IStakePool(i.token).yieldClaimer(), i.distributionManager, "pool yieldClaimer wired");
        // DM distributes the underlying (WXDAI here), reads yield from the pool.
        assertEq(address(AbstractDistributionManager(i.distributionManager).baseToken()), WXDAI, "baseToken=underlying");
        assertEq(
            address(AbstractDistributionManager(i.distributionManager).yieldModule()), i.token, "yieldModule=the pool"
        );
        assertEq(IOwnable(i.token).owner(), OWNER, "pool handed to final owner");
    }

    /// @dev The default Params.issueToken zero-value is pool mode.
    function test_DefaultIssueTokenZeroValueIsPoolMode() public {
        // Build params WITHOUT touching issueToken → it defaults to false → pool.
        CrowdStakeDeployer.Params memory p = CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Default",
            tokenSymbol: "DFLT",
            maxVotingPoints: 10_000,
            salt: "default-mode",
            registryKind: 0,
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            distributionKind: 0,
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: false,
            issueToken: false
        });
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);
        assertTrue(IStakePool(i.token).isPool(), "zero-value issueToken => pool mode");
    }

    // ---- Review S1: the yield module is fixed at DM init; no post-init setter exists ----

    /// @dev The removed owner-only `setYieldModule(address)` (selector 0xbe3df19f) is gone from the
    ///      shared beacon-proxied DM base. A call to that selector hits no function and, absent a
    ///      payable fallback, reverts — while the yieldModule wired at init is untouched. This is the
    ///      core S1 mitigation: no live token instance's owner can ever be handed a distribution-
    ///      bricking lever if an existing DM beacon is pointed at this implementation.
    function test_S1_SetYieldModuleSelectorNoLongerExists() public {
        CrowdStakeDeployer.Params memory p = _adminParams("s1-gone");
        p.issueToken = false; // pool mode: yieldModule = pool, baseToken = underlying
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        address dm = i.distributionManager;
        address before = address(AbstractDistributionManager(dm).yieldModule());
        assertEq(before, i.token, "precondition: yieldModule = pool");

        // Old setter selector, as any caller (even a future owner) would encode it.
        bytes memory oldSetter = abi.encodeWithSignature("setYieldModule(address)", address(0xDEAD));
        assertEq(bytes4(oldSetter), bytes4(0xbe3df19f), "old selector pinned");

        // As the final owner: the call finds no such function and reverts (no fallback).
        vm.prank(OWNER);
        (bool ok,) = dm.call(oldSetter);
        assertFalse(ok, "setYieldModule(address) no longer exists -> reverts");

        // And the yield module is exactly what init fixed it to — no state changed.
        assertEq(address(AbstractDistributionManager(dm).yieldModule()), before, "yieldModule unchanged");
    }

    /// @dev End-to-end: in pool mode the yield module is fixed at DM initialization and the owner
    ///      cannot repoint it by ANY path (there is no setter, and re-initialize reverts). Proves the
    ///      pool wiring works purely through the initializer, not a post-deploy owner call.
    function test_S1_PoolModeYieldModuleFixedAtInit_OwnerCannotRepoint() public {
        CrowdStakeDeployer.Params memory p = _adminParams("s1-fixed");
        p.issueToken = false; // POOL MODE
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        // The pool wiring was set purely at init: yieldModule = pool, baseToken = underlying.
        assertEq(address(AbstractDistributionManager(i.distributionManager).yieldModule()), i.token, "init: pool");
        assertEq(address(AbstractDistributionManager(i.distributionManager).baseToken()), WXDAI, "init: underlying");
        assertEq(IOwnable(i.distributionManager).owner(), OWNER, "owner is final owner, not deployer");

        // The owner cannot re-run initialize to repoint the yield module (initializer is spent).
        vm.prank(OWNER);
        (bool reinitOk,) = i.distributionManager
            .call(
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address,address,address)",
                    i.cycleModule,
                    i.registry,
                    WXDAI,
                    i.votingModule,
                    address(0xDEAD), // attacker-chosen yield module
                    address(0),
                    OWNER
                )
            );
        assertFalse(reinitOk, "re-initialize reverts (InvalidInitialization)");

        // Yield module is still the pool the deployer fixed at init.
        assertEq(address(AbstractDistributionManager(i.distributionManager).yieldModule()), i.token, "still the pool");
    }

    // ---- Backward-compatible legacy deploy (pinned IPFS frontends) ----

    /// @dev The pre-pool-mode 13-field selector (0xfd759538) still deploys a classic TOKEN instance.
    ///      Encoded as raw legacy calldata to prove a frozen frontend's bytes still work.
    function test_LegacySelectorDeploysClassicToken() public {
        CrowdStakeDeployer.LegacyParams memory legacy = CrowdStakeDeployer.LegacyParams({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Legacy Stake",
            tokenSymbol: "LEGA",
            maxVotingPoints: 10_000,
            salt: "legacy-1",
            registryKind: 0,
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            distributionKind: 0,
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: false
        });

        // Raw calldata with the OLD selector, as a pinned frontend would ABI-encode it.
        bytes memory callData = abi.encodeWithSelector(bytes4(0xfd759538), legacy);
        (bool ok, bytes memory ret) = address(deployer).call(callData);
        assertTrue(ok, "legacy-selector call succeeds against the new deployer");

        CrowdStakeDeployer.Instance memory i = abi.decode(ret, (CrowdStakeDeployer.Instance));
        // Classic token: it is NOT a pool (no isPool()), and yieldModule == baseToken == token.
        (bool isPoolOk,) = i.token.call(abi.encodeWithSignature("isPool()"));
        assertFalse(isPoolOk, "legacy deploy yields a classic token, not a pool");
        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "token yieldClaimer wired");
        assertEq(address(AbstractDistributionManager(i.distributionManager).baseToken()), i.token, "baseToken == token");
    }

    /// @dev The legacy overload must scope the family to the ORIGINAL caller (msg.sender), not the
    ///      deployer — proving it delegates through the internal body, not `this.deploy`.
    function test_LegacyCrossChain_ScopedToOriginalCaller() public {
        CrowdStakeDeployer.LegacyParams memory legacy = CrowdStakeDeployer.LegacyParams({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Legacy XChain",
            tokenSymbol: "LGXC",
            maxVotingPoints: 10_000,
            salt: "legacy-xchain",
            registryKind: 0,
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            distributionKind: 0,
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: true
        });
        bytes32 familyId = deployer.familyIdOf(FOUNDER, "legacy-xchain", "Legacy XChain", "LGXC", 10_000, 0, 0);

        vm.prank(FOUNDER);
        deployer.deploy(legacy);

        // The sibling is recorded under FOUNDER's familyId, not the deployer's.
        (,,,,,,, address votingModule) = deployer.familyInstances(familyId);
        assertTrue(votingModule != address(0), "family scoped to the original caller (FOUNDER)");
        assertEq(BasisPointsVotingModule(votingModule).familyId(), familyId, "module familyId matches caller-scoped id");
    }

    function test_DeploysVotingInstance() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_votingParams("voting-1", founders, 7 days));

        VotingRecipientRegistry reg = VotingRecipientRegistry(i.registry);
        assertEq(reg.owner(), OWNER, "registry owner");
        assertEq(reg.proposalExpiry(), 7 days, "proposal expiry");
        assertEq(reg.getRecipientCount(), 1, "one founding recipient");
        assertTrue(reg.isRecipient(FOUNDER), "founder is a recipient");

        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer wired");
        assertEq(AbstractCycleModule(i.cycleModule).distributionManager(), i.distributionManager, "cycle->distMgr");
    }

    function test_VotingFounderCanProposeExecuteProcess() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_votingParams("voting-2", founders, 7 days));
        VotingRecipientRegistry reg = VotingRecipientRegistry(i.registry);

        vm.prank(FOUNDER);
        uint256 pid = reg.proposeAddition(address(0xBEEF));
        reg.executeProposal(pid);
        reg.processQueue();
        assertEq(reg.getRecipientCount(), 2, "candidate added by unanimous (n=1) vote");
        assertTrue(reg.isRecipient(address(0xBEEF)), "new recipient active");
    }

    // ---- Distribution strategy kinds ----

    function test_DeploysEqualDistribution() public {
        CrowdStakeDeployer.Params memory p = _adminParams("equal-1");
        p.distributionKind = 1; // equal
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        MultiStrategyDistributionManager dm = MultiStrategyDistributionManager(i.distributionManager);
        assertEq(dm.getStrategyCount(), 1, "single equal strategy");
        assertEq(address(dm.strategies(0)), i.distributionStrategy, "equal strat wired as strategy[0]");
        assertEq(i.secondaryDistributionStrategy, address(0), "no secondary for pure equal");
        assertEq(IOwnable(i.distributionManager).owner(), OWNER, "manager owner");
        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer wired");
    }

    function test_DeploysSplitDistribution() public {
        CrowdStakeDeployer.Params memory p = _adminParams("split-1");
        p.distributionKind = 2; // split (half votes / half equal)
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        MultiStrategyDistributionManager dm = MultiStrategyDistributionManager(i.distributionManager);
        assertEq(dm.getStrategyCount(), 2, "voting + equal strategies");
        assertEq(address(dm.strategies(0)), i.distributionStrategy, "voting strat is primary/strategy[0]");
        assertEq(address(dm.strategies(1)), i.secondaryDistributionStrategy, "equal strat is secondary/strategy[1]");
        assertTrue(i.distributionStrategy != address(0) && i.secondaryDistributionStrategy != address(0), "both set");
        assertEq(IOwnable(i.distributionManager).owner(), OWNER, "manager owner");
    }

    function test_RevertWhen_InvalidDistributionKind() public {
        CrowdStakeDeployer.Params memory p = _adminParams("bad-dist");
        p.distributionKind = 3; // out of range
        vm.expectRevert(CrowdStakeDeployer.InvalidDistributionKind.selector);
        deployer.deploy(p);
    }

    // ---- Instance metadata ----

    function test_DeploySeedsMetadata() public {
        CrowdStakeDeployer.Params memory p = _adminParams("meta-1");
        p.tokenImageURI = TOKEN_IMG;
        p.bannerImageURI = BANNER_IMG;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        AbstractDistributionManager dm = AbstractDistributionManager(i.distributionManager);
        assertEq(dm.tokenImageURI(), TOKEN_IMG, "token image seeded");
        assertEq(dm.bannerImageURI(), BANNER_IMG, "banner image seeded");
        assertGt(bytes(dm.contractURI()).length, 0, "contractURI assembled");
        // The token pulls contractURI from its distribution manager (the claimer).
        assertEq(AbstractToken(i.token).contractURI(), dm.contractURI(), "token pulls contractURI from dist manager");
    }

    function test_OwnerCanUpdateMetadata() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("meta-2"));
        AbstractDistributionManager dm = AbstractDistributionManager(i.distributionManager);
        assertEq(dm.tokenImageURI(), "", "starts empty");

        vm.prank(OWNER);
        dm.setInstanceMetadata(TOKEN_IMG, BANNER_IMG);
        assertEq(dm.tokenImageURI(), TOKEN_IMG, "owner updated token image");
        assertEq(dm.bannerImageURI(), BANNER_IMG, "owner updated banner");
    }

    function test_RevertWhen_NonOwnerSetsMetadata() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("meta-3"));
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        AbstractDistributionManager(i.distributionManager).setInstanceMetadata(TOKEN_IMG, BANNER_IMG);
    }

    // ---- Guards ----

    function test_RevertWhen_VotingEmptyInitialRecipients() public {
        vm.expectRevert(CrowdStakeDeployer.EmptyInitialRecipients.selector);
        deployer.deploy(_votingParams("bad-1", new address[](0), 7 days));
    }

    function test_RevertWhen_VotingZeroProposalExpiry() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        vm.expectRevert(CrowdStakeDeployer.ZeroProposalExpiry.selector);
        deployer.deploy(_votingParams("bad-2", founders, 0));
    }

    function test_RevertWhen_OwnerIsZero() public {
        CrowdStakeDeployer.Params memory p = _adminParams("z");
        p.owner = address(0);
        vm.expectRevert(CrowdStakeDeployer.ZeroOwner.selector);
        deployer.deploy(p);
    }

    // ---- Cross-chain family ----

    /// @dev familyIdOf must exactly mirror the pure derivation (protocol tag + config commit).
    function test_FamilyIdOf_MirrorsDerivation() public view {
        CrowdStakeDeployer.Params memory p = _adminParams("fam-id");
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("crowdstake.family.v2"),
                FOUNDER,
                p.salt,
                keccak256(bytes(p.tokenName)),
                keccak256(bytes(p.tokenSymbol)),
                p.maxVotingPoints,
                p.registryKind,
                p.distributionKind
            )
        );
        assertEq(
            deployer.familyIdOf(
                FOUNDER, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
            ),
            expected,
            "familyIdOf derivation"
        );

        // Config-committing: a different symbol yields a different family (no accidental merge).
        assertTrue(
            deployer.familyIdOf(
                FOUNDER, p.salt, p.tokenName, "OTHER", p.maxVotingPoints, p.registryKind, p.distributionKind
            ) != expected,
            "symbol change -> different family"
        );
        // Creator-scoped: a different creator yields a different family.
        assertTrue(
            deployer.familyIdOf(
                OWNER, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
            ) != expected,
            "creator change -> different family"
        );
    }

    /// @dev A cross-chain deploy wires the familyId into the voting module, records the sibling,
    ///      and emits FamilyDeployed alongside SystemDeployed.
    function test_CrossChainDeploy_WiresFamilyAndRecordsSibling() public {
        CrowdStakeDeployer.Params memory p = _adminParams("fam-1");
        p.crossChain = true;

        bytes32 familyId = deployer.familyIdOf(
            FOUNDER, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
        );

        vm.expectEmit(true, true, true, false);
        emit CrowdStakeDeployer.FamilyDeployed(familyId, FOUNDER, OWNER);
        vm.prank(FOUNDER);
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        // The voting module knows its family and gates on castCrossChainVote.
        assertEq(BasisPointsVotingModule(i.votingModule).familyId(), familyId, "familyId wired into module");

        // familyInstances round-trip returns the full 8-address tuple.
        (
            address cycleModule,
            address registry,
            address token,
            address votingPowerStrategy,
            address distributionManager,
            address distributionStrategy,
            address secondaryDistributionStrategy,
            address votingModule
        ) = deployer.familyInstances(familyId);
        assertEq(cycleModule, i.cycleModule, "sibling cycleModule");
        assertEq(registry, i.registry, "sibling registry");
        assertEq(token, i.token, "sibling token");
        assertEq(votingPowerStrategy, i.votingPowerStrategy, "sibling votingPowerStrategy");
        assertEq(distributionManager, i.distributionManager, "sibling distributionManager");
        assertEq(distributionStrategy, i.distributionStrategy, "sibling distributionStrategy");
        assertEq(secondaryDistributionStrategy, i.secondaryDistributionStrategy, "sibling secondary");
        assertEq(votingModule, i.votingModule, "sibling votingModule");
    }

    /// @dev A classic deploy leaves familyInstances empty and the module familyId zero.
    function test_ClassicDeploy_LeavesFamilyUnset() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("classic-fam"));
        assertEq(BasisPointsVotingModule(i.votingModule).familyId(), bytes32(0), "classic module familyId 0");
    }

    /// @dev The same creator+config can only seed a family once per chain.
    function test_RevertWhen_FamilyAlreadyDeployed() public {
        CrowdStakeDeployer.Params memory p = _adminParams("fam-dup");
        p.crossChain = true;

        vm.prank(FOUNDER);
        deployer.deploy(p);

        vm.prank(FOUNDER);
        vm.expectRevert(CrowdStakeDeployer.FamilyAlreadyDeployed.selector);
        deployer.deploy(p);
    }

    // ---- Registry familyId wiring ----

    /// @dev An admin cross-chain deploy uses the base familyIdOf (byte-identical to today) and
    ///      wires it into the registry, which now exposes familyId() + lastRegistryUpdateNonce().
    function test_CrossChainAdminDeploy_WiresRegistryFamilyId() public {
        CrowdStakeDeployer.Params memory p = _adminParams("xchain-admin");
        p.crossChain = true;
        bytes32 familyId = deployer.familyIdOf(
            FOUNDER, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
        );

        vm.prank(FOUNDER);
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        assertEq(IFamilyId(i.registry).familyId(), familyId, "registry familyId = base familyIdOf");
        assertEq(IFamilyId(i.registry).lastRegistryUpdateNonce(), 0, "fresh update nonce");
        assertEq(BasisPointsVotingModule(i.votingModule).familyId(), familyId, "module familyId matches registry");
    }

    /// @dev A classic admin deploy leaves the registry familyId zero.
    function test_ClassicAdminDeploy_RegistryFamilyIdZero() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("classic-admin"));
        assertEq(IFamilyId(i.registry).familyId(), bytes32(0), "classic registry familyId 0");
    }

    // ---- votingFamilyIdOf: commits founders + expiry ----

    /// @dev votingFamilyIdOf folds the base familyIdOf with the founding cohort + expiry.
    function test_VotingFamilyIdOf_CommitsFoundersAndExpiry() public view {
        address[] memory founders = new address[](2);
        founders[0] = address(0x1111);
        founders[1] = address(0x2222);
        bytes32 salt = "vfid";

        bytes32 base = deployer.familyIdOf(FOUNDER, salt, "Demo Stake", "DEMO", 10_000, 1, 0);
        bytes32 expected = keccak256(abi.encode(base, keccak256(abi.encodePacked(founders)), uint256(7 days)));

        assertEq(
            deployer.votingFamilyIdOf(FOUNDER, salt, "Demo Stake", "DEMO", 10_000, 0, founders, 7 days),
            expected,
            "votingFamilyIdOf derivation"
        );

        // Different founders → different family (the critical drift-prevention property).
        address[] memory other = new address[](2);
        other[0] = address(0x1111);
        other[1] = address(0x3333);
        assertTrue(
            deployer.votingFamilyIdOf(FOUNDER, salt, "Demo Stake", "DEMO", 10_000, 0, other, 7 days) != expected,
            "founder change -> different family"
        );

        // Different expiry → different family.
        assertTrue(
            deployer.votingFamilyIdOf(FOUNDER, salt, "Demo Stake", "DEMO", 10_000, 0, founders, 8 days) != expected,
            "expiry change -> different family"
        );
    }

    /// @dev A voting cross-chain deploy wires votingFamilyIdOf (not the base id) into both the
    ///      registry and voting module, and records the sibling under that id.
    function test_CrossChainVotingDeploy_WiresVotingFamilyId() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        CrowdStakeDeployer.Params memory p = _votingParams("xchain-voting", founders, 7 days);
        p.crossChain = true;

        bytes32 votingFamilyId = deployer.votingFamilyIdOf(
            FOUNDER,
            p.salt,
            p.tokenName,
            p.tokenSymbol,
            p.maxVotingPoints,
            p.distributionKind,
            founders,
            p.proposalExpiry
        );
        bytes32 baseFamilyId = deployer.familyIdOf(
            FOUNDER, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
        );
        assertTrue(votingFamilyId != baseFamilyId, "voting-kind id diverges from base id");

        vm.prank(FOUNDER);
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        assertEq(IFamilyId(i.registry).familyId(), votingFamilyId, "registry uses votingFamilyIdOf");
        assertEq(BasisPointsVotingModule(i.votingModule).familyId(), votingFamilyId, "module uses votingFamilyIdOf");

        // Sibling recorded under the voting-kind id.
        (,,,,,,, address votingModule) = deployer.familyInstances(votingFamilyId);
        assertEq(votingModule, i.votingModule, "sibling recorded under voting-kind id");
    }
}
