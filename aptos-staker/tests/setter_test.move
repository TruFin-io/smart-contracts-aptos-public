#[test_only]
module publisher::setter_test{
    use std::signer;
    use std::vector;
    
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::stake;

    // smart contracts
    use publisher::staker::{Self, staker_info, set_pending_admin, set_default_pool, test_fee_precision, set_treasury};

    // test modules
    use publisher::constants;
    use publisher::setup_test_staker;
    use publisher::setup_test_delegation_pool;

//  _____________________________ Setter Tests _____________________________
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_set_min_deposit(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        // set minimum deposit
        staker::set_min_deposit(admin, 100000000000); // set to 1000 APT

        // Check min_deposit_amount was updated
        let (_, _, _, _, new_min_deposit, _, _, _) = staker_info();
        assert!(new_min_deposit == 100000000000, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65555, location=staker)]
    public entry fun test_set_min_deposit_to_zero_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        // set minimum deposit to zero
        staker::set_min_deposit(admin, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_set_min_deposit_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        // set minimum deposit to zero
        staker::set_min_deposit(src, 10);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    public entry fun test_set_fee(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set fee
        staker::set_fee(admin, 7);

        let (_, _, fee, _, _, _, _, _) = staker_info();
        assert!(fee == 7, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_set_fee_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        // set fee
        staker::set_fee(src, 10);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=65541, location=staker)]
    public entry fun test_set_fee_with_fee_too_large_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
       
        setup_test_staker::setup(admin, resource_account, src);

        let max_fees = test_fee_precision();
        
        // fails with EFEE_TOO_LARGE
        staker::set_fee(admin, max_fees);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    public entry fun test_set_new_admin(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set admin
        set_pending_admin(admin, signer::address_of(&alice));

        // admin should not change until alice confirms it
        let (_, _, _, _, _, admin_addr, _, _) = staker_info();
        assert!(admin_addr == signer::address_of(admin), 0);

        staker::claim_admin_role(&alice);

        assert!(staker::is_admin(signer::address_of(&alice)), 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_set_new_admin_to_wrong_address_first(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set admin to wrong address
        set_pending_admin(admin, signer::address_of(src));
        // set to correct address
        set_pending_admin(admin, signer::address_of(&alice));

        staker::claim_admin_role(&alice);

        assert!(staker::is_admin(signer::address_of(&alice)), 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327711, location=staker)]
    public entry fun test_claim_admin_role_no_pending_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        staker::claim_admin_role(src); //ENO_PENDING_ADMIN
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327712, location=staker)]
    public entry fun test_claim_admin_role_not_pending_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
       let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set admin
        set_pending_admin(admin, signer::address_of(&alice));
        
        staker::claim_admin_role(src); //ENOT_PENDING_ADMIN
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_set_pending_admin_to_zero_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set admin
        set_pending_admin(admin, @0x0); //EZERO_ADDRESS
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_set_pending_admin_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let alice = account::create_account_for_test(@0x123);
        let bob = account::create_account_for_test(@0x1234);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set admin
        set_pending_admin(&alice, signer::address_of(&bob)); //ENOT_ADMIN
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_set_treasury(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let treasury = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set treasury
        set_treasury(admin, signer::address_of(&treasury));

        let (_, new_treasury, _, _, _, _, _, _) = staker_info();
        assert!(new_treasury == signer::address_of(&treasury), 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_set_treasury_creates_treasury_account_if_no_account_exists(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);

        // check treasury does not have an account
        let treasury_account_exists = account::exists_at(@0x12388);
        assert!(!treasury_account_exists, 0);

        // set treasury
        set_treasury(admin, @0x12388);

        // check treasury does have an account
        let treasury_account_exists = account::exists_at(@0x12388);
        assert!(treasury_account_exists, 0);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65539, location=staker)]
    public entry fun test_set_treasury_to_zero_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let treasury = account::create_account_for_test(@0x00);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set treasury
        set_treasury(admin, signer::address_of(&treasury));
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_set_treasury_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        let alice = account::create_account_for_test(@0x123);
        let treasury = account::create_account_for_test(@0x1234);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set treasury
        set_treasury(&alice, signer::address_of(&treasury));
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_set_default_pool(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer,
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        // add a new delegation pool
        let new_pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, new_pool);
            
        // set default delegation pool
        set_default_pool(admin, new_pool);

        let default_pool_address = staker::default_pool();
        assert!(default_pool_address == new_pool, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_set_default_pool_to_zero_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set default delegation pool
        set_default_pool(admin, @0x00); // EINVALID_POOL_ADDRESS
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_set_default_pool_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        // add a new delegation pool
        let new_pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, new_pool);

        // set default delegation pool
        set_default_pool(&alice, new_pool); // ENOT_ADMIN
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=65550, location=staker)]
    public entry fun test_set_default_pool_to_invalid_pool_address_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // set default pool
        set_default_pool(admin, @0x1234); // EINVALID_POOL_ADDRESS
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=196625, location=staker)]
    public entry fun test_set_default_pool_to_disabled_pool_fails(
        aptos_framework: &signer,
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);
        
        // add a new delegation pool
        let new_pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, new_pool);
        staker::disable_pool(admin, new_pool);
            
        // set default pool
        set_default_pool(admin, new_pool); // EPOOL_DISABLED
    }

    #[test(admin = @default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    #[expected_failure(abort_code=196635, location=staker)]
    public entry fun test_set_default_pool_to_inactive_pool_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer
    ) {
        // initialise staker
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        let pool = setup_test_delegation_pool::create_basic_pool(admin);

        staker::add_pool(admin, pool);

        stake::leave_validator_set(admin, pool);

        staker::set_default_pool(admin, pool); // aborts with EVALIDATOR_NOT_ACTIVE
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_pause_contract(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        let (_, _, _, _, _, _, _, paused) = staker_info();
        assert!(!paused, 0);
        
        staker::pause(admin);
        
        let (_, _, _, _, _, _, _, paused) = staker_info();
        assert!(paused, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    public entry fun test_unpause_contract(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        staker::pause(admin);

        let (_, _, _, _, _, _, _, paused) = staker_info();
        assert!(paused, 0);

        staker::unpause(admin);

        let (_, _, _, _, _, _, _, paused) = staker_info();
        assert!(!paused, 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_pause_contract_not_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::pause(src); // ENOT_ADMIN
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_unpause_contract_not_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::pause(admin);

        staker::unpause(src); // ENOT_ADMIN
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=196638, location=staker)]
    public entry fun test_unpause_unpaused_contract_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::unpause(admin); // EALREADY_UNPAUSED
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]
    #[expected_failure(abort_code=196637, location=staker)]
    public entry fun test_pause_paused_contract_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::pause(admin); 
        staker::pause(admin); // EALREADY_PAUSED
    }

 //  _____________________________ Event Emission Tests _____________________________
    #[test(admin=@default_admin, resource_account=@publisher, src = @src_account)]
    public entry fun test_SetPendingAdmin_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        // pending admin
        let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // action that emits event
        staker::set_pending_admin(admin, signer::address_of(&alice));

        // assert number of emitted events
        let set_pending_admin_events = event::emitted_events<staker::SetPendingAdminEvent>();
        assert!(vector::length(&set_pending_admin_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_SetPendingAdminEvent(signer::address_of(admin), @0x123);
        assert!(event::was_event_emitted(&expected_event), 0);
    } 
    
    #[test(admin=@default_admin, resource_account=@publisher, src = @src_account)]
    public entry fun test_AdminRoleClaimedEvent_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        // new admin
        let alice = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // action that emits event
        staker::set_pending_admin(admin, signer::address_of(&alice));
        staker::claim_admin_role(&alice);

        // assert number of emitted events
        let set_admin_events = event::emitted_events<staker::AdminRoleClaimedEvent>();
        assert!(vector::length(&set_admin_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_AdminRoleClaimedEvent(signer::address_of(admin), @0x123);
        assert!(event::was_event_emitted(&expected_event), 0);
    } 

    #[test(admin=@default_admin, resource_account=@publisher, src = @src_account)]
    public entry fun test_setTreasuryEvent_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        // new treasury
        let treasury = account::create_account_for_test(@0x123);

        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
            
        // action that emits event
        staker::set_treasury(admin, signer::address_of(&treasury));

        // assert number of emitted events
        let set_treasury_events = event::emitted_events<staker::SetTreasuryEvent>();
        assert!(vector::length(&set_treasury_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_SetTreasuryEvent(@0x122, signer::address_of(&treasury));
        assert!(event::was_event_emitted(&expected_event), 0);
    } 

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account, aptos_framework=@0x1)]
    public entry fun test_setDefaultDelegationPoolEvent_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
        aptos_framework: &signer,
    ) { 
        // initialise staker
        let initial_default_pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, src);

        // add a new delegation pool
        let new_pool = setup_test_delegation_pool::create_basic_pool(admin);
        staker::add_pool(admin, new_pool);
            
        // perform action
        set_default_pool(admin, new_pool);

        // assert number of emitted events
        let set_default_pool_events = event::emitted_events<staker::SetDefaultDelegationPoolEvent>();
        assert!(vector::length(&set_default_pool_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_SetDefaultDelegationPoolEvent(initial_default_pool, new_pool);
        assert!(event::was_event_emitted(&expected_event), 0);
    } 

    #[test(admin=@default_admin, resource_account=@publisher, 
    src = @src_account)]
    public entry fun test_SetFeeEvent_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        // initialise staker
        setup_test_staker::setup(admin, resource_account, src);
        let new_fee = 888;

        // action emits event
        staker::set_fee(admin, new_fee);

        // assert number of emitted events
        let set_fee_events = event::emitted_events<staker::SetFeeEvent>();
        assert!(vector::length(&set_fee_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_SetFeeEvent(constants::default_fee(), new_fee);
        assert!(event::was_event_emitted(&expected_event), 0);
    } 

    #[test(admin=@default_admin, resource_account=@publisher,
    src=@src_account)]
    public entry fun test_SetMinDepositEvent_emitted(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        setup_test_staker::setup(admin, resource_account, src);
        
        // set minimum deposit
        let new_min_deposit = 10_000_000_000_000;
        staker::set_min_deposit(admin, new_min_deposit);

        // assert number of emitted events
        let set_min_deposit_events = event::emitted_events<staker::SetMinDepositEvent>();
        assert!(vector::length(&set_min_deposit_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_SetMinDepositEvent(constants::default_min_deposit(), new_min_deposit);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, 
    src=@src_account)]
    public entry fun test_PauseStateChangedEvent_emitted_when_paused(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::pause(admin);

        // assert number of emitted events
        let contract_state_changed_events = event::emitted_events<staker::PauseStateChangedEvent>();
        assert!(vector::length(&contract_state_changed_events) == 1, 0);

        // assert event contents
        let expected_event = staker::test_PauseStateChangedEvent(true);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
    
    #[test(admin=@default_admin, resource_account=@publisher, 
    src=@src_account)]
    public entry fun test_PauseStateChangedEvent_emitted_when_unpaused(
        admin: &signer,
        resource_account: &signer,
        src: &signer,
    ) { 
        setup_test_staker::setup(admin, resource_account, src);
        
        staker::pause(admin);
        staker::unpause(admin);

        // assert number of emitted events
        let contract_state_changed_events = event::emitted_events<staker::PauseStateChangedEvent>();
        assert!(vector::length(&contract_state_changed_events) == 2, 0);

        // assert event contents
        let expected_event = staker::test_PauseStateChangedEvent(false);
        assert!(event::was_event_emitted(&expected_event), 0);
    }
}