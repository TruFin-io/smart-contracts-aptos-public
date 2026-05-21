module publisher::staker{
    // *** LIBRARIES ***
    use std::string::{Self, String};
    use std::signer;
    use std::error;
    use std::option::{Self, Option};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::code;
    use aptos_framework::resource_account;
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::delegation_pool;
    use aptos_framework::stake;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::reconfiguration::current_epoch;

    use aptos_std::smart_table::{Self, SmartTable};

    // trufin smart contracts
    use publisher::truAPT;
    use whitelist::master_whitelist::{is_whitelisted};

    // *** CONSTANTS ***

    const ADMIN: address = @default_admin;
    const RESOURCE_ACCOUNT: address = @publisher;
    const SRC: address = @src_account;

    const FEE_PRECISION: u64 = 10000;
    const SHARE_PRICE_SCALING_FACTOR: u256 = 100000000; // 1 APT, scaling factor applied to the share price numerator
    const MAX_STAKE_AMOUNT: u64 = 50_000_000_00000000; // 50M APT
    const MIN_COINS_ON_SHARES_POOL: u64 = 10_00000000; // 10 APT, minimum amount of APT that must be in the pool to allow staking
    const ONE_APT: u64 = 100000000; // 1 APT

    // Validator States
    const POOL_ENABLED: u8 = 1;
    const POOL_DISABLED: u8 = 2;

    // Aptos Validator States
    const VALIDATOR_STATUS_ACTIVE: u64 = 2; // code for active validator on Aptos

    // *** ERRORS ***

    // Custom error codes.
    const ESTAKER_ALREADY_INITIALISED: u64 = 1; 
    const ESTRING_TOO_LONG: u64 = 2;
    const EZERO_ADDRESS: u64 = 3;
    const ENOT_ADMIN: u64 = 4;
    const EFEE_TOO_LARGE: u64 = 5;
    const EDEPOSIT_AMOUNT_TOO_SMALL: u64 = 6;
    const EBELOW_MIN_UNLOCK: u64 = 7;
    const EINSUFFICIENT_BALANCE: u64 = 8;
    const EUSER_NOT_WHITELISTED: u64 = 9;
    const ESENDER_MUST_BE_RECEIVER: u64 = 10;
    const EINVALID_NONCE: u64 = 11;
    const EWITHDRAW_NOT_READY: u64 = 12;
    const EPOOL_ALREADY_EXISTS: u64 = 13;
    const EINVALID_POOL_ADDRESS: u64 = 14;
    const EPOOL_ALREADY_DISABLED: u64 = 15;
    const EPOOL_ALREADY_ENABLED: u64 = 16;
    const EPOOL_DISABLED: u64 = 17;
    const EPOOL_AT_MAX_CAPACITY: u64 = 18;
    const EBELOW_MIN_STAKE: u64 = 19;
    const EUNLOCK_AMOUNT_TOO_HIGH: u64 = 20;
    const EDEPRECATED_ALLOCATION_UNDER_ONE_APT: u64 = 21;
    const EDEPRECATED_NO_ALLOCATIONS: u64 = 22;
    const EDEPRECATED_INVALID_RECIPIENT: u64 = 23;
    const EINVALID_UNSTAKED_AMOUNT: u64 = 24;
    const EDEPRECATED_NO_ALLOCATION_TO_RECIPIENT: u64 = 25;
    const EDEPRECATED_EXCESS_DEALLOCATION: u64 = 26;
    const EVALIDATOR_NOT_ACTIVE: u64 = 27;
    const ECONTRACT_PAUSED: u64 = 28;
    const EALREADY_PAUSED: u64 = 29;
    const EALREADY_UNPAUSED: u64 = 30;
    const ENO_PENDING_ADMIN: u64 = 31;
    const ENOT_PENDING_ADMIN: u64 = 32;
    const ENO_NONCES_PROVIDED: u64 = 33;
    const EDEPRECATED: u64 = 34;

    // *** STRUCTS ***

    /// @notice Staker settings defining resource ownership.
    struct Settings has key {
        signer_cap: account::SignerCapability, //resource account signer
        admin: address,
        pending_admin: Option<address>
    }

    /// @notice Staker metadata defining staker name and variables i.e. fees. 
    struct StakerInfo has key {
        name: String, // staker name
        treasury: address, // treasury address
        fee: u64, // treasury fee
        dist_fee: u64, // DEPRECATED in v0.0.2
        min_deposit: u64, // minimum APT amount a user must deposit
        truAPT_coin: object::Object<Metadata>, // TruApt token metadata
        tax_exempt_stake: u64, // total amount of APT staked in the staker for which no fees are charged
        is_paused: bool // whether the contract is currently paused
    }

    /// @notice Struct for storing all delegation pool information.
    struct DelegationPools has key {
        delegation_pools: SmartTable<address, DelegationPool>, // Mapping of pool_address to delegation pool
        default_delegation_pool: address, // Default delegation pool address
    }
    
    /// @notice Delegation Pool struct to track epochs and fees.
    struct DelegationPool has drop, store {
        pool_address: address,
        epoch_at_last_update: u64,
        add_stake_fees: u64,
        pool_state: u8
    }

    /// @notice Struct to return delegation pool information to the user.
    struct DelegationPoolInfo has drop {
        pool_address: address,
        pool_state: u8,
        stake: u64,
    }

    /// DEPRECATED in v0.0.2.
    struct Allocations has key {
        allocations: SmartTable<address, Allocation>,
    }

    /// DEPRECATED in v0.0.2.
    struct Allocation has drop, store, copy {
        apt_amount: u64,
        share_price_num: u256,
        share_price_denom: u256,
    }

    /// DEPRECATED in v0.0.2.
    struct AllocationInfo has drop {
        recipient: address,
        apt_amount: u64,
        share_price_num: u256,
        share_price_denom: u256,
    }

    /// DEPRECATED in v0.0.2.
    struct DistributionInfo has drop {
        user: address,
        recipient: address,
        user_balance: u64,
        recipient_balance: u64,
        fees: u64,
        treasury_balance: u64,
        shares: u64,
        apt_amount: u64,
        in_apt: bool,
        share_price_num: u256,
        share_price_denom: u256,
    }

    /// @notice Struct for storing unlock information.
    struct Unlocks has key {
        unlocks: SmartTable<u64, UnlockRequest>, // hashmap of unlock nonce to unlock request
        unlock_nonce: u64, // nonce for unlock requests      
        unlocked_amount_received: u64, // the sum of all unlocked APT received by the staker since the last residual-rewards collection
        unlocks_paid: u64, // the sum of all unlocked amounts paid to the users since the last residual reward collection
    }

    /// @notice Struct for unlock requests.
    struct UnlockRequest has drop, store {
        amount: u64,
        user: address,
        olc: u64,
        delegation_pool: address,
        residual_rewards_collected: bool
    }

    // *** EVENTS ***

    #[event]
    /// @notice Emitted when staker is initialised.
    /// @dev Emit StakerInitialised Event.
    /// @param Name of staker that was initialised.
    /// @param Address of the treasury.
    /// @param Address of the delegation pool.
    /// @param Treasury fee payable on rewards.
    /// @param Treasury fee payable upon distribution.
    /// @param Minimum APT amount a user has to deposit.
    /// @param Address of the admin who initialised the vault.
    struct StakerInitialisedEvent has drop, store {
        name: String,
        treasury: address,
        delegation_pool: address,
        fee: u64,
        dist_fee: u64, // DEPRECATED in v0.0.2
        min_deposit_amount: u64,
        admin: address,
    }

    #[event]
    /// @notice Emitted when contract is paused/unpaused.
    /// @param Whether the contract is now paused. 
    struct PauseStateChangedEvent has drop, store {
        is_paused: bool
    }

    #[event]
    /// @notice Emitted when Fee is set.
    /// @param Old treasury fee.
    /// @param New treasury fee.
    struct SetFeeEvent has drop, store {
        old_fee: u64,
        new_fee: u64
    }

    #[event]
    /// DEPRECATED in v0.0.2.
    struct SetDistFeeEvent has drop, store {
        old_dist_fee: u64,
        new_dist_fee: u64
    }

    #[event]
    /// @notice Emitted when minimum deposit is set.
    /// @param Old minimum deposit amount.
    /// @param New minimum deposit amount.
    struct SetMinDepositEvent has drop, store {
        old_min_deposit: u64,
        new_min_deposit: u64
    }

    #[event]
    /// @notice Emitted when a new pending admin is set.
    /// @param Current admin address.
    /// @param Pending admin address.
    struct SetPendingAdminEvent has drop, store {
        current_admin: address,
        pending_admin: address
    }
    
    #[event]
    /// @notice Emitted when the pending admin claims the admin role.
    /// @param Old admin address.
    /// @param New admin address.
    struct AdminRoleClaimedEvent has drop, store {
        old_admin: address,
        new_admin: address
    }

    #[event]
    /// @notice Emitted when default delegation pool is set.
    /// @param Old default delegation pool address.
    /// @param New default delegation pool address.
    struct SetDefaultDelegationPoolEvent has drop, store {
        old_default_delegation_pool: address,
        new_default_delegation_pool: address
    }
    
    #[event]
    /// @notice Emitted when treasury is set.
    /// @param Old treasury address.
    /// @param New treasury address.
    struct SetTreasuryEvent has drop, store {
        old_treasury: address,
        new_treasury: address
    }

    #[event]
    /// @notice Emitted when user deposits into the vault.
    /// @param Address of the user.
    /// @param Amount of APT deposited.
    /// @param User's TruAPT balance.
    /// @param Amount of TruAPT minted.
    /// @param Total amount staked on staker.
    /// @param Total supply of TruAPT in circulation.
    /// @param Share price numerator.
    /// @param Share price denominator.
    /// @param Address of the delegation pool.
    struct DepositedEvent has drop, store {
        user: address,
        amount: u64,
        user_balance: u64,
        shares_minted: u64,
        total_staked: u64,
        total_supply: u64,
        share_price_num: u256,
        share_price_denom: u256,
        delegation_pool: address
    }

    #[event]
    /// @notice Emitted when user unlocks funds from the vault.
    /// @param Address of the user.
    /// @param Amount of APT unlocked.
    /// @param OLC when the unlock request was made.
    /// @param Unlock nonce of the unlock request.
    /// @param User's TruAPT balance.
    /// @param Amount of shares burned.
    /// @param Total amount staked on staker.
    /// @param Total supply of TruAPT in circulation.
    /// @param Share price numerator.
    /// @param Share price denominator.
    /// @param Address of the delegation pool.
    struct UnlockedEvent has drop, store {
        user: address,
        amount: u64,
        olc: u64,
        unlock_nonce: u64,
        user_balance: u64,
        shares_burned: u64,
        total_staked: u64,
        total_supply: u64,
        share_price_num: u256,
        share_price_denom: u256,
        delegation_pool: address
    }

    #[event]
    /// DEPRECATED in v0.0.2.
    struct AllocatedEvent has drop, store {
        user: address,
        recipient: address,
        amount: u64,
        total_amount: u64,
        share_price_num: u256,
        share_price_denom: u256,
        total_allocated_amount: u64,
        total_allocated_share_price_num: u256,
        total_allocated_share_price_denom: u256
    }
   
    #[event]
    /// DEPRECATED in v0.0.2.
    struct DistributedRewardsEvent has drop, store {
        user: address,
        recipient: address,
        shares: u64,
        apt_amount: u64,
        user_balance: u64,
        recipient_balance: u64,
        fees: u64,
        treasury_balance: u64,
        share_price_num: u256,
        share_price_denom: u256,
        in_apt: bool,
        total_allocated_amount: u64,
        total_allocated_share_price_num: u256,
        total_allocated_share_price_denom: u256
    }

    #[event]
    /// DEPRECATED in v0.0.2.
    struct DistributedAllEvent has drop, store {
        user: address
    }

    #[event]
    /// DEPRECATED in v0.0.2.
    struct DeallocatedEvent has drop, store {
        user: address,
        recipient: address,
        amount: u64,
        total_amount: u64,
        share_price_num: u256,
        share_price_denom: u256,
        total_allocated_amount: u64,
        total_allocated_share_price_num: u256,
        total_allocated_share_price_denom: u256
    }

    #[event]
    /// @notice Emitted when user withdraws stake from the vault.
    /// @param Address of the user.
    /// @param Amount of APT unlocked.
    /// @param Unlock nonce of the unlock request.
    /// @param OLC when the unlock request was claimed.
    /// @param Address of the delegation pool.
    struct WithdrawalClaimedEvent has drop, store {
        user: address,
        amount: u64,
        unlock_nonce: u64,
        olc: u64,
        delegation_pool: address
    }
    
    #[event]
    /// @notice Emitted when a new delegation pool is added.
    /// @param Address of the new delegation pool.
    struct DelegationPoolAddedEvent has drop, store {
        pool_address: address,
    }

    #[event]
    /// @notice Emitted when the state of a delegation pool is changed.
    /// @param Address of the delegation pool which changed state.
    /// @param The old state of the delegation pool.
    /// @param The new state of the delegation pool.
    struct DelegationPoolStateChangedEvent has drop, store {
        pool_address: address,
        old_state: u8,
        new_state: u8
    }
    
    #[event]
    /// @notice Emitted when fees are collected.
    /// @param Amount of shares minted to the treasury in TruAPT.
    /// @param Treasury's TruAPT balance.
    /// @param Share price numerator.
    /// @param Share price denominator.
    struct FeesCollectedEvent has drop, store {
        shares_minted: u64,
        treasury_balance: u64,
        share_price_num: u256,
        share_price_denom: u256
    }

    #[event]
    /// @notice Emitted when residual rewards are collected by the treasury.
    /// @param Amount of residual rewards collected by treasury in APT.
    /// @param Share price numerator.
    /// @param Share price denominator.
    /// @param Treasury's TruAPT balance.
    struct ResidualRewardsCollectedEvent has drop, store {
        amount: u64,
        share_price_num: u256,
        share_price_denom: u256,
        treasury_balance: u64
    }

    // *** PUBLIC FUNCTIONS ***
    // *** PUBLIC VIEW FUNCTIONS ***
    
    #[view]
    /// @notice View function to query global staker info, such as staker's name, treasury address, treasury fee, distribution fee,
    ///  minimum deposit amount, admin address and TruAPT coin metadata.
    /// @return Staker name.
    /// @return Treasury address. 
    /// @return Treasury fee.
    /// @return DEPRECATED `dist_fee` slot.
    /// @return Minimum deposit amount in APT. 
    /// @return Admin address.
    /// @return TruAPT coin metadata.
    public fun staker_info(): (String, address, u64, u64, u64, address, object::Object<Metadata>, bool) acquires Settings, StakerInfo {
        let staker = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        return (
            staker.name,
            staker.treasury,
            staker.fee,
            staker.dist_fee,
            staker.min_deposit,
            settings.admin,
            staker.truAPT_coin,
            staker.is_paused
        )
    }

    #[view]
    /// @notice Checks if the user provided is the admin.
    /// @param Address that is to be checked.
    /// @return Boolean indicating whether the user is the admin.
    public fun is_admin(user: address): bool acquires Settings{
        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        return (settings.admin == user)
    }

    #[view]
    /// @notice Returns the total amount of APT currently staked by the vault.
    /// @dev The total staked is given by the current active (which includes pending active) stake plus the add_stake_fees,
    /// which are locked up for an epoch before being refunded. We do not include inactive or pending_inactive stake  
    /// as the corresponding TruAPT has already been burned and thus would cause wrong share_price calculations.
    /// @return Total amount of APT staked.
    public fun total_staked(): (u64) acquires DelegationPools {
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        let total_staked: u64 = 0;
        let current_epoch = current_epoch();

        smart_table::for_each_ref(&pools.delegation_pools, |_address, _pool| {
            let pool: &DelegationPool = _pool;
            let add_stake_fees = 0;
            if (pool.epoch_at_last_update == current_epoch) {
                add_stake_fees = pool.add_stake_fees;
            };
            let (active, _, _) = delegation_pool::get_stake(*_address, RESOURCE_ACCOUNT);
            total_staked = total_staked + active + add_stake_fees;
        });
        
        return total_staked
    }

    #[view]
    /// DEPRECATED in v0.0.2.
    public fun total_allocated(_user: address): (u64, u256, u256) {
        abort error::invalid_state(EDEPRECATED)
    }

    #[view]
    /// @notice View function to determine whether an unlock request is ready to be be withdrawn.
    /// This is the case if the lockup cycle during which the unlock request was made has elapsed, or the validator has become inactive.
    /// @param Unlock nonce as the identifier of the unlock request whose status shall be checked. 
    /// @return Boolean indicating whether an unlock request is now claimable.
    public fun is_claimable(unlock_nonce: u64) : (bool) acquires Unlocks {
        let unlocks = borrow_global<Unlocks>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&unlocks.unlocks, unlock_nonce), error::invalid_argument(EINVALID_NONCE));
        let unlock_request = smart_table::borrow(&unlocks.unlocks, unlock_nonce);
        
        // synchronize state with delegation pool (and underlying stake pool) state
        delegation_pool::synchronize_delegation_pool(unlock_request.delegation_pool);

        return ready_to_withdraw(unlock_request.olc, unlock_request.delegation_pool)
    }

    #[view]
    /// @notice View function to query the total amount of TruAPT tokens in existence.
    /// @return Total amount of TruAPT tokens in existence.
    public fun total_shares(): (u64) {
        return truAPT::total_supply()
    }

    #[view]
    /// @notice View function to query the share price scaling factor.
    /// @return Share price scaling factor.
    public fun share_price_scaling_factor(): (u256) {
        return SHARE_PRICE_SCALING_FACTOR
    }
    
    #[view]
    /// @notice View function to get the nonce of the latest unlock request.
    /// @return The latest unlock nonce.
    public fun latest_unlock_nonce(): (u64) acquires Unlocks{
        let unlocks = borrow_global<Unlocks>(RESOURCE_ACCOUNT);
        return unlocks.unlock_nonce
    }

    #[view]
    /// @notice View function to get the default delegation pool address.
    /// @return Address of the default delegation pool.
    public fun default_pool(): (address) acquires DelegationPools{
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        return pools.default_delegation_pool
    }

    #[view]
    /// @notice View function to get the current TruAPT share price in APT.
    /// @dev Represented via a fraction. Factor of SHARE_PRICE_SCALING_FACTOR is included in numerator.
    /// @dev The share price is inclusive of any fees charged on staking rewards.
    /// @return Share price numerator.
    /// @return Share price denominator.
    public fun share_price(): (u256, u256) acquires DelegationPools, StakerInfo {
        
        // Get the total number of TruAPT shares
        let shares_supply = (total_shares() as u256);

        if (shares_supply == 0) {
            return (SHARE_PRICE_SCALING_FACTOR, 1)
        };

        // get the total staked amount in APT
        let total_staked = total_staked();

        // get the taxable amount which is the total staked amount minus the tax exempt amount
        let staker_info = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        let taxable_amount = if (total_staked > staker_info.tax_exempt_stake) total_staked - staker_info.tax_exempt_stake else 0;

        // exclude fee taken on the taxable amount from the total staked when calculating the share price
        // to avoid the share price to drop when shares are minted to the treasury as fees
        let taxed_total_staked = (total_staked as u256) * (FEE_PRECISION as u256) - (staker_info.fee as u256) * (taxable_amount as u256);

        let price_num = taxed_total_staked * SHARE_PRICE_SCALING_FACTOR;
        let price_denom = shares_supply * (FEE_PRECISION as u256);

        return (price_num, price_denom)
    }

    #[view]
    /// @notice Gets the maximum amount of APT a user can withdraw from the vault.
    /// @param Address of the user under consideration.
    /// @return The maximum amount of APT a user can withdraw.
    public fun max_withdraw(user: address): u64 acquires DelegationPools, StakerInfo {
        let preview = preview_redeem(truAPT::balance_of(user));

        return preview
    }

    #[view]
    /// DEPRECATED in v0.0.2.
    public fun allocations(_user: address): vector<AllocationInfo> {
        abort error::invalid_state(EDEPRECATED)
    }

    #[view]
    /// @notice View function to retrieve delegation pool information for every delegation pool currently supported.
    /// @dev The pools info includes pool address, pool state, and active stake inclusive of add_stake fees.
    /// @return Vector containing individual delegation pool information.
    public fun pools(): (vector<DelegationPoolInfo>) acquires DelegationPools {
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        let pool_infos = vector::empty<DelegationPoolInfo>();
        let current_epoch = current_epoch();

        smart_table::for_each_ref(&pools.delegation_pools, |_address, _pool| {
            let pool: &DelegationPool = _pool;
            let add_stake_fees = 0;
            if (pool.epoch_at_last_update == current_epoch) {
                add_stake_fees = pool.add_stake_fees;
            };

            let (active, _, _) =  delegation_pool::get_stake(*_address, RESOURCE_ACCOUNT);
            let pool_info = DelegationPoolInfo{
                pool_address: *_address,
                pool_state: pool.pool_state,
                stake: active + add_stake_fees
            };
            vector::push_back(&mut pool_infos, pool_info);
        });

        return (pool_infos)
    }

    #[view]
    /// @notice View function to calculate the amount of residual rewards accumulated by the staker.
    /// @dev Residual rewards are staking rewards that accrue on pending inactive stake and belong to the treasury.
    /// They are calculated as the total unlocked stake received by the staker minus the amount users are entitled to withdraw.
    /// @return Amount of residual rewards available for treasury collection.
    public fun preview_residual_rewards(): u64 acquires Unlocks {        
        let unlocks = borrow_global<Unlocks>(RESOURCE_ACCOUNT);
  
        // cumulative APT amount that has been unlocked and is ready for user withdrawals
        let unlocks_awaiting_payout = 0; 

        // APT amount that has been withdrawn from the delegation pool into the staker (incl. rewards)
        let unlocked_amount_received = unlocks.unlocked_amount_received;

        // APT amount that has been paid out to users
        let unlocks_paid = unlocks.unlocks_paid;

        let pools: vector<address> = vector::empty();

        smart_table::for_each_ref(&unlocks.unlocks, |_nonce, _request| {
            let request: &UnlockRequest = _request;
            
            // synchronize state with delegation pool (and underlying stake pool) to ensure the olc is up to date
            delegation_pool::synchronize_delegation_pool(request.delegation_pool);
            
            // if the unlocked amount is ready for withdrawal AND residual_rewards have not been deducted from it
            if (ready_to_withdraw(request.olc, request.delegation_pool) && !request.residual_rewards_collected) {
                // add the claimable amount to the total unlocked amount awaiting payout
                unlocks_awaiting_payout = unlocks_awaiting_payout + request.amount;
            };

            if (!vector::contains(&pools, &request.delegation_pool)) {
                vector::push_back(&mut pools, request.delegation_pool);
            
                let (_, inactive, pending_inactive) = delegation_pool::get_stake(request.delegation_pool, RESOURCE_ACCOUNT);

                // if the delegation pool is inactive
                if (delegation_pool::can_withdraw_pending_inactive(request.delegation_pool)) {
                    
                    // add the pending_inactive amount to the amount received by staker
                    unlocked_amount_received = unlocked_amount_received + pending_inactive;
                };

                unlocked_amount_received = unlocked_amount_received + inactive;
            };

        });
        // residual rewards is the total unlocked amount received by the staker (unlocked_amount_received) during the 
        // unlock period minus the amount users are entitled to withdraw (unlocks_awaiting_payout + unlocks_paid).
        let residual_rewards = 0;
        if (unlocked_amount_received > (unlocks_paid + unlocks_awaiting_payout)) residual_rewards = unlocked_amount_received - (unlocks_paid + unlocks_awaiting_payout);
       
        return residual_rewards
    }

    #[view]
    /// @notice View function to query the whitelist contract address.
    /// @return The whitelist contract address.
    public fun whitelist(): (address) {
        return @whitelist
    }

    // *** INITIALIZER & UPGRADES ***
    /// @notice Initializes the staker.
    /// @param Admin that initialises the contract.
    /// @param Name of the staker contract.
    /// @param Address of the treasury. 
    /// @param Address of the default delegation pool we are staking to. 
    /// @param Treasury staking fee amount. 
    /// @param DEPRECATED `_dist_fee_deprecated` slot
    /// @param Minimum deposit amount in APT that a user has to deposit.
    public entry fun initialize(
        admin: &signer,
        name: String,
        treasury: address,
        default_delegation_pool: address,
        fee: u64,
        _dist_fee_deprecated: u64,
        min_deposit: u64,
    ) acquires Settings {
        check_admin(admin);
        assert!(!exists<StakerInfo>(RESOURCE_ACCOUNT), error::already_exists(ESTAKER_ALREADY_INITIALISED));
        assert!(string::length(&name) < 128, error::invalid_argument(ESTRING_TOO_LONG));
        assert!(treasury != @0x0, error::invalid_argument(EZERO_ADDRESS));
        assert!(fee < FEE_PRECISION, error::invalid_argument(EFEE_TOO_LARGE));
        assert!(_dist_fee_deprecated < FEE_PRECISION, error::invalid_argument(EFEE_TOO_LARGE));
        assert!(min_deposit >= MIN_COINS_ON_SHARES_POOL, error::invalid_argument(EBELOW_MIN_STAKE));
        assert!(delegation_pool::delegation_pool_exists(default_delegation_pool), error::invalid_argument(EINVALID_POOL_ADDRESS));
        assert!(stake::get_validator_state(default_delegation_pool) == VALIDATOR_STATUS_ACTIVE, error::invalid_state(EVALIDATOR_NOT_ACTIVE));

        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);
        
        coin::register<AptosCoin>(&resource_signer);
        if (!account::exists_at(treasury)) aptos_account::create_account(treasury);

        // transfer reserve amount (1 APT) to staker
        coin::transfer<AptosCoin>(admin, RESOURCE_ACCOUNT, ONE_APT);

        truAPT::initialize(&resource_signer);
        let truAPT_coin = truAPT::get_metadata();

        move_to(
            &resource_signer,
            StakerInfo {
                name: name,
                treasury: treasury,
                fee: fee,
                dist_fee: _dist_fee_deprecated,
                min_deposit: min_deposit,
                truAPT_coin: truAPT_coin,
                tax_exempt_stake: 0,
                is_paused: false
            },
        );

        let delegation_pools = smart_table::new();
        let default_pool_struct = DelegationPool{
                pool_address: default_delegation_pool,
                epoch_at_last_update: 0,
                add_stake_fees: 0,
                pool_state: POOL_ENABLED
        };
        smart_table::add(&mut delegation_pools, default_delegation_pool, default_pool_struct);

        // Initialise Delegation Pools
        move_to(
            &resource_signer,
            DelegationPools {
                delegation_pools,
                default_delegation_pool,
            },
        );
        
        // Initialise Unlocks
        move_to(
            &resource_signer,
            Unlocks {
                unlocks: smart_table::new(),
                unlock_nonce: 0,
                unlocked_amount_received: 0,
                unlocks_paid: 0,
            },
        );

        let event = StakerInitialisedEvent {
            name: name,
            treasury: treasury,
            delegation_pool: default_delegation_pool,
            fee: fee,
            dist_fee: _dist_fee_deprecated,
            min_deposit_amount: min_deposit,
            admin: signer::address_of(admin),
        };

        // emit event
        event::emit<StakerInitialisedEvent>(event);
    }

    /// @notice Upgrades the contract.
    /// @param Admin that wants to upgrade. Must be the current admin.
    /// @param Package metadata.
    /// @param Package code.
    public entry fun upgrade_contract(
        admin: &signer, 
        metadata_serialized: vector<u8>, 
        code: vector<vector<u8>>) 
        acquires Settings {
            check_admin(admin);
            let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
            let resource_signer = account::create_signer_with_capability(&settings.signer_cap);
            code::publish_package_txn(&resource_signer, metadata_serialized, code);
    }

    // *** PUBLIC METHODS ***
    // *** VAULT OWNER ADMIN SETTERS ***

    /// @notice Pauses the contract.
    /// @param Admin that wants to pause the contract.
    public entry fun pause(admin: &signer) acquires StakerInfo, Settings {
        check_admin(admin);
        let staker_info_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);
        assert!(!staker_info_mut.is_paused, error::invalid_state(EALREADY_PAUSED));
        staker_info_mut.is_paused = true;

        let event = PauseStateChangedEvent {
            is_paused: true
        };

        // emit event
        event::emit<PauseStateChangedEvent>(event);
    }
    
    /// @notice Unpauses the contract.
    /// @param Admin that wants to unpause the contract.
    public entry fun unpause(admin: &signer) acquires StakerInfo, Settings {
        check_admin(admin);
        let staker_info = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);    
        assert!(staker_info.is_paused, error::invalid_state(EALREADY_UNPAUSED));
        staker_info.is_paused = false;

        let event = PauseStateChangedEvent {
            is_paused: false
        };

        // emit event
        event::emit<PauseStateChangedEvent>(event);
    }

    /// @notice Sets the treasury fee.
    /// @param Admin that wants to alter the treasury fee.
    /// @param New treasury fee of staker vault.
    public entry fun set_fee(admin: &signer, new_fee: u64) acquires StakerInfo, Settings {
        check_admin(admin);
        assert!(new_fee < FEE_PRECISION, error::invalid_argument(EFEE_TOO_LARGE));

        let staker_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);

        let event = SetFeeEvent {
            old_fee: staker_mut.fee,
            new_fee: new_fee,
        };

        // emit event
        event::emit<SetFeeEvent>(event);

        // update
        staker_mut.fee = new_fee;
    }

    /// DEPRECATED in v0.0.2.
    public entry fun set_dist_fee(_admin: &signer, _new_dist_fee: u64) {
        abort error::invalid_state(EDEPRECATED)
    }
    
    /// @notice Sets the minimum APT deposit amount a user must deposit.
    /// @param Admin that wants to alter the minimum deposit amount.
    /// @param Minimum deposit amount in APT that a user has to deposit.
    public entry fun set_min_deposit(admin: &signer, new_min_deposit: u64) acquires StakerInfo, Settings {
        check_admin(admin);
        assert!(new_min_deposit >= MIN_COINS_ON_SHARES_POOL, error::invalid_argument(EBELOW_MIN_STAKE));
        
        let staker_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);

        // emit event
        let event = SetMinDepositEvent {
            old_min_deposit: staker_mut.min_deposit,
            new_min_deposit: new_min_deposit
        };

        // emit event
        event::emit<SetMinDepositEvent>(event);

        // update min deposit
        staker_mut.min_deposit = new_min_deposit;
    }

    /// @notice Sets a new pending admin.
    /// @param Admin that wants to set the pending admin.
    /// @param Pending admin address. 
     public entry fun set_pending_admin(
        admin: &signer,
        pending_admin: address
    ) acquires Settings {
        check_admin(admin);
        assert!(pending_admin != @0x0, error::invalid_argument(EZERO_ADDRESS));

        let settings_mut = borrow_global_mut<Settings>(RESOURCE_ACCOUNT);
        settings_mut.pending_admin = option::some(pending_admin);

        let event = SetPendingAdminEvent {
            current_admin: signer::address_of(admin),
            pending_admin: pending_admin
        };

        // emit event
        event::emit<SetPendingAdminEvent>(event);
    }

    /// @notice Allows the current pending admin to claim the admin role.
    /// @param The new admin. 
    public entry fun claim_admin_role(new_admin: &signer) acquires Settings {
        let settings_mut = borrow_global_mut<Settings>(RESOURCE_ACCOUNT);
        assert!(option::is_some(&settings_mut.pending_admin), error::permission_denied(ENO_PENDING_ADMIN));

        let new_admin_addr = signer::address_of(new_admin);
        let pending_admin_addr = option::borrow(&settings_mut.pending_admin);
        assert!(&new_admin_addr == pending_admin_addr, error::permission_denied(ENOT_PENDING_ADMIN));

        let event = AdminRoleClaimedEvent {
            old_admin: settings_mut.admin,
            new_admin: new_admin_addr
        };

        // emit event
        event::emit<AdminRoleClaimedEvent>(event);

        // update
        settings_mut.pending_admin = option::none();
        settings_mut.admin = new_admin_addr;
    }
    
    /// @notice Sets a new treasury.
    /// @param Admin that wants to alter the treasury.
    /// @param New treasury address. 
     public entry fun set_treasury(
        admin: &signer,
        new_treasury: address
    ) acquires StakerInfo, Settings {
        check_admin(admin);
        assert!(new_treasury != @0x0, error::invalid_argument(EZERO_ADDRESS));
        if (!account::exists_at(new_treasury)) aptos_account::create_account(new_treasury);

        let staker_info_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);

        let event = SetTreasuryEvent {
            old_treasury: staker_info_mut.treasury,
            new_treasury: new_treasury
        };

        // emit event
        event::emit<SetTreasuryEvent>(event);

        // update
        staker_info_mut.treasury = new_treasury;
    }

    /// @notice Sets default delegation pool.
    /// @param Admin that wants to set the default delegation pool.
    /// @param Address of the new default delegation pool.
     public entry fun set_default_pool(
        admin: &signer,
        delegation_pool: address
    ) acquires Settings, DelegationPools {
        check_admin(admin);
        check_delegation_pool(delegation_pool);

        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);

        let event = SetDefaultDelegationPoolEvent {
            old_default_delegation_pool: pools_mut.default_delegation_pool,
            new_default_delegation_pool: delegation_pool
        };

        // emit event
        event::emit<SetDefaultDelegationPoolEvent>(event);

        // update
        pools_mut.default_delegation_pool = delegation_pool;
    }

    // @notice Adds a new delegation pool that users can stake to.
    // @param Admin that wants to add a new delegation pool.
    // @param Address of the new delegation pool.
    public entry fun add_pool(admin: &signer, pool_address: address) acquires Settings, DelegationPools {
        check_admin(admin);
        assert!(pool_address != @0x0, error::invalid_argument(EZERO_ADDRESS));
        assert!(delegation_pool::delegation_pool_exists(pool_address), error::invalid_argument(EINVALID_POOL_ADDRESS));
        
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        assert!(!smart_table::contains(&pools_mut.delegation_pools, pool_address), error::already_exists(EPOOL_ALREADY_EXISTS));
        
        let new_delegation_pool = DelegationPool{
                pool_address: pool_address,
                epoch_at_last_update: 0,
                add_stake_fees: 0,
                pool_state: POOL_ENABLED
        };
        smart_table::add(&mut pools_mut.delegation_pools, pool_address, new_delegation_pool);
         
         let event = DelegationPoolAddedEvent {
            pool_address
        };

        // emit event
        event::emit<DelegationPoolAddedEvent>(event);
    }


    // @notice Disables an existing delegation pool to stop users from staking to it.
    // @param Admin that wants to disable a delegation pool.
    // @param Address of the delegation pool to be disabled.
    public entry fun disable_pool(admin: &signer, pool_address: address) acquires Settings, DelegationPools {
        check_admin(admin);
        assert!(pool_address != @0x0, error::invalid_argument(EZERO_ADDRESS));
        
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&pools_mut.delegation_pools, pool_address), error::invalid_argument(EINVALID_POOL_ADDRESS));
   
        // check current pool state
        let pool_mut = smart_table::borrow_mut(&mut pools_mut.delegation_pools, pool_address);
        assert!(pool_mut.pool_state == POOL_ENABLED, error::invalid_state(EPOOL_ALREADY_DISABLED));

        pool_mut.pool_state = POOL_DISABLED;
        
        let event = DelegationPoolStateChangedEvent {
            pool_address: pool_address,
            old_state: POOL_ENABLED,
            new_state: POOL_DISABLED
        };
        
        // emit event
        event::emit<DelegationPoolStateChangedEvent>(event);
    }

    // @notice Enables a delegation pool for users to stake to.
    // @param Admin that wants to enable a delegation pool.
    // @param Address of the delegation pool to be enabled.
    public entry fun enable_pool(admin: &signer, pool_address: address) acquires Settings, DelegationPools {
        check_admin(admin);
        assert!(pool_address != @0x0, error::invalid_argument(EZERO_ADDRESS));
        
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&pools_mut.delegation_pools, pool_address), error::invalid_argument(EINVALID_POOL_ADDRESS));
   
        // check current pool state
        let pool_mut = smart_table::borrow_mut(&mut pools_mut.delegation_pools, pool_address);
        assert!(pool_mut.pool_state == POOL_DISABLED, error::invalid_state(EPOOL_ALREADY_ENABLED));

        pool_mut.pool_state = POOL_ENABLED;

        let event = DelegationPoolStateChangedEvent {
            pool_address: pool_address,
            old_state: POOL_DISABLED,
            new_state: POOL_ENABLED
        };

        // emit event
        event::emit<DelegationPoolStateChangedEvent>(event);
    }

    /// @notice Collects residual rewards that accumulated upon delegation pool unlocks and transfers them to the treasury.
    /// @dev Residual rewards are staking rewards that accrue on pending inactive stake during an unlock period.
    /// @dev When residual rewards are collected all inactive stake is withdrawn from the delegation pools into the staker,
    /// which will hold the amount belonging to unclaimed unlocks, and the difference gets transferred to the treasury.
    /// @param Admin wanting to collect the residual rewards on behalf of the treasury.
    public entry fun collect_residual_rewards(admin: &signer) acquires Settings, Unlocks, StakerInfo, DelegationPools {
        check_admin(admin);
        
        // get resources    
        let unlocks_mut = borrow_global_mut<Unlocks>(RESOURCE_ACCOUNT);
        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);

        // cumulative APT amount that has been withdrawn from the delegation pool into the staker
        let unlocked_amount_received = unlocks_mut.unlocked_amount_received;
        // cumulative APT amount that has been unlocked and paid out to the users already
        let unlocks_paid = unlocks_mut.unlocks_paid;
        // cumulative APT amount that has been unlocked and is ready for pending withdrawal by users
        let unlocks_awaiting_payout = 0;

        smart_table::for_each_mut(&mut unlocks_mut.unlocks, |_nonce, _request| {
            let request: &mut UnlockRequest = _request;

            // synchronize state with delegation pool (and underlying stake pool) state to ensure the olc is up to date
            delegation_pool::synchronize_delegation_pool(request.delegation_pool);
            
            // if the unlocked amount is ready for withdrawal AND residual_rewards have not yet been deducted from it
            if (ready_to_withdraw(request.olc, request.delegation_pool) && !request.residual_rewards_collected) {
                // add amount to unlocked amount awaiting payout
                unlocks_awaiting_payout = unlocks_awaiting_payout + request.amount;
                request.residual_rewards_collected = true; // set to true, since we are collecting them further down
            };
            
            let (_, inactive, pending_inactive) = delegation_pool::get_stake(request.delegation_pool, RESOURCE_ACCOUNT);

            // if the delegation pool is inactive AND has pending inactive stake that our staker is entitled to
            if (delegation_pool::can_withdraw_pending_inactive(request.delegation_pool) && pending_inactive > 0) {
                // withdraw the pending inactive stake to our staker and add it to the total unlocked amounts received
                delegation_pool::withdraw(&resource_signer, request.delegation_pool, pending_inactive);
                unlocked_amount_received = unlocked_amount_received + pending_inactive;
            };

            // if the pool has inactive stake that our staker is entitled to
            if (inactive > 0) {
                // withdraw the inactive stake and add it to the unlocked amount received
                delegation_pool::withdraw(&resource_signer, request.delegation_pool, inactive);
                unlocked_amount_received = unlocked_amount_received + inactive;
            };
        });

        // residual rewards is the total unlocked APT amount received by the staker (unlocked_amount_received) during 
        // the unlock period minus the unlocked amount that belongs to the users (unlocks_awaiting_payout + unlocks_paid)
        let residual_rewards = 0;
        if (unlocked_amount_received > (unlocks_paid + unlocks_awaiting_payout)) residual_rewards = unlocked_amount_received - (unlocks_paid + unlocks_awaiting_payout);

        
        if (residual_rewards > 0) {
            let (share_price_num, share_price_denom) = share_price();
            let staker_info = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);

            // transfer the residual_rewards to the treasury
            coin::transfer<AptosCoin>(&resource_signer, staker_info.treasury, residual_rewards);
            
            let event = ResidualRewardsCollectedEvent {
                amount: residual_rewards,
                share_price_num: share_price_num,
                share_price_denom: share_price_denom,
                treasury_balance: truAPT::balance_of(staker_info.treasury),

            };

            // emit event
            event::emit<ResidualRewardsCollectedEvent>(event);
        };

        // reset residual reward counters
        unlocks_mut.unlocked_amount_received = 0;
        unlocks_mut.unlocks_paid = 0;
    }

    // *** USER FUNCTIONALITY ***

    /// @notice Transfers APT tokens from the user to the staker and stakes them via the default delegation pool.
    /// @dev Staking requires the amount to be staked to be equal or above to the minimum deposit limit
    /// and to not bring the delegation pool's stake to be greater than the maximum stake limit.
    /// @param User wanting to stake APT.
    /// @param APT amount to be staked.
    public entry fun stake(user: &signer, amount: u64) acquires Settings, StakerInfo, DelegationPools {
        check_not_paused();
        check_whitelist(user);

        let default_delegation_pool = default_pool();
        internal_stake(user, amount, default_delegation_pool);
    }

    /// @notice Transfers APT tokens from the user to the staker and stakes them to a delegation pool.
    /// @dev Staking requires the amount to be staked to be equal or above to the minimum deposit limit
    /// and to not bring the delegation pool's stake to be greater than the maximum stake limit.
    /// @param User wanting to stake APT.
    /// @param APT amount to be staked.
    public entry fun stake_to_specific_pool(user: &signer, amount: u64, delegation_pool: address) acquires Settings, StakerInfo, DelegationPools {
        check_not_paused();
        check_whitelist(user);
        
        internal_stake(user, amount, delegation_pool);
    }

    /// DEPRECATED in v0.0.2.
    public entry fun allocate(_allocator: &signer, _recipient: address, _amount: u64) {
        abort error::invalid_state(EDEPRECATED)
    }

    /// DEPRECATED in v0.0.2.
    public entry fun distribute_rewards(_distributor: &signer, _recipient: address, _in_APT: bool) {
        abort error::invalid_state(EDEPRECATED)
    }

    /// DEPRECATED in v0.0.2.
    public entry fun distribute_all(_distributor: &signer, _in_APT: bool) {
        abort error::invalid_state(EDEPRECATED)
    }

    /// DEPRECATED in v0.0.2.
    public entry fun deallocate(_deallocator: &signer, _recipient: address, _amount: u64) {
        abort error::invalid_state(EDEPRECATED)
    }

    /// @notice Requests to unlock a certain amount of APT from the default delegation pool.
    /// @dev Users must unlock at least 10 APT. If the user's remaining staked amount falls below 10 APT, their entire stake will be withdrawn.
    /// @param User wanting to unlock their assets.
    /// @param APT amount to be unlocked.
    public entry fun unlock(
        user: &signer,
        amount: u64,
    ) acquires Settings, DelegationPools, Unlocks, StakerInfo {
        check_not_paused();
        check_whitelist(user);
        
        let default_delegation_pool = default_pool();
        internal_unlock(user, amount, default_delegation_pool);
    }

    /// @notice Requests to unlock a certain amount of APT from the specified delegation pool.
    /// @dev Users must unlock at least 10 APT. If the user's remaining staked amount falls below 10 APT, their entire stake will be withdrawn.
    /// @param User wanting to unlock their assets.
    /// @param APT amount to be unlocked.
    /// @param Address of the delegation pool to unlock from.
    public entry fun unlock_from_specific_pool(user: &signer, amount: u64, pool: address) acquires Settings, DelegationPools, Unlocks, StakerInfo {
        check_not_paused();
        check_whitelist(user);
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&pools.delegation_pools, pool), error::invalid_argument(EINVALID_POOL_ADDRESS));
        internal_unlock(user, amount, pool);
    }

    /// @notice Withdraws a previously requested and now unlocked APT amount from the staker.
    /// @dev Requires the unlock nonce provided to be valid and the unlock to be ready for withdrawal.
    /// @dev During withdrawal all inactive stake and pending inactive stake (for inactive validators)
    /// gets transferred from the delegation pool to the staker. This is required to ensure that the sum of all APT
    /// received by the staker during withdraw, unlock and collect_residual_rewards operations is greater than 
    /// the sum of all APT withdrawn by users. 
    /// @dev Some accounting is done to keep track of the APT received by the staker and paid out to the user,
    /// which is necessary to calculate the residual rewards.
    /// @param User entitled to their unlocked assets.
    /// @param Unlock nonce of the previously submitted unlock request.
    public entry fun withdraw(user: &signer, unlock_nonce: u64) acquires Settings, StakerInfo, DelegationPools, Unlocks {
        check_not_paused();
        check_whitelist(user);

        internal_withdraw(user, unlock_nonce);
    }

    /// @notice Withdraws multiple previously requested and now unlocked APT amounts from the staker.
    /// @dev Requires the unlock nonces provided to be valid and the unlocks to be ready for withdrawal.
    /// @param Unlock nonces corresponding to matured unlock requests.
    public entry fun withdraw_list(
        user: &signer,
        unlock_nonces: vector<u64>,
    ) acquires Settings, StakerInfo, DelegationPools, Unlocks {
        check_not_paused();
        check_whitelist(user);

        assert!(!vector::is_empty(&unlock_nonces), error::invalid_argument(ENO_NONCES_PROVIDED));

        vector::for_each(unlock_nonces, |unlock_nonce| {
            internal_withdraw(user, unlock_nonce);
        })
    }

    /// @notice Public function to collect treasury fees accumulated on the staking rewards.
    /// @dev Calculates treasury fees on rewards and mints the appropriate number of shares to the treasury.
    /// @dev Fees are calculated only on staking rewards, not on the amount originally staked by the users. Because Aptos delegation pools
    /// automatcally compound the staking rewards some accounting is needed to determine the amount of stake that is taxable.
    public entry fun collect_fees() acquires Settings, StakerInfo, DelegationPools {
        check_not_paused();
        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);

        let total_staked = total_staked();
        let (price_num, price_denom) = share_price();

        // gets the taxable amount
        let staker_info_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);
        let taxable_amount = if (total_staked > staker_info_mut.tax_exempt_stake) total_staked - staker_info_mut.tax_exempt_stake else 0;
        
        // calculate the share increase for the treasury
        let share_increase_treasury = (taxable_amount as u256) * (staker_info_mut.fee as u256) * SHARE_PRICE_SCALING_FACTOR * price_denom / (price_num * (FEE_PRECISION as u256));
        
        if (share_increase_treasury > 0) {
            // mint the shares to the treasury
            truAPT::mint(&resource_signer, staker_info_mut.treasury, (share_increase_treasury as u64));

            let event = FeesCollectedEvent {
                shares_minted: (share_increase_treasury as u64),
                treasury_balance: truAPT::balance_of(staker_info_mut.treasury),
                share_price_num: price_num,
                share_price_denom: price_denom
            };

            // emit event
            event::emit<FeesCollectedEvent>(event);
        };
        
        // update tax exempt stake
        staker_info_mut.tax_exempt_stake = total_staked;

    }

    // *** INTERNAL FUNCTIONS ***

    /// @notice Private method, runs automatically when code is published.
    fun init_module(account: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(account, SRC);
        move_to(account, Settings {
            signer_cap,
            admin: ADMIN,
            pending_admin: option::none()
        });
    }

    /// @notice Checks that the contract is not paused.
    inline fun check_not_paused() acquires StakerInfo, Settings {
        let (_, _, _, _, _, _, _, paused) = staker_info();
        assert!(!paused, error::permission_denied(ECONTRACT_PAUSED));
    }

    /// @notice Checks that the transaction sender is the admin.
    /// @param User address to be checked.
    inline fun check_admin(user: &signer) acquires Settings{
        assert!(is_admin(signer::address_of(user)), error::permission_denied(ENOT_ADMIN));
    }

    /// @notice Checks that the transaction sender is whitelisted.
    /// @param User address to the signer to be checked.
    inline fun check_whitelist(user: &signer) {
        assert!(is_whitelisted(signer::address_of(user)), error::permission_denied(EUSER_NOT_WHITELISTED));
    }

    /// @notice Checks that a deposit amount is not zero and not below the min_deposit amount.
    /// @param APT deposit amount.
    inline fun check_deposit_amount(amount: u64) acquires StakerInfo {
        let staker = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        assert!(amount >= staker.min_deposit, error::invalid_argument(EDEPOSIT_AMOUNT_TOO_SMALL));
    }

    /// @notice Checks that a delegation pool is ready to accept stakes.
    /// @param Address of the delegation pool to be checked.
    inline fun check_delegation_pool(pool_address: address) acquires DelegationPools {
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&pools.delegation_pools, pool_address), error::invalid_argument(EINVALID_POOL_ADDRESS));
        assert!(smart_table::borrow(&pools.delegation_pools, pool_address).pool_state == POOL_ENABLED, error::invalid_state(EPOOL_DISABLED));

        // only validators that are `active` can be staked on.
        assert!(stake::get_validator_state(pool_address) == VALIDATOR_STATUS_ACTIVE, error::invalid_state(EVALIDATOR_NOT_ACTIVE));
    }
    
    /// @notice Checks that an amount will not put the delegation pool over the max staking limit.
    /// @param Amount to be staked.
    /// @param Address of the delegation pool to be checked.
    inline fun check_staked_amount(amount: u64, pool_address: address) {
        let (active, _, pending_active, _) = delegation_pool::get_delegation_pool_stake(pool_address);
        assert!(active + pending_active + amount <= MAX_STAKE_AMOUNT, error::invalid_argument(EPOOL_AT_MAX_CAPACITY));
    }

    /// @notice Checks that a given olc has passed or that a given pool is inactive and allows withdrawals.
    /// @param The olc to be checked. 
    /// @param Address of the delegation pool to be checked.
    fun ready_to_withdraw(olc: u64, pool_address: address) : bool {
        return (olc < delegation_pool::observed_lockup_cycle(pool_address)) || 
        delegation_pool::can_withdraw_pending_inactive(pool_address)
    }

    /// @notice Private function to transfer the APT amount approved by the caller and stake it to the relevant delegation pool.
    /// @param User wanting to stake APT.
    /// @param APT amount to be staked.
    /// @param Address of the delegation pool to be staked to.
    fun internal_stake(user: &signer, amount: u64, delegation_pool: address) acquires Settings, StakerInfo, DelegationPools {
        check_deposit_amount(amount);
        check_delegation_pool(delegation_pool);
        check_staked_amount(amount, delegation_pool);
        synchronize_pool_state(delegation_pool);

        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);

        // receive APT from user.
        coin::transfer<AptosCoin>(user, signer::address_of(&resource_signer), amount);

        // mint user's TruAPT token
        let user_address = signer::address_of(user);
        let share_increase_user = convert_to_shares(amount);
        truAPT::mint(&resource_signer, user_address, share_increase_user);

        // get active stake before new stake
        let(active_before_stake, _, _) = delegation_pool::get_stake(delegation_pool, RESOURCE_ACCOUNT);

        // stake APT to delegation pool
        delegation_pool::add_stake(&resource_signer, delegation_pool, amount);
        
        // get active stake after new stake
        let(active_after_stake, _, _) = delegation_pool::get_stake(delegation_pool, RESOURCE_ACCOUNT);

        // calculate the delegation pool's "add stake fee" for this stake
        let add_stake_fee = amount - (active_after_stake - active_before_stake);

        // add the "add stake fee" amount to the staker's total amount of staking fees paid to this delegation pool for this epoch.
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        let pool_mut = smart_table::borrow_mut(&mut pools_mut.delegation_pools, delegation_pool);
        pool_mut.add_stake_fees = pool_mut.add_stake_fees + add_stake_fee;
        
        // fees are only charged on rewards, not on the initial stake
        let staker_info_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);
        staker_info_mut.tax_exempt_stake = staker_info_mut.tax_exempt_stake + amount;

        let(global_price_num, global_price_denom) = share_price();

        let event = DepositedEvent {
            user: user_address,
            amount: amount,
            user_balance: truAPT::balance_of(user_address),
            shares_minted: share_increase_user,
            total_staked: total_staked(),
            total_supply: total_shares(),
            share_price_num: global_price_num,
            share_price_denom: global_price_denom,
            delegation_pool: delegation_pool
        };

        // emit event
        event::emit<DepositedEvent>(event);
    }

    /// @notice Private function to handle unlocks and burning of user shares.
    /// @param User wanting to unlock their assets.
    /// @param APT amount to be unlocked.
    /// @param Address of the delegation pool to unlock from.
    fun internal_unlock(account: &signer, amount: u64, pool: address) acquires Settings, Unlocks, DelegationPools, StakerInfo{
        assert!(amount >= MIN_COINS_ON_SHARES_POOL, error::invalid_argument(EBELOW_MIN_UNLOCK));
        synchronize_pool_state(pool);

        // confirm the user has enough TruAPT to unlock
        let receiver = signer::address_of(account);
        let max_withdraw = max_withdraw(receiver);
        assert!(amount <= max_withdraw, error::invalid_argument(EINSUFFICIENT_BALANCE));

        // Unlocking reduces the active stake, ie the total staked amount.
        // The total staked amount is used to determine the taxable amount inside collect_fees().
        // Thus fees must be charged before unlocking.
        // Assumes no slashing enabled.
        collect_fees();

        let truAPT_amount;
        // if user's remaining balance falls below threshold, withdraw entire user stake
        if (max_withdraw - amount < MIN_COINS_ON_SHARES_POOL) {
            amount = max_withdraw;
            truAPT_amount = truAPT::balance_of(receiver);
        } else {
            truAPT_amount = convert_to_shares(amount);
        };
        
        // confirm that remaining active balance on pool after this unlock would be >= 10 APT
        // otherwise pool would become inactive (Aptos delegation pool requirement)
        let (active, _, pending_inactive_pre_unlock) = delegation_pool::get_stake(pool, RESOURCE_ACCOUNT);
        assert!(active >= amount + MIN_COINS_ON_SHARES_POOL, error::invalid_argument(EUNLOCK_AMOUNT_TOO_HIGH));

        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);

        // burn truAPT token
        truAPT::burn(&resource_signer, receiver, truAPT_amount);

        // get staker APT balance before unlock
        let balance_before = coin::balance<AptosCoin>(RESOURCE_ACCOUNT);     
        
        // the unlock operation moves the APT amount from active to pending inactive stake.
        // Any inactive stake will be automatically transferred back to the staker.
        delegation_pool::unlock(&resource_signer, pool, amount);
        
        let staker_info_mut = borrow_global_mut<StakerInfo>(RESOURCE_ACCOUNT);

        // update the amount of already taxed stake (fees were already charged above)
        staker_info_mut.tax_exempt_stake = if (staker_info_mut.tax_exempt_stake > amount) staker_info_mut.tax_exempt_stake - amount else 0;

        // pending inactive staker balance after unlock
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool, RESOURCE_ACCOUNT);

        // check how much was actually unstaked by calculating the difference in pending inactive stake
        // the requested unlock amount should transition to pending_inactive (with a small margin of error)
        // this check makes sure that the unstaked APT will exactly match the amount of TruAPT burned above, such that the share price will remain constant.
        let unstaked_apt = pending_inactive - pending_inactive_pre_unlock;
        assert!(amount >= unstaked_apt && amount <= unstaked_apt + 2, error::invalid_argument(EINVALID_UNSTAKED_AMOUNT));

        // create unlock request
        let unlock_nonce = increment_unlock_nonce();
        let olc = delegation_pool::observed_lockup_cycle(pool);
        let unlock_request = UnlockRequest{
            amount: amount,
            user: receiver,
            olc: olc,
            delegation_pool: pool,
            residual_rewards_collected: false
        };

        // get staker APT balance after unlock
        let unlocks_mut = borrow_global_mut<Unlocks>(RESOURCE_ACCOUNT);
        let balance_after = coin::balance<AptosCoin>(RESOURCE_ACCOUNT);
        // unlocks on Aptos' delegation pool can trigger a withdrawal of all the inactive stake, which needs to be accounted for
        // (crucial for accurate residual rewards calculation)
        unlocks_mut.unlocked_amount_received = unlocks_mut.unlocked_amount_received + (balance_after - balance_before);

        // add unlock request to the global unlocks table (accessed by unlock nonce)
        smart_table::add(&mut unlocks_mut.unlocks, unlock_nonce, unlock_request);

        let (global_price_num, global_price_denom) = share_price();

        let event = UnlockedEvent {
            user: receiver,
            amount: amount,
            unlock_nonce: unlock_nonce,
            olc: olc,
            user_balance: truAPT::balance_of(receiver),
            shares_burned: truAPT_amount,
            total_staked: total_staked(),
            total_supply: total_shares(),
            share_price_num: global_price_num,
            share_price_denom: global_price_denom,
            delegation_pool: pool
        };
        
        // emit event
        event::emit<UnlockedEvent>(event);
    }

    /// @notice Private function that withdraws a previously requested and now unlocked APT amount from the staker.
    /// @param User entitled to their unlocked assets.
    /// @param Unlock nonce of the previously submitted unlock request.
    fun internal_withdraw(user: &signer, unlock_nonce: u64) acquires Settings, DelegationPools, Unlocks {
        // get the user's unlock request
        let unlocks_mut = borrow_global_mut<Unlocks>(RESOURCE_ACCOUNT);
        assert!(smart_table::contains(&unlocks_mut.unlocks, unlock_nonce), error::invalid_argument(EINVALID_NONCE));
        let UnlockRequest{
            amount, 
            user:receiver, 
            olc, 
            delegation_pool, 
            residual_rewards_collected} = smart_table::remove(&mut unlocks_mut.unlocks, unlock_nonce);

        // confirm the signer is entitled to the unlocked amount
        let user_addr = signer::address_of(user);
        assert!(user_addr == receiver, error::permission_denied(ESENDER_MUST_BE_RECEIVER));
        
        // synchronize state with delegation pool (and underlying stake pool) state
        synchronize_pool_state(delegation_pool);
        delegation_pool::synchronize_delegation_pool(delegation_pool);

        // check whether unlock is ready OR the pool is inactive and one olc has passed (in which case all unlocks can be 
        // immediately withdrawn)
        assert!(ready_to_withdraw(olc, delegation_pool), error::permission_denied(EWITHDRAW_NOT_READY));

        // access resource signer to withdraw from pool   
        let settings = borrow_global<Settings>(RESOURCE_ACCOUNT);
        let resource_signer = account::create_signer_with_capability(&settings.signer_cap);

        let (_, inactive, pending_inactive) = delegation_pool::get_stake(delegation_pool, RESOURCE_ACCOUNT);

        // Withdraw

        if (delegation_pool::can_withdraw_pending_inactive(delegation_pool) && pending_inactive > 0) {
            // if delegation pool is inactive, claimable stake is not moved to inactive. 
            // Instead, the pending_inactive amount is withdrawn.
            delegation_pool::withdraw(&resource_signer, delegation_pool, pending_inactive);
            unlocks_mut.unlocked_amount_received = unlocks_mut.unlocked_amount_received + pending_inactive;
        };
    
        if (inactive > 0) {
            delegation_pool::withdraw(&resource_signer, delegation_pool, inactive);
            unlocks_mut.unlocked_amount_received = unlocks_mut.unlocked_amount_received + inactive;
        };

        // if residual_rewards have not been collected for this unlock request, we add the unlock amount to the unlocks_paid.
        if (!residual_rewards_collected) unlocks_mut.unlocks_paid = unlocks_mut.unlocks_paid + amount;
        
        // transfer APT to user
        coin::transfer<AptosCoin>(&resource_signer, user_addr, amount);

        let event = WithdrawalClaimedEvent {
            user: user_addr,
            amount: amount,
            unlock_nonce: unlock_nonce,
            olc: delegation_pool::observed_lockup_cycle(delegation_pool),
            delegation_pool: delegation_pool
        };
        
        // emit event
        event::emit<WithdrawalClaimedEvent>(event);
    }

    /// @notice Convert an amount of APT tokens to the equivalent TruAPT amount, rounding the result down.
    /// @param An amount of APT tokens.
    /// @return The number of TruAPT shares.
    fun convert_to_shares(assets: u64): (u64) acquires DelegationPools, StakerInfo {
        let (price_num, price_denom) = share_price();

        // price_num is scaled by SHARE_PRICE_SCALING_FACTOR, hence we must multiply by the same factor 
        let shares = (assets as u256) * SHARE_PRICE_SCALING_FACTOR * price_denom / price_num;

        return (shares as u64)
    }

    /// @notice Returns the amount of APT that can be withdrawn for an amount of TruAPT, rounding the result up.
    /// @param An amount of TruAPT tokens.
    /// @return An amount of APT tokens.
    fun preview_redeem(shares: u64): u64 acquires DelegationPools, StakerInfo {
        return convert_to_assets_with_rounding(shares, true)
    }

    /// @notice Convert an amount of TruAPT tokens to the equivalent value of APT, rounding the result down.
    /// @param An amount of TruAPT tokens.
    /// @return An amount of APT tokens.
    fun convert_to_assets(shares: u64): u64 acquires DelegationPools, StakerInfo {
        return convert_to_assets_with_rounding(shares, false)
    }

    /// @notice Convert an amount of TruAPT tokens to the equivalent APT amount with specified rounding.
    /// @param An amount of TruAPT tokens.
    /// @param Boolean indicating whether the APT amount is rounded up (True) or down (False).
    /// @return An amount of APT tokens.
    fun convert_to_assets_with_rounding(shares: u64, rounding_up: bool): u64 acquires DelegationPools, StakerInfo {
        let (price_num, price_denom) = share_price();

        let assets_num = (shares as u256) * price_num;
        let assets_denom = price_denom * SHARE_PRICE_SCALING_FACTOR;

        let assets = assets_num / assets_denom;
        if (rounding_up) {
            let remainder = assets_num % assets_denom;
            if (remainder > 0) assets = assets + 1;
        };

        return (assets as u64)
    }

    /// @notice Increments the unlock nonce by one and returns it to the caller.
    /// @return A new unlock nonce.
    fun increment_unlock_nonce(): (u64) acquires Unlocks {
        let unlocks_mut = borrow_global_mut<Unlocks>(RESOURCE_ACCOUNT);
        unlocks_mut.unlock_nonce = unlocks_mut.unlock_nonce + 1;
        
        return unlocks_mut.unlock_nonce
    }
    
    /// @notice Synchronizes state with delegation pool.
    /// @param Address of the delegation pool to synchronize state with.
    fun synchronize_pool_state(delegation_pool: address) acquires DelegationPools {
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        let pool_mut = smart_table::borrow_mut(&mut pools_mut.delegation_pools, delegation_pool);
        let current_epoch = current_epoch();
        if (pool_mut.epoch_at_last_update < current_epoch) {
            pool_mut.epoch_at_last_update = current_epoch;
            pool_mut.add_stake_fees = 0;
        }
    }

    // *** TEST-ONLY FUNCTIONS ***

    #[test_only]
    public fun test_initialize(user: &signer) {
        init_module(user);
    }

    #[test_only]
    public entry fun test_unlock_request(nonce: u64) : (u64, address, u64, address) acquires Unlocks {
        let unlocks = borrow_global<Unlocks>(RESOURCE_ACCOUNT);
        let UnlockRequest{amount, user, olc, delegation_pool, residual_rewards_collected:_} = smart_table::borrow(&unlocks.unlocks, nonce); 
        return (*amount, *user, *olc, *delegation_pool)
    }

    #[test_only]
    public entry fun test_set_pool(delegation_pool: address) acquires DelegationPools {
        let pools_mut = borrow_global_mut<DelegationPools>(RESOURCE_ACCOUNT);
        pools_mut.default_delegation_pool = delegation_pool;
        let new_pool = DelegationPool{
                pool_address: delegation_pool,
                epoch_at_last_update: 0,
                add_stake_fees: 0,
                pool_state: POOL_ENABLED
        };
        smart_table::add(&mut pools_mut.delegation_pools, delegation_pool, new_pool);
    }

    #[test_only]
    public entry fun tax_exempt_stake(): u64 acquires StakerInfo {
        let staker_info = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        return staker_info.tax_exempt_stake
    }

    #[view]
    #[test_only]
    public entry fun test_pool(pool_address: address): (address, u64, u64, u8) acquires DelegationPools {
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        let DelegationPool{pool_address, epoch_at_last_update, add_stake_fees, pool_state} = smart_table::borrow(&pools.delegation_pools, pool_address); 
        return (*pool_address, *epoch_at_last_update, *add_stake_fees, *pool_state)
    }

    #[view]
    #[test_only]
    public entry fun test_fee_precision(): u64 {
        return FEE_PRECISION
    }

    #[view]
    #[test_only]
    public entry fun test_min_coins_on_share_pool(): u64 {
        return MIN_COINS_ON_SHARES_POOL
    }

    #[view]
    #[test_only]
    public fun test_DelegationPoolInfo(pool_address: address, pool_state: u8, stake: u64): DelegationPoolInfo {
        let pool = DelegationPoolInfo{
            pool_address,
            pool_state,
            stake
        };
        return pool
    }

    #[view]
    #[test_only]
    public fun test_StakerInitialisedEvent(
        name: String, 
        treasury: address,
        delegation_pool: address,
        fee: u64,
        dist_fee: u64,
        min_deposit_amount: u64,
        admin: address
        ): StakerInitialisedEvent {
        let event = StakerInitialisedEvent {
            name,
            treasury,
            delegation_pool,
            fee,
            dist_fee,
            min_deposit_amount,
            admin
        };
        return event
    }   
    
    #[view]
    #[test_only]
    public fun test_DepositedEvent(
        user: address, 
        amount: u64,
        shares_minted: u64,
        ): DepositedEvent acquires DelegationPools, StakerInfo {
        let (share_price_num, share_price_denom) = share_price();
        let total_staked = total_staked();
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);

        let event = DepositedEvent {
            user,
            amount,
            user_balance: truAPT::balance_of(user),
            shares_minted,
            total_staked: total_staked,
            total_supply: total_shares(),
            share_price_num,
            share_price_denom,
            delegation_pool: pools.default_delegation_pool
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_UnlockedEvent(
        user: address,
        amount: u64,
        unlock_nonce: u64,
        shares_burned: u64,
        ): UnlockedEvent acquires DelegationPools, StakerInfo {
        let total_staked = total_staked();
        let (share_price_num, share_price_denom) = share_price();
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);
        
        let event = UnlockedEvent {
            user,
            amount,
            olc: delegation_pool::observed_lockup_cycle(pools.default_delegation_pool),
            unlock_nonce,
            user_balance: truAPT::balance_of(user),
            shares_burned,
            total_staked: total_staked,
            total_supply: total_shares(),
            share_price_num,
            share_price_denom,
            delegation_pool: pools.default_delegation_pool,
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_WithdrawalClaimedEvent(user: address, amount: u64, unlock_nonce: u64): WithdrawalClaimedEvent acquires DelegationPools {
        let pools = borrow_global<DelegationPools>(RESOURCE_ACCOUNT);        
        let event = WithdrawalClaimedEvent {
            user,
            amount,
            unlock_nonce,
            olc: delegation_pool::observed_lockup_cycle(pools.default_delegation_pool),
            delegation_pool: pools.default_delegation_pool
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_PauseStateChangedEvent(is_paused: bool): PauseStateChangedEvent {
        let event = PauseStateChangedEvent {
            is_paused
        };
        return event
    }  

    #[view]
    #[test_only]
    public fun test_SetPendingAdminEvent(current_admin: address, pending_admin: address): SetPendingAdminEvent {
        let event = SetPendingAdminEvent {
            current_admin,
            pending_admin
        };
        return event
    }  
   
    #[view]
    #[test_only]
    public fun test_AdminRoleClaimedEvent(old_admin: address, new_admin: address): AdminRoleClaimedEvent {
        let event = AdminRoleClaimedEvent {
            old_admin,
            new_admin
        };
        return event
    }  
    
    #[view]
    #[test_only]
    public fun test_SetTreasuryEvent(old_treasury: address, new_treasury: address): SetTreasuryEvent {
        let event = SetTreasuryEvent {
            old_treasury,
            new_treasury
        };
        return event
    }  

    #[view]
    #[test_only]
    public fun test_SetDefaultDelegationPoolEvent(
        old_default_delegation_pool: address, 
        new_default_delegation_pool: address
    ): SetDefaultDelegationPoolEvent {
        let event = SetDefaultDelegationPoolEvent {
            old_default_delegation_pool,
            new_default_delegation_pool
        };
        return event
    } 

    #[view]
    #[test_only]
    public fun test_SetFeeEvent(old_fee: u64, new_fee: u64): SetFeeEvent {
        let event = SetFeeEvent {
            old_fee,
            new_fee
        };
        return event
    } 

    #[view]
    #[test_only]
    public fun test_SetMinDepositEvent(old_min_deposit: u64, new_min_deposit: u64): SetMinDepositEvent {
        let event = SetMinDepositEvent {
            old_min_deposit,
            new_min_deposit
        };
        return event
    } 
    
    #[view]
    #[test_only]
    public fun test_DelegationPoolAddedEvent(pool_address: address): DelegationPoolAddedEvent {
        let event = DelegationPoolAddedEvent {
            pool_address
        };
        return event
    } 

    #[view]
    #[test_only]
    public fun test_DelegationPoolStateChangedEvent(pool_address: address, old_state: u8, new_state: u8): DelegationPoolStateChangedEvent {
        let event = DelegationPoolStateChangedEvent {
            pool_address,
            old_state, 
            new_state
        };
        return event
    } 
    
    #[view]
    #[test_only]
    public fun test_ResidualRewardsCollectedEvent(amount: u64): ResidualRewardsCollectedEvent
    acquires StakerInfo, DelegationPools {
        let (share_price_num, share_price_denom) = share_price();
        let staker_info = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        let event = ResidualRewardsCollectedEvent {
            amount,
            share_price_num,
            share_price_denom,
            treasury_balance: truAPT::balance_of(staker_info.treasury)
        };
        return event
    }

    #[view]
    #[test_only]
    public fun test_FeesCollectedEvent(shares_minted: u64, share_price_num: u256, share_price_denom: u256): FeesCollectedEvent
    acquires StakerInfo {
        let staker_info = borrow_global<StakerInfo>(RESOURCE_ACCOUNT);
        let event = FeesCollectedEvent {
            shares_minted,
            treasury_balance: truAPT::balance_of(staker_info.treasury),
            share_price_num,
            share_price_denom
        };
        return event
    }
}