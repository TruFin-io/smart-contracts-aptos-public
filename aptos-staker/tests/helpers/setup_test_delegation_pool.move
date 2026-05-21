#[test_only]
module publisher::setup_test_delegation_pool {
    use std::features;
    use std::signer;

    use aptos_framework::delegation_pool::{initialize_test_validator_custom};
    use aptos_framework::stake;
    use aptos_framework::reconfiguration;
    use aptos_framework::delegation_pool; 

    // test modules
    use publisher::constants;

    friend publisher::init_test;
    friend publisher::setter_test;
    friend publisher::stake_test;
    friend publisher::unlock_test;
    friend publisher::withdraw_test;
    friend publisher::share_price_test;
    friend publisher::multi_validator_test;
    friend publisher::total_staked_test;
    friend publisher::getter_test;
    friend publisher::setup_test_staker;
    friend publisher::residual_rewards_test;
    friend publisher::fees_test;
    friend publisher::withdraw_list_test;

    public(friend) fun setup(aptos_framework: &signer) {
        reconfiguration::initialize_for_test(aptos_framework);
        features::change_feature_flags_for_testing(aptos_framework, 
                                       vector[
                                        constants::pools(), 
                                        constants::module_event(),
                                        constants::operator_beneficiary_change()], vector[]);
        
        stake::initialize_for_test_custom(
            aptos_framework,
            100 * constants::one_apt(),  // min deposit
            100_000_000 * constants::one_apt(), // max deposit
            constants::lockup_cycle_seconds(), // recurring lockup secs
            true,   // allow validator set change
            1,  // rewards rate numerator
            100,    // rewards rate denominator
            10_000_000 * constants::one_apt(), // voting power increase limit
        );
    }
    
    public(friend) fun create_basic_pool(
        validator: &signer,
    ): address {
        // initialise delegation pool setup
        return create_delegation_pool(
            validator,
            100 * constants::one_apt(),  // initial deposit by validator
            true,   // should join validator set
            true,   // should end epoch
            0 // initialize with zero commission for simplicity
        )
    }
    
    public(friend) fun create_delegation_pool(   
        validator: &signer,
        initial_deposit: u64,
        should_join_validator_set: bool,
        should_end_epoch: bool,
        commission_percentage: u64
    ): address {
        initialize_test_validator_custom(
            validator,
            initial_deposit,
            should_join_validator_set,
            should_end_epoch,
            commission_percentage
        );
        
        let delegation_pool = delegation_pool::get_owned_pool_address(signer::address_of(validator));
        return delegation_pool
    }
}