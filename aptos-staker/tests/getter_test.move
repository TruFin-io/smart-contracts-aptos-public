#[test_only]
module publisher::getter_test{
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool; 

    // smart contracts
    use publisher::staker::{Self, test_DelegationPoolInfo, pools, default_pool, stake_to_specific_pool, add_pool, disable_pool};

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::setup_test_delegation_pool;
    use publisher::time;

    // Validator-related constants
    const POOL_ENABLED: u8 = 1;
    const POOL_DISABLED: u8 = 2;

// -------------------------------- Get Max Withdraw ------------------------------------------
    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3)]
    public entry fun test_max_withdraw_is_zero_if_no_deposits(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw == 0, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_max_withdraw_before_epoch_ends(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        staker::stake(alice, deposit_amount);

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw == deposit_amount, 0);
    }


    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_max_withdraw_after_epoch_ends(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw == deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_max_withdraw_is_greater_than_just_deposited_amount_after_accrual(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();

        // time passes
        time::move_olc_and_epoch_forward();

        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw > deposit_amount, 0);
    }

    #[test(alice=@0xE0A1, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_max_withdraw_is_zero_after_unlocking_entire_deposit_amount(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        staker::stake(alice, deposit_amount);

        delegation_pool::end_aptos_epoch();
        let max_withdraw_before = staker::max_withdraw(signer::address_of(alice));

        // time passes
        time::move_olc_and_epoch_forward();

        // get max withdraw amount
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw > max_withdraw_before, 0);

        staker::unlock(alice, max_withdraw);
        
        // get max withdraw amount
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        assert!(max_withdraw == 0, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xABC123, admin = @default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun  test_max_withdraw_after_share_price_increase_and_deposit(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
   
        // whitelist and setup users with APT
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 100 * constants::one_apt());
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, 100 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        // Alice stakes
        staker::stake(alice, 11 * constants::one_apt());

        // share price increases
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // Bob stakes
        let deposit_bob = 10 * constants::one_apt();
        staker::stake(bob, deposit_bob);
 
        // Verify that Bob's max withdraw matches his initial deposit
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        assert!(max_withdraw_bob == deposit_bob, 0);
    }

// -------------------------------- Get Pools() Info ------------------------------------------
    #[test(admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3)]
    public entry fun test_pools_gets_default_pool(
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // get pools info
        let all_pools = pools();

        // assert pool info
        assert!(vector::length(&all_pools) == 1, 0);

        let expected_pool_info = test_DelegationPoolInfo(default_pool(), POOL_ENABLED, 0);
        assert!(vector::contains(&all_pools, &expected_pool_info), 0);
    }

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_pools_gets_default_pool_and_stake(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
  
        // whitelist and setup user with APT
        let deposit_amount = 1000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // stake some tokens with the default pool
        stake_to_specific_pool(julia, deposit_amount, default_pool());

        // verify the delegation pool vector contains the expected info
        let all_pools = pools();
        assert!(vector::length(&all_pools) == 1, 0);

        let expected_pool_info = test_DelegationPoolInfo(default_pool(), POOL_ENABLED, deposit_amount);
        assert!(vector::contains(&all_pools, &expected_pool_info), 0);
        
        // end epoch, add_stake fees are reimbursed
        delegation_pool::end_aptos_epoch();

        // get pools info
        all_pools = pools();

        // verify state of delegation pool
        assert!(vector::length(&all_pools) == 1, 0);

        let (active_stake, _, _) =  delegation_pool::get_stake(default_pool(), signer::address_of(resource_account));
        expected_pool_info = test_DelegationPoolInfo(default_pool(), POOL_ENABLED, active_stake);
        assert!(vector::contains(&all_pools, &expected_pool_info), 0);

        // end epoch, rewards are distributed
        delegation_pool::end_aptos_epoch();

        // get pools info
        all_pools = pools();

        // verify state of delegation pool
        assert!(vector::length(&all_pools) == 1, 0);

        let (active_stake, _, _) =  delegation_pool::get_stake(default_pool(), signer::address_of(resource_account));
        expected_pool_info = test_DelegationPoolInfo(default_pool(), POOL_ENABLED, active_stake);
        assert!(vector::contains(&all_pools, &expected_pool_info), 0);
    }

    #[test(julia=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator_one=@0xDEA1, validator_two=@0xDEA2, whitelist=@whitelist)]
    public entry fun test_pools_gets_DelegationPoolInfo_for_two_pools(
        julia: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator_one: &signer,
        validator_two: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_one);
        let pool_one_address = default_pool();

        // create and add a second delegation pool
        let pool_two_address = setup_test_delegation_pool::create_basic_pool(validator_two);
        add_pool(admin, pool_two_address);

        // whitelist and setup user with APT
        let deposit_one_amount = 100 * constants::one_apt();
        let deposit_two_amount = 200 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, julia, deposit_one_amount + deposit_two_amount);
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(julia)]);

        // stake with the two delegation pools
        stake_to_specific_pool(julia, deposit_one_amount, pool_one_address);
        stake_to_specific_pool(julia, deposit_two_amount, pool_two_address);

        // disable second pool
        disable_pool(admin, pool_two_address);

        // verify the delegation pool vector contains the expected items
        let all_pools = pools();

        // verify pool info
        assert!(vector::length(&all_pools) == 2, 0);

        let expected_pool_one_info = test_DelegationPoolInfo(pool_one_address, POOL_ENABLED, deposit_one_amount);
        assert!(vector::contains(&all_pools, &expected_pool_one_info), 0);

        let expected_pool_two_info = test_DelegationPoolInfo(pool_two_address, POOL_DISABLED, deposit_two_amount);
        assert!(vector::contains(&all_pools, &expected_pool_two_info), 0);
    }

// -------------------------------- Get whitelist address ------------------------------------------
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_whitelist_address(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        validator: &signer,
        whitelist: &signer
    ) {
        // initialise staker and delegation pool
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // whitelist and setup user with APT
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 1_000 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        // get whitelist address
        let whitelist_address = staker::whitelist();
        assert!(whitelist_address == signer::address_of(whitelist), 0);
    }

}

