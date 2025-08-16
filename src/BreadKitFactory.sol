// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DefaultYieldClaimer} from "./DefaultYieldClaimer.sol";

contract BreadKitFactory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error AlreadyWhitelistedBeacon();
    error NotBeacon();
    error NotWhitelistedBeacon();
    error Create2Failed();

    event WhitelistBeacons(address[] beacons);
    event BlacklistBeacons(address[] beacons);
    event CreateToken(address token, address beacon, bytes payload);
    event CreateYieldDistributor(
        address yieldClaimer, address token, address[] initialRecipients, uint256 percentVoted, address owner
    );

    EnumerableSet.AddressSet internal _beacons;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function createToken(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address token) {
        if (!_beacons.contains(beacon_)) {
            revert NotWhitelistedBeacon();
        }

        bytes32 salt = keccak256(abi.encode(msg.sender, salt_));
        bytes memory bytecode = _getTokenInitCode(beacon_, payload_);
        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (token == address(0)) revert Create2Failed();

        emit CreateToken(token, beacon_, payload_);
    }

    function createDefaultYieldClaimer(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = keccak256(abi.encode(msg.sender, salt_));
        assembly {
            yieldClaimer := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (yieldClaimer == address(0)) revert Create2Failed();

        emit CreateYieldDistributor(yieldClaimer, token_, initialRecipients_, percentVoted_, owner_);
    }

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

    function computeTokenAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        external
        view
        returns (address token)
    {
        bytes memory bytecode = _getTokenInitCode(beacon_, payload_);
        bytes32 salt = keccak256(abi.encode(msg.sender, salt_));
        token = _getCreate2Address(salt, keccak256(bytecode));
    }

    function computeClaimerAddress(
        address token_,
        address[] memory initialRecipients_,
        uint256 percentVoted_,
        address owner_,
        bytes32 salt_
    ) external view returns (address yieldClaimer) {
        bytes memory bytecode = _getYieldDistributorInitCode(token_, initialRecipients_, percentVoted_, owner_);
        bytes32 salt = keccak256(abi.encode(msg.sender, salt_));
        yieldClaimer = _getCreate2Address(salt, keccak256(bytecode));
    }

    function _getTokenInitCode(address beacon_, bytes calldata payload_) internal pure returns (bytes memory) {
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
