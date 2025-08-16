// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAMMVotingPowerModule {
    /// @notice Occurs when a user does not have sufficient Butter to mint `ButteredBread`
    error InsufficientFunds();
    /// @notice Occurs when an invalid value is attempted to be used in setter functions
    error InvalidValue();
    /// @notice Occurs when attempting a deposit with a non-sanctioned LP
    error NotAllowListed();
    /// @notice Occurs when attempting to delegate `ButteredBrea`d tokens. Delegations are set via the $BREAD contract
    error NonDelegatable();
    /// @notice Occurs when attempting to transfer soulbound `ButteredBread` tokens
    error NonTransferable();
    /// @notice Occurs when a dependent variable is not set
    error UnsetVariable();
    /// @notice Occurs when a transfer fails
    error TransferFailed();
    /// @notice Occurs when an amount is 0
    error AmountZero();

    /// @notice The event emitted when an LP Token (Butter) has been added
    event ButterAdded(address _account, address _lp, uint256 _amount);
    /// @notice The event emitted when an LP Token (Butter) has been removed
    event ButterRemoved(address _account, address _lp, uint256 _amount);

    /**
     * @param breadToken Address of `BreadToken`
     * @param liquidityPools Sanctioned LPs
     * @param scalingFactors Scaling factor on mint per sanctioned LP
     * @dev Each scaling factor is a fixed point percent (e.g. 100 = 1X, 150 = 1.5X, 1000 = 10X)
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    struct InitData {
        address breadToken;
        address[] liquidityPools;
        uint256[] scalingFactors;
        string name;
        string symbol;
    }

    /**
     * @param balance Value of deposited LP tokens (Butter)
     * @param scalingFactor At the time of deposit or updated with `syncVotingWeight` function
     */
    struct LPData {
        uint256 balance;
        uint256 scalingFactor;
    }

    /// @notice Initialize contract as a `TransparentUpgradeableProxy`
    function initialize(InitData calldata _initData) external;

    /// @notice Returns whether a given liquidity pool is Breadchain sanctioned or not
    function allowlistedLPs(address _lp) external view returns (bool _allowed);

    /// @notice Returns the factor that determines how much `ButteredBread` should be minted for a Liquidity Pool token (Butter)
    function scalingFactors(address _lp) external view returns (uint256 _factor);

    /// @notice Returns the amount of LP tokens (Butter) deposited for an account
    function accountToLPBalance(address _account, address _lp) external view returns (uint256 _balance);

    /// @notice Deposits LP tokens (Butter) and mints `ButteredBread` according to the respective LP scaling factor
    function deposit(address _lp, uint256 _amount) external;

    /// @notice Withdraws some amount of Butter (LP token) and burns an amount of the user's `ButteredBread` according to the respective scaling factor
    function withdraw(address _lp, uint256 _amount) external;

    /// @notice Defines a liquidity pool's status as sanctioned or unsanctioned by Breadchain
    function modifyAllowList(address _lp, bool _allowed) external;

    /// @notice Modifies how much `ButteredBread` should be minted for a Liquidity Pool token (Butter)
    function modifyScalingFactor(address _lp, uint256 _factor, address[] calldata holders) external;
}
