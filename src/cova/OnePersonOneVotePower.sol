// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";

/// @title OnePersonOneVotePower
/// @author COVA Artist Cooperative
/// @notice Crowdstake {IVotingPowerStrategy} implementing one-person-one-vote:
///         every cooperative member has exactly one equal unit of voting power,
///         non-members have none — independent of any token balance.
/// @dev Plugged into {CovaPointsVotingModule} (an {AbstractVotingModule}) as
///      its voting-power strategy, so the protocol's voting machinery treats
///      every member's ballot equally. Membership is curated by the
///      coordinator (owner).
contract OnePersonOneVotePower is IVotingPowerStrategy, Ownable {
    /// @notice The equal voting power granted to every member.
    uint256 public constant VOTE_UNIT = 1e18;

    mapping(address => bool) public isMember;
    uint256 public memberCount;

    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);

    error AlreadyMember();
    error NotMember();
    error ZeroAddress();

    constructor(address coordinator) {
        if (coordinator == address(0)) revert ZeroAddress();
        _initializeOwner(coordinator);
    }

    function addMember(address member) public onlyOwner {
        if (member == address(0)) revert ZeroAddress();
        if (isMember[member]) revert AlreadyMember();
        isMember[member] = true;
        memberCount++;
        emit MemberAdded(member);
    }

    function removeMember(address member) public onlyOwner {
        if (!isMember[member]) revert NotMember();
        isMember[member] = false;
        memberCount--;
        emit MemberRemoved(member);
    }

    function addMembers(address[] calldata members) external onlyOwner {
        for (uint256 i = 0; i < members.length; i++) {
            addMember(members[i]);
        }
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        return isMember[account] ? VOTE_UNIT : 0;
    }
}
