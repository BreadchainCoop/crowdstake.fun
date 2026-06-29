// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMembership {
    function isMember(address account) external view returns (bool);
    function memberCount() external view returns (uint256);
}

/// @title CovaWithdrawals
/// @author COVA Artist Cooperative
/// @notice The four dedicated cooperative funds (Reserve, Education,
///         Solidarity, Production) and their democratic withdrawal flow — the
///         one part of the front end with no crowdstake analogue (crowdstake
///         models yield distribution, not fund-balance governance).
/// @dev Factory-deployed beacon module. Holds {CovaDollarYield} balances per
///      fund; withdrawals are proposed by members, decided one-person-one-vote
///      via the shared {OnePersonOneVotePower} membership ({IMembership}), and
///      released to the recipient when "for" strictly outnumbers "against".
contract CovaWithdrawals is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint8 public constant FUND_COUNT = 4; // Reserve, Education, Solidarity, Production

    enum Status {
        Voting,
        Approved,
        Rejected
    }

    struct Withdrawal {
        address proposer;
        uint8 fund;
        uint256 amount;
        address recipient;
        string purpose;
        Status status;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    /// @custom:storage-location erc7201:crowdstake.storage.CovaWithdrawals
    struct Store {
        IERC20 token;
        IMembership membership;
        uint256[4] funds;
        Withdrawal[] withdrawals;
        mapping(uint256 => mapping(address => bool)) voted;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.CovaWithdrawals")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORE = 0xb98722db7b4817523809d9ee21aee8b0be906a189a63c29d38f29655c3b88500;

    function _s() private pure returns (Store storage $) {
        assembly {
            $.slot := STORE
        }
    }

    error NotAMember();
    error InvalidFund();
    error InvalidAmount();
    error NotVoting();
    error AlreadyVoted();
    error NoVotesCast();

    event Inflow(uint8 indexed fund, uint256 amount, string note);
    event WithdrawalProposed(
        uint256 indexed id, address indexed proposer, uint8 fund, uint256 amount, address recipient, string purpose
    );
    event WithdrawalVoted(uint256 indexed id, address indexed member, bool support);
    event WithdrawalClosed(uint256 indexed id, Status status);
    event Movement(string from, string to, uint256 amount, string kind, string note);

    modifier onlyMember() {
        if (!_s().membership.isMember(msg.sender)) revert NotAMember();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address membership_, address coordinator_) external initializer {
        __Ownable_init(coordinator_);
        Store storage $ = _s();
        $.token = IERC20(token_);
        $.membership = IMembership(membership_);
    }

    /// @notice Coordinator deposits cUSD and credits the four funds (the front
    ///         end's "quarterly cooperative allocation").
    function allocateInflow(uint256[4] calldata amounts, string calldata note) external onlyOwner {
        Store storage $ = _s();
        uint256 total;
        for (uint8 i = 0; i < FUND_COUNT; i++) {
            total += amounts[i];
        }
        if (total == 0) revert InvalidAmount();
        $.token.safeTransferFrom(msg.sender, address(this), total);
        for (uint8 i = 0; i < FUND_COUNT; i++) {
            if (amounts[i] > 0) {
                $.funds[i] += amounts[i];
                emit Inflow(i, amounts[i], note);
                emit Movement("inflow", _name(i), amounts[i], "allocation", note);
            }
        }
    }

    function proposeWithdrawal(uint8 fund, uint256 amount, address recipient, string calldata purpose)
        external
        onlyMember
        returns (uint256 id)
    {
        if (fund >= FUND_COUNT) revert InvalidFund();
        Store storage $ = _s();
        if (amount == 0 || amount > $.funds[fund]) revert InvalidAmount();
        id = $.withdrawals.length;
        $.withdrawals.push(Withdrawal(msg.sender, fund, amount, recipient, purpose, Status.Voting, 0, 0));
        emit WithdrawalProposed(id, msg.sender, fund, amount, recipient, purpose);
    }

    function voteWithdrawal(uint256 id, bool support) external onlyMember {
        Store storage $ = _s();
        Withdrawal storage w = $.withdrawals[id];
        if (w.status != Status.Voting) revert NotVoting();
        if ($.voted[id][msg.sender]) revert AlreadyVoted();
        $.voted[id][msg.sender] = true;
        if (support) w.votesFor += 1;
        else w.votesAgainst += 1;
        emit WithdrawalVoted(id, msg.sender, support);
    }

    function closeWithdrawal(uint256 id) external onlyMember {
        Store storage $ = _s();
        Withdrawal storage w = $.withdrawals[id];
        if (w.status != Status.Voting) revert NotVoting();
        if (w.votesFor + w.votesAgainst == 0) revert NoVotesCast();
        if (w.votesFor > w.votesAgainst) {
            if (w.amount > $.funds[w.fund]) revert InvalidAmount();
            w.status = Status.Approved;
            $.funds[w.fund] -= w.amount;
            $.token.safeTransfer(w.recipient, w.amount);
            emit Movement(_name(w.fund), "recipient", w.amount, "withdrawal", w.purpose);
        } else {
            w.status = Status.Rejected;
        }
        emit WithdrawalClosed(id, w.status);
    }

    // ---- views ----
    function token() external view returns (IERC20) {
        return _s().token;
    }

    function membership() external view returns (IMembership) {
        return _s().membership;
    }

    function getFunds() external view returns (uint256[4] memory) {
        return _s().funds;
    }

    function withdrawalsCount() external view returns (uint256) {
        return _s().withdrawals.length;
    }

    function getWithdrawal(uint256 id) external view returns (Withdrawal memory) {
        return _s().withdrawals[id];
    }

    function hasVoted(uint256 id, address member) external view returns (bool) {
        return _s().voted[id][member];
    }

    function _name(uint8 i) private pure returns (string memory) {
        if (i == 0) return "reserve";
        if (i == 1) return "education";
        if (i == 2) return "solidarity";
        return "production";
    }
}
