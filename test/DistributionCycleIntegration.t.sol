// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {IDistributionStrategy} from "../src/interfaces/IDistributionStrategy.sol";
import {IVotingModule} from "../src/interfaces/IVotingModule.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";
import {IYieldModule} from "../src/interfaces/IYieldModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Integration test verifying claimAndDistribute() atomically advances the cycle
contract DistributionCycleIntegrationTest is Test {
    CycleModule public cycleModule;
    BaseDistributionManager public baseManager;

    address public owner = address(this);
    uint256 constant CYCLE_LENGTH = 100;
    uint256 constant START_BLOCK = 1000;

    // Mock addresses
    address public mockRegistry = address(0x1111);
    address public mockBaseToken = address(0x2222);
    address public mockVotingModule = address(0x3333);
    address public mockStrategy = address(0x4444);

    function setUp() public {
        vm.roll(START_BLOCK);

        // Deploy cycle module
        CycleModule cycleImpl = new CycleModule();
        bytes memory cycleInit =
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE_LENGTH, owner);
        cycleModule = CycleModule(address(new ERC1967Proxy(address(cycleImpl), cycleInit)));

        // Deploy base distribution manager
        BaseDistributionManager managerImpl = new BaseDistributionManager();

        // Set up mocks for all dependencies
        vm.etch(mockRegistry, hex"00");
        vm.etch(mockBaseToken, hex"00");
        vm.etch(mockVotingModule, hex"00");
        vm.etch(mockStrategy, hex"00");

        bytes memory managerInit = abi.encodeWithSelector(
            BaseDistributionManager.initialize.selector,
            address(cycleModule),
            mockRegistry,
            mockBaseToken,
            mockVotingModule,
            mockStrategy,
            owner
        );
        baseManager = BaseDistributionManager(address(new ERC1967Proxy(address(managerImpl), managerInit)));

        // Wire distribution manager into cycle module
        cycleModule.setDistributionManager(address(baseManager));
    }

    function testClaimAndDistributeAdvancesCycle() public {
        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleModule.getCurrentCycle(), 1);
        assertTrue(cycleModule.isCycleComplete());

        // Mock all required calls for claimAndDistribute
        // isDistributionReady checks
        vm.mockCall(
            mockVotingModule,
            abi.encodeWithSelector(IVotingModule.getCurrentVotingDistribution.selector),
            abi.encode(new uint256[](0))
        );
        // Need non-zero votes - mock a distribution with votes
        uint256[] memory dist = new uint256[](1);
        dist[0] = 100;
        vm.mockCall(
            mockVotingModule,
            abi.encodeWithSelector(IVotingModule.getCurrentVotingDistribution.selector),
            abi.encode(dist)
        );
        vm.mockCall(
            mockRegistry,
            abi.encodeWithSelector(IRecipientRegistry.getRecipientCount.selector),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            mockBaseToken,
            abi.encodeWithSelector(IYieldModule.yieldAccrued.selector),
            abi.encode(uint256(1000))
        );
        vm.mockCall(
            mockBaseToken,
            abi.encodeWithSelector(IYieldModule.claimYield.selector, uint256(1000), address(baseManager)),
            ""
        );
        vm.mockCall(
            mockBaseToken,
            abi.encodeWithSelector(IERC20.transfer.selector, mockStrategy, uint256(1000)),
            abi.encode(true)
        );
        vm.mockCall(
            mockStrategy,
            abi.encodeWithSelector(IDistributionStrategy.distribute.selector, uint256(1000)),
            ""
        );

        // Execute
        baseManager.claimAndDistribute();

        // Verify cycle was advanced
        assertEq(cycleModule.getCurrentCycle(), 2);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK + CYCLE_LENGTH);
        assertFalse(cycleModule.isCycleComplete());
    }

    function testIsDistributionReadyReturnsFalseWhenNotWired() public {
        // Deploy a fresh manager NOT wired as distribution manager on the cycle module
        BaseDistributionManager managerImpl = new BaseDistributionManager();

        // Create a fresh cycle module with no distribution manager set
        CycleModule freshCycleImpl = new CycleModule();
        bytes memory freshCycleInit =
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE_LENGTH, owner);
        CycleModule freshCycle = CycleModule(address(new ERC1967Proxy(address(freshCycleImpl), freshCycleInit)));

        bytes memory managerInit = abi.encodeWithSelector(
            BaseDistributionManager.initialize.selector,
            address(freshCycle),
            mockRegistry,
            mockBaseToken,
            mockVotingModule,
            mockStrategy,
            owner
        );
        BaseDistributionManager unwiredManager =
            BaseDistributionManager(address(new ERC1967Proxy(address(managerImpl), managerInit)));

        vm.roll(START_BLOCK + CYCLE_LENGTH);

        // Should return false because this manager isn't the cycle module's distribution manager
        assertFalse(unwiredManager.isDistributionReady());
    }
}
