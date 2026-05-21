#[test_only]
module publisher::account_setup {
    use std::signer;
    use std::vector;
    
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use aptos_framework::resource_account::create_resource_account;
    
    // smart contracts
    use whitelist::master_whitelist;

    // test modules
    friend publisher::init_test;
    friend publisher::setter_test;
    friend publisher::stake_test;
    friend publisher::unlock_test;
    friend publisher::withdraw_test;
    friend publisher::setup_test_staker;
    friend publisher::truAPT_test;
    friend publisher::share_price_test;
    friend publisher::multi_validator_test;
    friend publisher::total_staked_test;
    friend publisher::getter_test;
    friend publisher::residual_rewards_test;
    friend publisher::fees_test;
    friend publisher::withdraw_list_test;

    // ________________ Account-related helper functions  ________________
    public(friend) fun prepare_account(sender: &signer) {
        let addr = signer::address_of(sender);
        // configure APT account and register APT
        if (!account::exists_at(addr)) aptos_account::create_account(addr);
    } 

    // create main accounts for staker setup
    public(friend) fun create_main_accounts(admin: &signer, resource_account: &signer, src: &signer){
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(src));
        account::create_account_for_test(signer::address_of(resource_account));
        create_resource_account(src, b"", b"");

        // set up minting for testing if necessary
        let aptos_framework = account::create_account_for_test(@0x1);
        if (!aptos_coin::has_mint_capability(&aptos_framework)) {
            let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&aptos_framework);
            coin::destroy_burn_cap(burn_cap);
            coin::destroy_mint_cap(mint_cap);
        };

        // mint 1 APT to admin for staker reserve
        coin::register<AptosCoin>(admin);
        aptos_coin::mint(&aptos_framework, signer::address_of(admin), 100000000);
    }

    // initialize whitelist and whitelist users
    public(friend) fun setup_whitelist(owner: &signer, users: vector<address>) {
        aptos_account::create_account(signer::address_of(owner));
        master_whitelist::test_initialize(owner);     

        while (!vector::is_empty(&users)) {
            let user = vector::pop_back(&mut users);
            master_whitelist::whitelist_user(owner, user);
        }
    }

    // _________________________________ APT related helper functions _________________________________

    /// Mint APT to existing user or resource account
    public(friend) fun mint_APT(aptos_framework: &signer, staker: &signer, amount: u64) {
        aptos_coin::mint(aptos_framework, signer::address_of(staker), amount);
    }   

    // Setup account and mint APT to it
    public(friend) fun setup_account_and_mint_APT(aptos_framework: &signer, account: &signer, amount: u64) {
        // initialise user
        prepare_account(account);

        aptos_coin::mint(aptos_framework, signer::address_of(account), amount);
    } 
}