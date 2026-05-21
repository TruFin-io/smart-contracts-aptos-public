#[test_only]
module publisher::deprecated_test {
    use publisher::staker;

    // EDEPRECATED = 34, wrapped in aptos_framework::error::invalid_state (category 3).
    // abort_code = (3 << 16) | 34 = 196642.

    // ___________________________ Entry functions ___________________________

    #[test(admin = @default_admin)]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_set_dist_fee_reverts(admin: &signer) {
        staker::set_dist_fee(admin, 100);
    }

    #[test(allocator = @0xA11)]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_allocate_reverts(allocator: &signer) {
        staker::allocate(allocator, @0xBEEF, 1_000_000);
    }

    #[test(distributor = @0xA11)]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_distribute_rewards_reverts(distributor: &signer) {
        staker::distribute_rewards(distributor, @0xBEEF, true);
    }

    #[test(distributor = @0xA11)]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_distribute_all_reverts(distributor: &signer) {
        staker::distribute_all(distributor, true);
    }

    #[test(deallocator = @0xA11)]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_deallocate_reverts(deallocator: &signer) {
        staker::deallocate(deallocator, @0xBEEF, 1_000_000);
    }

    // ___________________________ View functions ___________________________

    #[test]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_total_allocated_reverts() {
        let (_a, _b, _c) = staker::total_allocated(@0xBEEF);
    }

    #[test]
    #[expected_failure(abort_code = 196642, location = staker)]
    public entry fun test_allocations_reverts() {
        let _ = staker::allocations(@0xBEEF);
    }
}
