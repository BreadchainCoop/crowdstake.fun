// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DefaultYieldClaimer} from "./implementation/DefaultYieldClaimer.sol";

contract CrowdStakeFactory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error AlreadyAllowlistedBeacon();
    error NotBeacon();
    error NotAllowlistedBeacon();
    error Create2Failed();

    event AllowlistBeacons(address[] beacons);
    event DenylistBeacons(address[] beacons);
    event CreateToken(address token, address beacon, bytes payload);
    event CreateModule(address module, address beacon, bytes payload);
    event CreateYieldDistributor(
        address yieldClaimer, address token, address[] initialRecipients, uint256 percentVoted, address owner
    );

    EnumerableSet.AddressSet internal _beacons;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /// @notice Creates a beacon proxy for a token (legacy entrypoint, delegates to create)
    function createToken(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address token) {
        token = _createBeaconProxy(beacon_, payload_, salt_);
        emit CreateToken(token, beacon_, payload_);
    }

    /// @notice Creates a beacon proxy for any module type
    function create(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address module) {
        module = _createBeaconProxy(beacon_, payload_, salt_);
        emit CreateModule(module, beacon_, payload_);
    }

    /// @notice Computes the deterministic address for a beacon proxy deployment
    function computeAddress(address beacon_, bytes calldata payload_, bytes32 salt_) external view returns (address) {
        return _computeBeaconProxyAddress(beacon_, payload_, salt_);
    }

    /// @notice Computes the deterministic address for a token (legacy entrypoint, delegates to computeAddress)
    function computeTokenAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        external
        view
        returns (address)
    {
        return _computeBeaconProxyAddress(beacon_, payload_, salt_);
    }

    function createDefaultYieldClaimer(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = _deriveSalt(salt_);
        assembly {
            yieldClaimer := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (yieldClaimer == address(0)) revert Create2Failed();

        emit CreateYieldDistributor(yieldClaimer, token_, initialRecipients_, percentVoted_, owner_);
    }

    function allowlistBeacons(address[] calldata beacons_) external onlyOwner {
        uint256 length = beacons_.length;

        for (uint256 i; i < length; i++) {
            address beacon = beacons_[i];

            if (beacon.code.length == 0) revert NotBeacon();
            if (_beacons.contains(beacon)) {
                revert AlreadyAllowlistedBeacon();
            }

            _beacons.add(beacon);
        }

        emit AllowlistBeacons(beacons_);
    }

    function denylistBeacons(address[] calldata beacons_) external onlyOwner {
        uint256 length = beacons_.length;

        for (uint256 i; i < length; i++) {
            address beacon = beacons_[i];

            if (!_beacons.contains(beacon)) {
                revert NotAllowlistedBeacon();
            }

            _beacons.remove(beacon);
        }

        emit DenylistBeacons(beacons_);
    }

    function beacons() external view returns (address[] memory) {
        return _beacons.values();
    }

    function beaconsContains(address beacon_) external view returns (bool isContained) {
        return _beacons.contains(beacon_);
    }

    function computeClaimerAddress(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external view returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = _deriveSalt(salt_);
        yieldClaimer = _getCreate2Address(salt, keccak256(bytecode));
    }

    // ============ Internal Helpers ============

    function _createBeaconProxy(address beacon_, bytes calldata payload_, bytes32 salt_)
        internal
        returns (address proxy)
    {
        if (!_beacons.contains(beacon_)) {
            revert NotAllowlistedBeacon();
        }

        bytes32 salt = _deriveSalt(salt_);
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (proxy == address(0)) revert Create2Failed();
    }

    function _computeBeaconProxyAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        internal
        view
        returns (address)
    {
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        bytes32 salt = _deriveSalt(salt_);
        return _getCreate2Address(salt, keccak256(bytecode));
    }

    function _deriveSalt(bytes32 salt_) internal view returns (bytes32 salt) {
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
