// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IVotingPowerStrategy.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title TimeWeightedVotingPowerStrategy
/// @notice Voting power weighted by how long tokens have been held (issue #48)
/// @dev Uses ERC20Votes checkpoints to calculate time-weighted voting power.
///      Power accumulates based on block-weighted token holdings over a cycle.
/// @author BreadKit Protocol
contract TimeWeightedVotingPowerStrategy is IVotingPowerStrategy {
    /// @notice The voting token with checkpoint support
    address public immutable votingToken;

    /// @notice The block number when the current cycle started
    uint256 public cycleStartBlock;

    /// @notice Admin that can update cycle parameters
    address public admin;

    error NotAdmin();
    error InvalidBlock();

    event CycleStartBlockUpdated(uint256 oldBlock, uint256 newBlock);

    constructor(address _votingToken, address _admin) {
        votingToken = _votingToken;
        admin = _admin;
        cycleStartBlock = block.number;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        return IVotes(votingToken).getVotes(account);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getAccumulatedVotingPower(address account) external view override returns (uint256) {
        // Time-weighted: current votes * blocks held since cycle start
        uint256 currentVotes = IVotes(votingToken).getVotes(account);
        uint256 blocksInCycle = block.number - cycleStartBlock;

        if (blocksInCycle == 0) return currentVotes;

        // Approximate time-weighted power using current balance * duration
        // More sophisticated implementations could sample checkpoints
        return currentVotes * blocksInCycle;
    }

    /// @notice Get voting power for a specific period using checkpoints
    /// @param account The account to check
    /// @param startBlock Start of the period
    /// @param endBlock End of the period
    /// @return power The time-weighted voting power
    function getVotingPowerForPeriod(address account, uint256 startBlock, uint256 endBlock)
        external
        view
        returns (uint256 power)
    {
        if (endBlock <= startBlock) revert InvalidBlock();

        // Use past votes at the start block as an approximation
        uint256 pastVotes = IVotes(votingToken).getPastVotes(account, startBlock);
        power = pastVotes * (endBlock - startBlock);
    }

    /// @notice Update the cycle start block
    /// @param _cycleStartBlock New cycle start block
    function setCycleStartBlock(uint256 _cycleStartBlock) external onlyAdmin {
        uint256 old = cycleStartBlock;
        cycleStartBlock = _cycleStartBlock;
        emit CycleStartBlockUpdated(old, _cycleStartBlock);
    }

    /// @notice Transfer admin role
    /// @param newAdmin New admin address
    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
