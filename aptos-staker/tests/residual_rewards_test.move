#[test_only]
module publisher::residual_rewards_test{
    use std::signer;
    use std::vector;

    use aptos_framework::delegation_pool;
    use aptos_framework::event;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::stake;

    // smart contracts
    use publisher::staker::{Self, stake};

    // test modules
    use publisher::constants;
    use publisher::account_setup;
    use publisher::setup_test_delegation_pool;
    use publisher::setup_test_staker::{Self, initial_deposit};
    use publisher::time;

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_one_delegation_pool_no_rewards(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes and accrues rewards
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount);

        // no rewards have accrued, so residual_rewards should be zero
        let preview = staker::preview_residual_rewards();
        assert!(preview == 0, 0);
        
        // fetch residual_rewards
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);

        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance, 0);
    }
    
    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_one_delegation_pool_rewards(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes and accrues rewards
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // unlock the initial amount and rewards earned
        let max_withdraw = staker::max_withdraw(signer::address_of(alice));
        
        // user submits unlock request
        staker::unlock(alice, max_withdraw);
        let nonce = staker::latest_unlock_nonce();

        // time passes
        time::move_olc_and_epoch_forward();  

        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let rewards = inactive - max_withdraw;
        
        // user withdraws
        staker::withdraw(alice, nonce);
        
        // assert preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        
        // fetch residual_rewards
        staker::collect_residual_rewards(admin);

        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(alice)) == max_withdraw, 0);
    }

    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_one_delegation_pool_multiple_unlocks(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user accounts with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);        
        delegation_pool::end_aptos_epoch();

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);        
        delegation_pool::end_aptos_epoch();

        // charlie withdraws
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);

        // time passes
        time::move_olc_and_epoch_forward();  

        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let total_withdrawn = max_withdraw_alice + max_withdraw_bob + max_withdraw_charlie;
        let rewards = inactive - total_withdrawn;
        
        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));

        // fetch residual_rewards
        staker::collect_residual_rewards(admin);
        
        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(resource_account)) >= total_withdrawn, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);

        staker::withdraw(alice, 1);
        staker::withdraw(bob, 2);
        staker::withdraw(charlie, 3);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_one_delegation_pool_multiple_unlocks_withdraw_first(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user accounts with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);        
        delegation_pool::end_aptos_epoch();

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);        
        delegation_pool::end_aptos_epoch();

        // charlie withdraws
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);

        // time passes
        time::move_olc_and_epoch_forward();  

        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let total_withdrawn = max_withdraw_alice + max_withdraw_bob + max_withdraw_charlie;
        let rewards = inactive - total_withdrawn;

        staker::withdraw(alice, 1);
        staker::withdraw(bob, 2);
        staker::withdraw(charlie, 3);

        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));

        // fetch residual_rewards
        staker::collect_residual_rewards(admin);
        
        // assert user got their requested amount back and treasury got the rewards
        let reserve_amount = 1 * constants::one_apt(); 
        assert!(coin::balance<AptosCoin>(signer::address_of(resource_account)) <= reserve_amount, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_one_delegation_multiple_unlocks_different_olcs(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  
        time::move_olc_and_epoch_forward();
        // inactive should be equal to alice's withdrawn amount plus rewards
        let (_, inactive_1, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);        
        time::move_olc_and_epoch_forward();
        // inactive should be equal to bobs's withdrawn amount plus rewards
        let (_, inactive_2, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // charlie withdraws
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);        
        delegation_pool::end_aptos_epoch();
        
        // inactive should be 0 as all unlocks have been withdrawn and the current olc has not yet expired
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(inactive == 0, 0);
        
        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        // since charlie's unlock is not claimable yet, it will not be considered
        let total_withdrawn = max_withdraw_alice + max_withdraw_bob;
        let rewards = inactive_1 + inactive_2 - total_withdrawn;
        
        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        // fetch residual_rewards
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        
        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(resource_account)) >= total_withdrawn, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);

        time::move_olc_and_epoch_forward(); 
        staker::withdraw(alice, 1); 
        staker::withdraw(bob, 2); 
        staker::withdraw(charlie, 3);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_multiple_collections_vs_one(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, 2 * deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, 2 * deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        // make initial deposits
        initial_deposit(aptos_framework, whitelist, pool);
      
        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  
        time::move_olc_and_epoch_forward();
                
        let rewards_1 = staker::preview_residual_rewards();

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);
        time::move_olc_and_epoch_forward();

        let rewards_2 = staker::preview_residual_rewards();
        let increase = rewards_2 - rewards_1;

        // charlie withdraws
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);
        delegation_pool::end_aptos_epoch();
        time::move_olc_and_epoch_forward(); 

        let rewards_3 = staker::preview_residual_rewards();
        let increase_2 = rewards_3 - rewards_2;

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));

        staker::collect_residual_rewards(admin);

        let treasury_increase = coin::balance<AptosCoin>(signer::address_of(treasury)) - prebalance;
        
        assert!(treasury_increase == rewards_1 + increase + increase_2, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, validator_2=@0xFEA, validator_3=@0xDEF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_different_pools(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        validator_2: &signer,
        validator_3: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        
        // initialise additional delegation pools
        let pool_2 = setup_test_delegation_pool::create_basic_pool(validator_2);
        staker::add_pool(admin, pool_2);
        let pool_3 = setup_test_delegation_pool::create_basic_pool(validator_3);
        staker::add_pool(admin, pool_3);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);

        // perform initial deposits to all pools
        initial_deposit(aptos_framework, whitelist, pool);
        aptos_coin::mint(aptos_framework, signer::address_of(whitelist), deposit_amount);
        staker::stake_to_specific_pool(whitelist, deposit_amount/2, pool_2);
        staker::stake_to_specific_pool(whitelist, deposit_amount/2, pool_3);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        staker::stake_to_specific_pool(bob, deposit_amount, pool_2);
        staker::stake_to_specific_pool(charlie, deposit_amount, pool_3);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  
        time::move_olc_and_epoch_forward();
        // inactive should be equal to alice's withdrawn amount plus rewards
        let (_, inactive_1, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock_from_specific_pool(bob, max_withdraw_bob, pool_2);        
        time::move_olc_and_epoch_forward();
        // inactive should be equal to bobs's withdrawn amount plus rewards
        let (_, inactive_2, _) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));

        // charlie withdraws and rewards accrue
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock_from_specific_pool(charlie, max_withdraw_charlie, pool_3);        
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        // since charlie's unlock is not claimable yet, it will not be considered
        let total_withdrawn = max_withdraw_alice + max_withdraw_bob;
        let rewards = inactive_1 + inactive_2 - total_withdrawn;
        
        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        // fetch residual_rewards
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        
        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(resource_account)) >= total_withdrawn, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);

        time::move_olc_and_epoch_forward(); 
        staker::withdraw(alice, 1); 
        staker::withdraw(bob, 2); 
        staker::withdraw(charlie, 3);

        // there should now be more to unlock as charlie has accrued rewards
        preview = staker::preview_residual_rewards();
        assert!(preview > 0, 0);
        prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + preview, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_collected_twice(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // alice withdraws 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  
        time::move_olc_and_epoch_forward();
        // inactive should be equal to alice's withdrawn amount plus rewards
        let (_, inactive_1, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // bob withdraws
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);        
        time::move_olc_and_epoch_forward();
        // inactive should be equal to bobs's withdrawn amount plus rewards
        let (_, inactive_2, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // charlie withdraws
        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);        
        delegation_pool::end_aptos_epoch();
        
        // inactive should be 0 as all unlocks have been withdrawn and the current olc has not yet expired
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(inactive == 0, 0);
        
        // treasury should be minted the difference between the total withdrawn amount and the requested withdrawn amount
        // since charlie's unlock is not claimable yet, it will not be considered
        let total_withdrawn = max_withdraw_alice + max_withdraw_bob;
        let rewards = inactive_1 + inactive_2 - total_withdrawn;
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        
        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == rewards, 0);

        // fetch residual_rewards
        staker::collect_residual_rewards(admin);

        // assert user got their requested amount back and treasury got the rewards
        assert!(coin::balance<AptosCoin>(signer::address_of(resource_account)) >= total_withdrawn, 0);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + rewards, 0);

        // charlie's unlock is ready for withdrawal
        time::move_olc_and_epoch_forward();

        (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        let new_rewards = inactive - max_withdraw_charlie;

        // check preview is correct
        let preview = staker::preview_residual_rewards();
        assert!(preview == new_rewards, 0);

        prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance + new_rewards, 0);

        staker::withdraw(alice, 1);
        staker::withdraw(bob, 2);
        staker::withdraw(charlie, 3);
    }

    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_residual_rewards_not_collected_before_and_after_unlock_same_olc(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
       let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // no unlock has happened yet, so no residual_rewards should have been collected
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance, 0);

        // alice unlocks 
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  

        // unlock is not ready for withdrawal so no residual_rewards should have been collected
        prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance, 0);

        time::move_olc_and_epoch_forward();
        staker::withdraw(alice, 1);
       
       // now rewards should have been collected
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) > prebalance, 0);
    }
    
    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator_1=@0xDEA3, validator_2=@0xE4DF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_when_pool_becomes_inactive(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // alice unlocks and rewards accrue
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // leave validator set
        stake::leave_validator_set(validator_1, pool);
        delegation_pool::end_aptos_epoch();
        
        let (_, _, pending_inactive) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // bob unlocks but no rewards accrue
        let max_withdraw_bob = staker::max_withdraw(signer::address_of(bob));
        staker::unlock(bob, max_withdraw_bob);  

        time::move_olc_and_epoch_forward();

        // residual_rewards should be collected on Alice's unlock i.e. the rewards collected during unlock
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        let rewards = pending_inactive - max_withdraw_alice;
        
        // check preview is correct with potential rounding error
        let preview = staker::preview_residual_rewards();
        assert!(preview + 1 == rewards, 0);

        staker::collect_residual_rewards(admin);

        // assert user got their requested amount back and treasury got the rewards (with small rounding error)
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == (prebalance + rewards - 1), 0);
        
        staker::withdraw(alice, 1);

        let max_withdraw_charlie = staker::max_withdraw(signer::address_of(charlie));
        staker::unlock(charlie, max_withdraw_charlie);  

        // no rewards are accruing, so no residual_rewards should be collected
        preview = staker::preview_residual_rewards();
        assert!(preview == 0, 0);
        prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance, 0);

        staker::withdraw(bob, 2);
        staker::withdraw(charlie, 3);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator_1=@0xDEA3, validator_2=@0xE4DF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_when_pool_becomes_inactive_two_withdraws(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // alice stake and accrues rewards
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // leave validator set
        stake::leave_validator_set(validator_1, pool);
        time::move_olc_and_epoch_forward();

        // first unlock
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice / 2);  
        time::move_olc_and_epoch_forward();

        // second unlock
        staker::unlock(alice, max_withdraw_alice / 2);  
        time::move_olc_and_epoch_forward();
        delegation_pool::end_aptos_epoch();

        // first withdraw
        staker::withdraw(alice, 1);

        // there should be no residual rewards to collect 
        let rewards = staker::preview_residual_rewards();
        assert!(rewards == 0, 0);

        let prebalance_treasury = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance_treasury, 0);

        // second withdraw
        staker::withdraw(alice, 2);
    }

    #[test(alice=@0xE0A1, bob=@0xEDA1, charlie=@0xEFA1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator_1=@0xDEA3, validator_2=@0xE4DF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_when_pool_becomes_inactive_pre_and_post_withdrawals(
        alice: &signer,
        bob: &signer,
        charlie: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, charlie, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob), signer::address_of(charlie)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // users stake and accrue rewards
        stake(alice, deposit_amount);
        stake(bob, deposit_amount);
        stake(charlie, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // alice unlocks and rewards accrue
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);  

        // leave validator set
        stake::leave_validator_set(validator_1, pool);
        time::move_olc_and_epoch_forward();

        let (active, inactive, pending_inactive) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(active > 0, 0);
        assert!(inactive > 0, 0);
        assert!(pending_inactive == 0, 0);

        // bob unlocks and immediately withdraws (no rewards accrue)
        staker::unlock(bob, 20 * constants::one_apt());
        staker::withdraw(bob,2);

        // residual rewards have accrued after alice's unlock
        let residual_rewards = staker::preview_residual_rewards();
        assert!(residual_rewards > 0, 0);

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);

        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == (prebalance + residual_rewards), 0);    
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator_1=@0xDEA3, validator_2=@0xE4DF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_with_inactive_stake_on_inactive_validator(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // alice stakes and accrues rewards
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();
        
        // alice unlocks and accrues rewards. OLC passes
        let max_withdraw_alice = staker::max_withdraw(signer::address_of(alice));
        staker::unlock(alice, max_withdraw_alice);

        time::move_olc_and_epoch_forward();

        // leave validator set
        stake::leave_validator_set(validator_1, pool);
        delegation_pool::end_aptos_epoch();

        let (_, inactive, pending_inactive) = delegation_pool::get_stake(pool, signer::address_of(resource_account));
        assert!(inactive > 0, 0);
        assert!(pending_inactive == 0, 0);

        // rewards should have accrued for alice
        // treasury receives part of the rewards of final unlock OLC
        let residual_rewards = staker::preview_residual_rewards();
        assert!(residual_rewards > 0, 0);

        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);

        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == (prebalance + residual_rewards), 0);   

        staker::withdraw(alice, 1); 
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator_1=@0xDEA3, validator_2=@0xE4DF, whitelist=@whitelist)]
    public entry fun test_residual_rewards_when_pool_becomes_inactive_many_withdrawals(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);
       
        // initialise additional delegation pool
        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),  // min deposit
            true,   // should join validator set
            true,   // should end epoch
            0 // no commission
        );
        staker::add_pool(admin, pool_2);

        // setup whitelisted user account with funds
        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, 2 * deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        
        initial_deposit(aptos_framework, whitelist, pool);

        // alice stake and accrues rewards
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();
        delegation_pool::end_aptos_epoch();

        // leave validator set
        stake::leave_validator_set(validator_1, pool);
        time::move_olc_and_epoch_forward();

        // first unlock
        let i = 0;
        while(i < 10){
            staker::unlock(alice, 100 * constants::one_apt());  
            staker::withdraw(alice, i + 1);
            i = i + 1;
        };
        let prebalance = coin::balance<AptosCoin>(signer::address_of(treasury));
        staker::collect_residual_rewards(admin);
        assert!(coin::balance<AptosCoin>(signer::address_of(treasury)) == prebalance, 0);
    }

    #[test(admin=@default_admin, resource_account=@publisher, src=@src_account)]    
    #[expected_failure(abort_code=327684, location=staker)]
    public entry fun test_collect_residual_rewards_not_called_by_admin_fails(
        admin: &signer,
        resource_account: &signer,
        src: &signer
    ) {
        setup_test_staker::setup(admin, resource_account, src);

        // attempt to collect residual_rewards
        staker::collect_residual_rewards(src);
    }

    #[test(alice=@0xE0A1, admin=@default_admin, aptos_framework=@0x1, resource_account=@publisher, 
    src=@src_account, treasury=@0x122, validator=@0xDEA3, whitelist=@whitelist)]
    public entry fun test_ResidualRewardsCollectedEvent_emitted(
        alice: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator: &signer,
        whitelist: &signer
    ) { 
        // initialise staker and delegation pool
        let pool = setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator);
        
        let deposit_amount = 10_000 * constants::one_apt();
        
        // setup whitelisted user with funds
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice)]);
        initial_deposit(aptos_framework, whitelist, pool);

        // user stakes
        stake(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // user submits unlock request
        staker::unlock(alice, deposit_amount);
        delegation_pool::end_aptos_epoch();

        // time passes
        time::move_olc_and_epoch_forward();
        
        let (_, inactive, _) = delegation_pool::get_stake(pool, signer::address_of(resource_account));

        // action that emits event
        staker::collect_residual_rewards(admin);

        // assert number of emitted events
        let residual_rewards_event = event::emitted_events<staker::ResidualRewardsCollectedEvent>();
        assert!(vector::length(&residual_rewards_event) == 1, 0);

        // assert event contents
        let rewards = inactive - deposit_amount;
        let expected_event = staker::test_ResidualRewardsCollectedEvent(rewards);
        assert!(event::was_event_emitted(&expected_event), 0);
    }



    // Alice and Bob both unlock while validator_2 is out of the set with an expired lockup.
    // Alice withdraws, which sweeps the staker's entire pending_inactive position on that pool
    // (Alice's AND Bob's principal) into the staker account. The validator then rejoins, so Bob's
    // request stops being ready_to_withdraw and drops out of unlocks_awaiting_payout while his
    // principal is already held by the staker. Collection must not treat that principal as reward.
    #[test(alice=@0xE0A1, bob=@0xE0B2, admin=@default_admin, aptos_framework=@0x1,
    resource_account=@publisher, src=@src_account, treasury=@0x122, validator_1=@0xDEA3,
    validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_residual_rewards_exclude_pending_unlock_after_validator_rejoins(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),
            true,
            true,
            0
        );
        staker::add_pool(admin, pool_2);

        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool_2);

        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        staker::stake_to_specific_pool(bob, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        // validator_2 leaves the set and its lockup expires -> can_withdraw_pending_inactive == true
        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        assert!(stake::get_validator_state(pool_2) == constants::inactive_validator_status(), 100);
        time::move_olc_and_epoch_forward();
        assert!(delegation_pool::can_withdraw_pending_inactive(pool_2), 101);

        // both users unlock during the out-of-set window
        let alice_amount = 500 * constants::one_apt();
        staker::unlock_from_specific_pool(alice, alice_amount, pool_2);
        let alice_nonce = staker::latest_unlock_nonce();

        let bob_amount = 500 * constants::one_apt();
        staker::unlock_from_specific_pool(bob, bob_amount, pool_2);
        let bob_nonce = staker::latest_unlock_nonce();

        assert!(staker::is_claimable(alice_nonce), 102);
        assert!(staker::is_claimable(bob_nonce), 103);

        // The staker holds permanently-staked active APT well above MIN_COINS_ON_SHARES_POOL: the
        // 11 APT initial_deposit that is never unlocked, plus the validator's own stake. That floor
        // is on the active shares pool and does nothing to limit the pending_inactive sweep below.
        let (active_before, _, pending_inactive_before) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active_before >= 10 * constants::one_apt(), 200);
        // the pool's share math can round each unlock down by up to 2 octas (see EINVALID_UNSTAKED_AMOUNT)
        assert!(pending_inactive_before + 4 >= alice_amount + bob_amount, 201);

        // Alice withdraws: this sweeps the staker's whole pending_inactive position, Bob's included
        staker::withdraw(alice, alice_nonce);

        // the active floor is untouched, yet every user's pending unlock has been swept out
        let (active_after, _, pending_inactive_after) = delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        assert!(active_after == active_before, 202);
        assert!(pending_inactive_after == 0, 203);

        // Bob's money is already sitting in the staker account
        let staker_balance_after_alice = coin::balance<AptosCoin>(signer::address_of(resource_account));
        assert!(staker_balance_after_alice >= bob_amount, 104);

        // validator_2 rejoins -> Bob's request silently stops being ready_to_withdraw
        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        assert!(!staker::is_claimable(bob_nonce), 105);

        let preview = staker::preview_residual_rewards();
        let treasury_before = coin::balance<AptosCoin>(signer::address_of(treasury));
        let staker_balance_before_collect = coin::balance<AptosCoin>(signer::address_of(resource_account));
        let (_, pool_inactive, pool_pending_inactive) =
            delegation_pool::get_stake(pool_2, signer::address_of(resource_account));
        let gross_recoverable =
            staker_balance_before_collect + pool_inactive + pool_pending_inactive;
        let recoverable_excluding_reserve =
            if (gross_recoverable > constants::one_apt()) {
                gross_recoverable - constants::one_apt()
            } else {
                0
            };
        let expected_gain =
            if (recoverable_excluding_reserve > bob_amount) {
                recoverable_excluding_reserve - bob_amount
            } else {
                0
            };
        let expected_raw_gain = pending_inactive_before - alice_amount;

        staker::collect_residual_rewards(admin);
        let treasury_gain = coin::balance<AptosCoin>(signer::address_of(treasury)) - treasury_before;
        let staker_balance_after_collect = coin::balance<AptosCoin>(signer::address_of(resource_account));

        // the preview the admin sees must match what collection actually transfers
        assert!(preview == treasury_gain, 204);

        // the treasury receives exactly the capped headroom, excluding Bob's principal and the reserve
        assert!(treasury_gain == expected_gain, 205);

        // The staker must still be able to pay Bob and retain its rounding reserve. The reserve
        // may already be short by up to two octas for each of Alice's and Bob's unlocks.
        assert!(
            staker_balance_after_collect >= bob_amount + constants::one_apt() - 4,
            999
        );

        let expected_cap_event =
            staker::test_ResidualRewardsCappedEvent(expected_raw_gain, expected_gain);
        assert!(event::was_event_emitted(&expected_cap_event), 206);
    }

    // Same as above, but instead of asserting solvency we let Bob's request mature and withdraw.
    // Before the solvency cap this aborted with coin::EINSUFFICIENT_BALANCE (65542) at the
    // coin::transfer in internal_withdraw, because the treasury had taken Bob's principal.
    #[test(alice=@0xE0A1, bob=@0xE0B2, admin=@default_admin, aptos_framework=@0x1,
    resource_account=@publisher, src=@src_account, treasury=@0x122, validator_1=@0xDEA3,
    validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_withdraw_succeeds_after_residual_rewards_collected_post_rejoin(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),
            true,
            true,
            0
        );
        staker::add_pool(admin, pool_2);

        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool_2);

        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        staker::stake_to_specific_pool(bob, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        time::move_olc_and_epoch_forward();

        staker::unlock_from_specific_pool(alice, 500 * constants::one_apt(), pool_2);
        let alice_nonce = staker::latest_unlock_nonce();
        staker::unlock_from_specific_pool(bob, 500 * constants::one_apt(), pool_2);
        let bob_nonce = staker::latest_unlock_nonce();

        staker::withdraw(alice, alice_nonce);

        stake::join_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();

        staker::collect_residual_rewards(admin);

        // Alice unlocks her remaining stake, creating pending_inactive so the OLC can advance
        // and Bob's request finally matures.
        staker::unlock_from_specific_pool(alice, 400 * constants::one_apt(), pool_2);
        let alice_nonce_2 = staker::latest_unlock_nonce();
        time::move_olc_and_epoch_forward();
        time::move_olc_and_epoch_forward();
        delegation_pool::synchronize_delegation_pool(pool_2);
        assert!(staker::is_claimable(bob_nonce), 106);

        let bob_before = coin::balance<AptosCoin>(signer::address_of(bob));
        staker::withdraw(bob, bob_nonce);
        assert!(coin::balance<AptosCoin>(signer::address_of(bob)) == bob_before + 500 * constants::one_apt(), 107);

        // and Alice's later request is still payable too
        assert!(staker::is_claimable(alice_nonce_2), 108);
        staker::withdraw(alice, alice_nonce_2);
    }

    // Control: identical to the test above except validator_2 never rejoins.
    #[test(alice=@0xE0A1, bob=@0xE0B2, admin=@default_admin, aptos_framework=@0x1,
    resource_account=@publisher, src=@src_account, treasury=@0x122, validator_1=@0xDEA3,
    validator_2=@0xDFA1, whitelist=@whitelist)]
    public entry fun test_residual_rewards_when_validator_does_not_rejoin(
        alice: &signer,
        bob: &signer,
        admin: &signer,
        aptos_framework: &signer,
        resource_account: &signer,
        src: &signer,
        treasury: &signer,
        validator_1: &signer,
        validator_2: &signer,
        whitelist: &signer
    ) {
        setup_test_staker::setup_with_delegation_pool(aptos_framework, admin, resource_account, src, validator_1);

        let pool_2 = setup_test_delegation_pool::create_delegation_pool(
            validator_2,
            100 * constants::one_apt(),
            true,
            true,
            0
        );
        staker::add_pool(admin, pool_2);

        let deposit_amount = 1_000 * constants::one_apt();
        account_setup::setup_account_and_mint_APT(aptos_framework, alice, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, bob, deposit_amount);
        account_setup::setup_account_and_mint_APT(aptos_framework, treasury, 1 * constants::one_apt());
        account_setup::setup_whitelist(whitelist, vector<address>[signer::address_of(alice), signer::address_of(bob)]);

        initial_deposit(aptos_framework, whitelist, pool_2);

        staker::stake_to_specific_pool(alice, deposit_amount, pool_2);
        staker::stake_to_specific_pool(bob, deposit_amount, pool_2);
        delegation_pool::end_aptos_epoch();

        stake::leave_validator_set(validator_2, pool_2);
        delegation_pool::end_aptos_epoch();
        time::move_olc_and_epoch_forward();

        let alice_amount = 500 * constants::one_apt();
        staker::unlock_from_specific_pool(alice, alice_amount, pool_2);
        let alice_nonce = staker::latest_unlock_nonce();

        let bob_amount = 500 * constants::one_apt();
        staker::unlock_from_specific_pool(bob, bob_amount, pool_2);
        let bob_nonce = staker::latest_unlock_nonce();

        staker::withdraw(alice, alice_nonce);

        // no rejoin here, so Bob's request stays ready and is counted as an obligation
        assert!(staker::is_claimable(bob_nonce), 105);
        assert!(staker::preview_residual_rewards() == 0, 106);

        staker::collect_residual_rewards(admin);
        let staker_balance_after_collect = coin::balance<AptosCoin>(signer::address_of(resource_account));

        assert!(staker_balance_after_collect >= bob_amount, 999);

        // and Bob can actually withdraw
        staker::withdraw(bob, bob_nonce);
    }
}
