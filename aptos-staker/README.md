# Aptos staking with TruFin

The TruFin Aptos staking vault offers users a reliable way of staking APT on the Aptos network.  
On staking APT via the vault, users receive a receipt in the form of the **rewards bearing TruAPT token**.  
In addition to the liquid staking functionality, the TruFin staker supports delegating to different pools.

> Note: Allocations feature is deprecated.

## Multi-delegation pools support

The `aptos-staker` module supports the addition of multiple delegation pools.
This allows users to choose with which pool they want to stake.  
By design, users are allowed to deposit in any pool and to withdraw from any pool.  
The price of TruAPT (aka the share price) is function of the total staked across all the pools.

**Notes:**
Pools can be disabled but not deleted.

## Extra security features

### Pausability

The contract is pausable which allows an admin to temporarily prevent anyone from interacting with the contract.  
This is useful in case of an emergency where the contract needs to be stopped while a remediation is pending.

### 2-step admin

Replacing the admin is a two-step process where the new admin address is added as pending, in order to then be switched to active.  
This prevents adding an admin with an address that is wrong or has an error in it which would render the contract without any admin.

## Note on minimum deposits

We require users to stake a minimum of 10APT every time. We also only allow users to unstake a minimum of 10 APT every time  because Aptos delegation pools don't allow to unlock less than this amount.  
As we're dealing with institutional clients, we don't expect this to be a problem.  
By design, there is no maximum limit to how much can be deposited by a single user.

## Note on rounding errors

There are situations where rounding errors can lead to bad UX.  
Consider the example of a user who stakes 100 APT and then finds out they can only withdraw 99.99999999 APT. If this were to happen we make them whole by letting them withdraw 100 APT, while we pay for the difference.  
As a rule of thumb, we allow for 1 or 2 octas to make up for rounding errors if it can lead to better UX.  
This is not a security concern as we consider that "draining" our reserve this way is not worth it from an attacker perspective.  
To be able to cover costs associated with rounding errors, we transfer 1 APT to the TruFin's staker as part of the initialisation process.  

## Note on fees

The treasury receives a specified percentage of all rewards. However, instead of sending these rewards to the treasury, we mint the equivalent amount of TruAPT so that the treasury can also benefit from staking rewards.  
The share price is calculated to already reflect this in order to avoid share price fluctuations when minting TruAPT for the treasury.

## More notes

- We do not impose limits on setter functions which we appreciate is a centralization risk, but due to the upgradeable nature of our contracts, unavoidable.
- TruFin will always maintain a stake of at least 10 APT as `active` to meet the delegation pools minimum requirement on their active stake.
- We also don’t allow the user to leave a balance under 10 APT and if they ask to withdraw an amount such that less than 10 APT would be left in the vault, we round it up so that everything gets withdrawn.
- We don't call `synchronize_delegation_pool` when we know this is done from within the Aptos contracts
- The `total_staked()` method only includes `active` stake, not `pending_inactive` stake that is still accruing rewards. The rationale for doing so is that as soon as a user unlocks, their TruAPT is burned and their stake will move from the `active` stake to the `pending_inactive` stake.
- In `collect_residual_rewards` we iterate over all pending unlocks, potentially exposing us to a gas griefing attack. However, this is very unlikely as all our users are KYCed and we don't expect to have too many pending unlocks at any given time.
- By design, `pending_inactive` stake rewards go to the treasury and are not automatically restaked. We call these `residual_rewards`. However, we'll tell our users on the front end that it's in their best interest to unlock as close to the end of the unlock period as possible so that they don't lose out on rewards, but ultimately the rewards that accrue at that time will be transferred to our treasury.
- We account for add stake fees not yet reimbursed in the contract to avoid fluctuation in the total APT staked that would affect the share price. We don't use `delegation_pool::get_add_stake_fee` to determine these fees, because it can return 1 octa less than what we calculate with `(staked_amount - (active_after_stake - active_before_stake))`
- Unlocks & withdrawals:
During the `withdraw` and `collect_residual_rewards` operations, `inactive` (and sometimes `pending_inactive`) stake from prior unlocks are transferred to the TruFin staker's account. The users' withdrawals are then paid from this account.
The working assumption is that the sum of all `inactive` stake + `pending_inactive` stake that the staker receives from the delegation pools when calling the staker's `unlock`, `withdraw` and `collect_residual_rewards` functions is greater than the total APT withdrawn by our users + residual rewards fees collected by the treasury.
- Unlocks draw on a pool's `active` stake, and newly-added stake only becomes `active` in the next epoch. As a result an `unlock` / `unlock_from_specific_pool` against a given pool can temporarily revert (`EUNLOCK_AMOUNT_TOO_HIGH`) when that pool's currently-active stake has been consumed — for example by another user unlocking against it before recently-added stake activates. This is by design: it protects each pool's active-stake floor and no funds are lost or frozen. The redemption succeeds once the relevant stake becomes active in the following epoch, or immediately by unlocking from another pool with sufficient active stake. See `test_unlock_when_other_unlock_drains_active_stake_fails`.
