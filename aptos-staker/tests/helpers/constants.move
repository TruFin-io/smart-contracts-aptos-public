#[test_only]
module publisher::constants {
    friend publisher::init_test;
    friend publisher::setter_test;
    friend publisher::stake_test;
    friend publisher::unlock_test;
    friend publisher::withdraw_test;
    friend publisher::truAPT_test;
    friend publisher::share_price_test;
    friend publisher::multi_validator_test;
    friend publisher::total_staked_test;
    friend publisher::getter_test;
    friend publisher::residual_rewards_test;

    friend publisher::setup_test_staker;
    friend publisher::setup_test_delegation_pool;
    friend publisher::time;
    friend publisher::fees_test;
    friend publisher::withdraw_list_test;

    const ONE_APT: u64 = 100000000;

    const SHARE_PRICE_SCALING_FACTOR: u256 = 100000000;
    
    // Validator statuses from `stake` contract
    const VALIDATOR_STATUS_PENDING_ACTIVE: u64 = 1;
    const VALIDATOR_STATUS_ACTIVE: u64 = 2;
    const VALIDATOR_STATUS_PENDING_INACTIVE: u64 = 3;
    const VALIDATOR_STATUS_INACTIVE: u64 = 4;

    // _________________ Constants for staker setup _________________
    const DEFAULT_FEE: u64 = 1000;

    const DEFAULT_DIST_FEE: u64 = 500;

    const FEE_PRECISION: u64 = 10000;

    const DEFAULT_MIN_DEPOSIT: u64 = 1000000000;

    const MIN_COINS_ON_SHARES_POOL: u64 = 1000000000;

    // _________________ Constants for custom delegation pool setup _________________
    const LOCKUP_CYCLE_SECONDS: u64 = 3600;

    const DELEGATION_POOLS: u64 = 11;

    const MODULE_EVENT: u64 = 26;

    const OPERATOR_BENEFICIARY_CHANGE: u64 = 39;

    const NEW_OLC_PERIOD: u64 = 3600; // time in seconds

    // _________________ Getter Functions for Constants _________________
    #[view]
    public(friend) fun one_apt(): u64 {
        ONE_APT
    }

    #[view]
    public(friend) fun pending_active_validator_status(): u64 {
        VALIDATOR_STATUS_PENDING_ACTIVE
    }

    #[view]
    public(friend) fun active_validator_status(): u64 {
        VALIDATOR_STATUS_ACTIVE
    }

    #[view]
    public(friend) fun pending_inactive_validator_status(): u64 {
        VALIDATOR_STATUS_PENDING_INACTIVE
    }

    #[view]
    public(friend) fun inactive_validator_status(): u64 {
        VALIDATOR_STATUS_INACTIVE
    }

    #[view]
    public(friend) fun default_fee(): u64 {
        DEFAULT_FEE
    }

    #[view]
    public(friend) fun default_dist_fee(): u64 {
        DEFAULT_DIST_FEE
    }
    
    #[view]
    public(friend) fun fee_precision(): u64 {
        FEE_PRECISION
    }

    #[view]
    public(friend) fun default_min_deposit(): u64 {
        DEFAULT_MIN_DEPOSIT
    }

    #[view]
    public(friend) fun pools(): u64 {
        DELEGATION_POOLS
    }

    #[view]
    public(friend) fun lockup_cycle_seconds(): u64 {
        LOCKUP_CYCLE_SECONDS
    }

    #[view]
    public(friend) fun module_event(): u64 {
        MODULE_EVENT
    }

    #[view]
    public(friend) fun operator_beneficiary_change(): u64 {
        OPERATOR_BENEFICIARY_CHANGE
    }

    #[view]
    public(friend) fun new_olc_period(): u64 {
        NEW_OLC_PERIOD
    }

    #[view]
    public(friend) fun min_coins_on_shares_pool(): u64 {
        MIN_COINS_ON_SHARES_POOL
    }
}