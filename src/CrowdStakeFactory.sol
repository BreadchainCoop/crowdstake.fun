// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DefaultYieldClaimer} from "./implementation/DefaultYieldClaimer.sol";
import {TokenBasedVotingPower} from "./implementation/strategies/TokenBasedVotingPower.sol";
import {TimeWeightedVotingPower} from "./implementation/TimeWeightedVotingPower.sol";
import {ChainlinkAutomation} from "./implementation/automation/ChainlinkAutomation.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract CrowdStakeFactory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error AlreadyWhitelistedBeacon();
    error NotBeacon();
    error NotWhitelistedBeacon();
    error Create2Failed();

    event WhitelistBeacons(address[] beacons);
    event BlacklistBeacons(address[] beacons);
    event CreateToken(address token, address beacon, bytes payload);
    event CreateModule(address module, address beacon, bytes payload);
    event CreateYieldDistributor(
        address yieldClaimer, address token, address[] initialRecipients, uint256 percentVoted, address owner
    );
    event CreateTokenBasedVotingPower(address votingPower, address votingToken);
    event CreateTimeWeightedVotingPower(address votingPower, address votingToken, address cycleModule);
    event CreateChainlinkAutomation(address automation, address distributionManager);

    EnumerableSet.AddressSet internal _beacons;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    // ============ Beacon-Based Deployment (Tokens & Modules) ============

    function createToken(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address token) {
        if (!_beacons.contains(beacon_)) {
            revert NotWhitelistedBeacon();
        }

        bytes32 salt = _computeSalt(salt_);
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (token == address(0)) revert Create2Failed();

        emit CreateToken(token, beacon_, payload_);
    }

    function createModule(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address module) {
        if (!_beacons.contains(beacon_)) {
            revert NotWhitelistedBeacon();
        }

        bytes32 salt = _computeSalt(salt_);
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        assembly {
            module := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (module == address(0)) revert Create2Failed();

        emit CreateModule(module, beacon_, payload_);
    }

    // ============ Constructor-Based Deployment ============

    function createDefaultYieldClaimer(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = _computeSalt(salt_);
        assembly {
            yieldClaimer := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (yieldClaimer == address(0)) revert Create2Failed();

        emit CreateYieldDistributor(yieldClaimer, token_, initialRecipients_, percentVoted_, owner_);
    }

    function createTokenBasedVotingPower(address votingToken_, bytes32 salt_) external returns (address votingPower) {
        bytes memory bytecode = abi.encodePacked(type(TokenBasedVotingPower).creationCode, abi.encode(votingToken_));
        bytes32 salt = _computeSalt(salt_);
        assembly {
            votingPower := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (votingPower == address(0)) revert Create2Failed();

        emit CreateTokenBasedVotingPower(votingPower, votingToken_);
    }

    function createTimeWeightedVotingPower(address votingToken_, address cycleModule_, bytes32 salt_)
        external
        returns (address votingPower)
    {
        bytes memory bytecode = abi.encodePacked(
            type(TimeWeightedVotingPower).creationCode, abi.encode(votingToken_, cycleModule_)
        );
        bytes32 salt = _computeSalt(salt_);
        assembly {
            votingPower := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (votingPower == address(0)) revert Create2Failed();

        emit CreateTimeWeightedVotingPower(votingPower, votingToken_, cycleModule_);
    }

    function createChainlinkAutomation(address distributionManager_, bytes32 salt_)
        external
        returns (address automation)
    {
        bytes memory bytecode =
            abi.encodePacked(type(ChainlinkAutomation).creationCode, abi.encode(distributionManager_));
        bytes32 salt = _computeSalt(salt_);
        assembly {
            automation := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (automation == address(0)) revert Create2Failed();

        emit CreateChainlinkAutomation(automation, distributionManager_);
    }

    // ============ Beacon Management ============

    function whitelistBeacons(address[] calldata beacons_) external onlyOwner {
        uint256 length = beacons_.length;

        for (uint256 i; i < length; i++) {
            address beacon = beacons_[i];

            if (beacon.code.length == 0) revert NotBeacon();
            if (_beacons.contains(beacon)) {
                revert AlreadyWhitelistedBeacon();
            }

            _beacons.add(beacon);
        }

        emit WhitelistBeacons(beacons_);
    }

    function blacklistBeacons(address[] calldata beacons_) external onlyOwner {
        uint256 length = beacons_.length;

        for (uint256 i; i < length; i++) {
            address beacon = beacons_[i];

            if (!_beacons.contains(beacon)) {
                revert NotWhitelistedBeacon();
            }

            _beacons.remove(beacon);
        }

        emit BlacklistBeacons(beacons_);
    }

    function beacons() external view returns (address[] memory) {
        return _beacons.values();
    }

    function beaconsContains(address beacon_) external view returns (bool isContained) {
        return _beacons.contains(beacon_);
    }

    // ============ Address Pre-Computation ============

    function computeTokenAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        external
        view
        returns (address token)
    {
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        bytes32 salt = _computeSaltView(salt_);
        token = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeModuleAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        external
        view
        returns (address module)
    {
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        bytes32 salt = _computeSaltView(salt_);
        module = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeClaimerAddress(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external view returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = _computeSaltView(salt_);
        yieldClaimer = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeTokenBasedVotingPowerAddress(address votingToken_, bytes32 salt_)
        external
        view
        returns (address votingPower)
    {
        bytes memory bytecode = abi.encodePacked(type(TokenBasedVotingPower).creationCode, abi.encode(votingToken_));
        bytes32 salt = _computeSaltView(salt_);
        votingPower = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeTimeWeightedVotingPowerAddress(address votingToken_, address cycleModule_, bytes32 salt_)
        external
        view
        returns (address votingPower)
    {
        bytes memory bytecode = abi.encodePacked(
            type(TimeWeightedVotingPower).creationCode, abi.encode(votingToken_, cycleModule_)
        );
        bytes32 salt = _computeSaltView(salt_);
        votingPower = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeChainlinkAutomationAddress(address distributionManager_, bytes32 salt_)
        external
        view
        returns (address automation)
    {
        bytes memory bytecode =
            abi.encodePacked(type(ChainlinkAutomation).creationCode, abi.encode(distributionManager_));
        bytes32 salt = _computeSaltView(salt_);
        automation = _getCreate2Address(salt, keccak256(bytecode));
    }

    // ============ Internal Helpers ============

    function _computeSalt(bytes32 salt_) internal view returns (bytes32 salt) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), salt_)
            salt := keccak256(ptr, 0x40)
        }
    }

    function _computeSaltView(bytes32 salt_) internal view returns (bytes32 salt) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), salt_)
            salt := keccak256(ptr, 0x40)
        }
    }

    function _getBeaconProxyInitCode(address beacon_, bytes calldata payload_) internal pure returns (bytes memory) {
        return abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon_, payload_));
    }

    function _getYieldDistributorInitCode(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(DefaultYieldClaimer).creationCode, abi.encode(token_, initialRecipients_, percentVoted_, owner_)
        );
    }

    function _getCreate2Address(bytes32 salt_, bytes32 bytecodeHash_) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt_, bytecodeHash_)))));
    }
}
