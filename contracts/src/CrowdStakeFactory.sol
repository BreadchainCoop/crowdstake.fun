// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title CrowdStakeFactory
/// @notice Factory contract for deploying deterministic beacon proxies.
/// @dev Uses CREATE2 for deterministic deployments with sender-scoped salts.
///      Only beacons on the allowlist can be used to create proxies.
contract CrowdStakeFactory is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Thrown when attempting to add a beacon that is already on the allowlist.
    error AlreadyAllowlistedBeacon();

    /// @notice Thrown when the provided address has no code deployed (e.g., an EOA).
    error NotBeacon();

    /// @notice Thrown when attempting to use or remove a beacon that is not on the allowlist.
    error NotAllowlistedBeacon();

    /// @notice Thrown when a CREATE2 deployment returns the zero address.
    error Create2Failed();

    /// @notice Emitted when beacons are added to the allowlist.
    /// @param beacons The array of beacon addresses added.
    event AllowlistBeacons(address[] beacons);

    /// @notice Emitted when beacons are removed from the allowlist.
    /// @param beacons The array of beacon addresses removed.
    event DenylistBeacons(address[] beacons);

    /// @notice Emitted when a token proxy is created via the legacy `createToken` entrypoint.
    /// @param token The address of the deployed token proxy.
    /// @param beacon The beacon address used for the proxy.
    /// @param payload The initialization payload forwarded to the proxy.
    event CreateToken(address token, address beacon, bytes payload);

    /// @notice Emitted when a module proxy is created via `create`.
    /// @param module The address of the deployed module proxy.
    /// @param beacon The beacon address used for the proxy.
    /// @param payload The initialization payload forwarded to the proxy.
    event CreateModule(address module, address beacon, bytes payload);

    /// @dev Set of beacon addresses currently on the allowlist.
    EnumerableSet.AddressSet internal _beacons;

    /// @notice Deploys a new CrowdStakeFactory and sets the initial owner.
    /// @param _owner The address that will own this factory.
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /// @notice Creates a beacon proxy for a token (legacy entrypoint, delegates to `_createBeaconProxy`).
    /// @param beacon_ The allowlisted beacon to use for the proxy.
    /// @param payload_ The ABI-encoded initialization calldata forwarded to the proxy constructor.
    /// @param salt_ A user-provided salt combined with `msg.sender` for deterministic deployment.
    /// @return token The address of the newly deployed token proxy.
    function createToken(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address token) {
        token = _createBeaconProxy(beacon_, payload_, salt_);
        emit CreateToken(token, beacon_, payload_);
    }

    /// @notice Creates a beacon proxy for any module type.
    /// @param beacon_ The allowlisted beacon to use for the proxy.
    /// @param payload_ The ABI-encoded initialization calldata forwarded to the proxy constructor.
    /// @param salt_ A user-provided salt combined with `msg.sender` for deterministic deployment.
    /// @return module The address of the newly deployed module proxy.
    function create(address beacon_, bytes calldata payload_, bytes32 salt_) external returns (address module) {
        module = _createBeaconProxy(beacon_, payload_, salt_);
        emit CreateModule(module, beacon_, payload_);
    }

    /// @notice Computes the deterministic address for a beacon proxy deployment without deploying it.
    /// @dev When called off-chain via eth_call, msg.sender defaults to address(0) unless the
    ///      `from` field is set explicitly, which will produce incorrect results since the salt
    ///      is sender-scoped. Use the overload that accepts a `sender_` parameter instead.
    /// @param beacon_ The beacon address that would be used.
    /// @param payload_ The initialization payload that would be used.
    /// @param salt_ The user-provided salt that would be used.
    /// @return The predicted deployment address.
    function computeAddress(address beacon_, bytes calldata payload_, bytes32 salt_) external view returns (address) {
        return _computeBeaconProxyAddress(beacon_, payload_, salt_);
    }

    /// @notice Computes the deterministic address for a beacon proxy with an explicit sender.
    /// @dev Use this overload for off-chain address predictions (e.g., via eth_call) to avoid
    ///      the msg.sender footgun — the default overload uses caller() for the salt, which
    ///      defaults to address(0) in static calls unless `from` is set.
    /// @param beacon_ The beacon address that would be used.
    /// @param payload_ The initialization payload that would be used.
    /// @param salt_ The user-provided salt that would be used.
    /// @param sender_ The address that will call `create` (used to derive the sender-scoped salt).
    /// @return The predicted deployment address.
    function computeAddress(address beacon_, bytes calldata payload_, bytes32 salt_, address sender_)
        external
        view
        returns (address)
    {
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        bytes32 salt = _deriveSaltFor(sender_, salt_);
        return _getCreate2Address(salt, keccak256(bytecode));
    }

    /// @notice Computes the deterministic address for a token proxy (legacy entrypoint).
    /// @param beacon_ The beacon address that would be used.
    /// @param payload_ The initialization payload that would be used.
    /// @param salt_ The user-provided salt that would be used.
    /// @return The predicted deployment address.
    function computeTokenAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        external
        view
        returns (address)
    {
        return _computeBeaconProxyAddress(beacon_, payload_, salt_);
    }

    /// @notice Adds beacon addresses to the allowlist. Only callable by the owner.
    /// @param beacons_ The array of beacon addresses to add.
    /// @dev Reverts if any address has no deployed code or is already allowlisted.
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

    /// @notice Removes beacon addresses from the allowlist. Only callable by the owner.
    /// @param beacons_ The array of beacon addresses to remove.
    /// @dev Reverts if any address is not currently on the allowlist.
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

    /// @notice Returns all beacon addresses currently on the allowlist.
    /// @return An array of allowlisted beacon addresses.
    function beacons() external view returns (address[] memory) {
        return _beacons.values();
    }

    /// @notice Checks whether a beacon address is on the allowlist.
    /// @param beacon_ The beacon address to check.
    /// @return isContained True if the beacon is allowlisted.
    function beaconsContains(address beacon_) external view returns (bool isContained) {
        return _beacons.contains(beacon_);
    }

    // ============ Internal Helpers ============

    /// @dev Deploys a beacon proxy using CREATE2 with a sender-scoped salt.
    ///      Reverts if the beacon is not allowlisted or if deployment fails.
    /// @param beacon_ The allowlisted beacon to use for the proxy.
    /// @param payload_ The ABI-encoded initialization calldata forwarded to the proxy constructor.
    /// @param salt_ A user-provided salt combined with `msg.sender` for deterministic deployment.
    /// @return proxy The address of the newly deployed proxy.
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

    /// @dev Computes the predicted address for a beacon proxy deployment.
    /// @param beacon_ The beacon address that would be used.
    /// @param payload_ The initialization payload that would be used.
    /// @param salt_ The user-provided salt that would be used.
    /// @return The predicted deployment address.
    function _computeBeaconProxyAddress(address beacon_, bytes calldata payload_, bytes32 salt_)
        internal
        view
        returns (address)
    {
        bytes memory bytecode = _getBeaconProxyInitCode(beacon_, payload_);
        bytes32 salt = _deriveSalt(salt_);
        return _getCreate2Address(salt, keccak256(bytecode));
    }

    /// @dev Derives a sender-scoped salt by hashing `msg.sender` with the user-provided salt.
    /// @param salt_ The user-provided salt.
    /// @return salt The derived sender-scoped salt.
    function _deriveSalt(bytes32 salt_) internal view returns (bytes32 salt) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), salt_)
            salt := keccak256(ptr, 0x40)
        }
    }

    /// @dev Derives a sender-scoped salt for a given sender address (for off-chain predictions).
    /// @param sender_ The address to use instead of msg.sender.
    /// @param salt_ The user-provided salt.
    /// @return The derived sender-scoped salt.
    function _deriveSaltFor(address sender_, bytes32 salt_) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender_, salt_));
    }

    /// @dev Returns the creation code for a `BeaconProxy` with the given beacon and payload.
    /// @param beacon_ The beacon address to encode.
    /// @param payload_ The initialization payload to encode.
    /// @return The ABI-packed creation bytecode.
    function _getBeaconProxyInitCode(address beacon_, bytes calldata payload_) internal pure returns (bytes memory) {
        return abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon_, payload_));
    }

    /// @dev Computes a CREATE2 address from a salt and bytecode hash.
    /// @param salt_ The CREATE2 salt.
    /// @param bytecodeHash_ The keccak256 hash of the creation bytecode.
    /// @return The predicted deployment address.
    function _getCreate2Address(bytes32 salt_, bytes32 bytecodeHash_) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt_, bytecodeHash_)))));
    }
}
