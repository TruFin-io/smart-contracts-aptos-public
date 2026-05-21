# Aptos smart contracts

A repository of smart contracts packages written in `move` for `Aptos` blockchain (`core-move`). In the future this repository might also contain `move` packages for the `Sui` blockchain (`sui-move`).

## Contents

- `aptos-staker`: `Aptos` liquid staking solution

## Linter for logic

### Move prover

1. Navigate to the directory containing your `cargo.toml` (and `aptos-cli` installation) and follow these steps: https://aptos.dev/tools/aptos-cli/install-cli/install-move-prover
2. Then run

```
aptos move prove --package-dir aptos-staker --dev
```

or inside your package run:
```
aptos move prove --named-addresses publisher=default
```
or `aptos move prove --dev` to find security issues in your move software. The `Prover.toml` contains the standard settings for the `move prover`.

## Initialising a new project:

Initialise a new Aptos move package by creating a new directory `mkdir new-move-package-name` and initialising the new aptos move package inside the folder using: 

`aptos move init --name ${new-move-package-name}`

**Deployment Profiles**

Configuring a new signer: You can run `aptos init` in any folder and create separate configurations. Look at the account you created with the `aptos account list` command. This tool allows for multiple profiles within the same repository.
Specify a profile name using `aptos init --profile trufin`

## Compiling a project


Compile a **development version** of your project using `dev-addresses` and `dev_dependencies` specified inside `Move.toml`:

`aptos move compile --dev`


Compile a **production version** of this project using `addresses` and `dependencies` specified inside `Move.toml`: `aptos move compile --named-addresses publisher=0xC0FFEE`


## Testing a project

To test a **development version** of the package _from within the package folder_ without worrying about deployment addresses run:

`aptos move test --dev`


To test a *development version* of the `aptos-staker` package _from the root folder_ run:
`aptos move test --package-dir aptos-staker --dev`

If you have your publishers set:
to test a *production version* of the project _from within its folder_ run: `aptos move test`

To test a *production version* of the `aptos-staker` package _from the root folder_ run:
`aptos move test --package-dir aptos-staker`

To test the *testnet staker*:
1. cd into aptos-staker
2. `aptos move compile --named-addresses default_admin=default_admin,src_account=src_account,publisher=<staker_address>`
3. Run the following, replacing test.mv with the desired test file and script_acc with your aptos profile: 
`aptos move run-script --compiled-script-path build/aptos-staker/bytecode_scripts/test.mv --profile script_acc`

Add  `--profile-gas > test_logs.txt` to print debug statements and only simulate the tests without actually executing them. Note that to simulate i.e unlock tests you will first need to run the stake tests. 

**Test coverage**

To obtain the test coverage simply add `--coverage`.
Inside aptos-staker run:
`aptos move test --dev --coverage`

This will create the file `.coverage_map.mvcov` that is used to show gaps in test coverage running:
`aptos move coverage source --dev --module staker`

## Publishing the Whitelist

Once the package has been compiled and tested, it can be published (deployed) using your aptos account. (Make sure you have run aptos init and have an aptos account)

Change the whitelist address in the `Move.toml` file to match your aptos account address.

You can then run the following commands in your terminal:
 First, give permission to execute the script:
 `chmod +x deploy_whitelist.sh`

 Then, run the script, passing in 
 1. Your aptos account name as ACCOUNT_NAME.
 2. Pass in true as DEV, if this is to publish to devnet or testnet, otherwise false.
 
`./deploy_staker.sh default true` 

## Publishing the Staker


The staker imports the whitelist. Thus, please publish the whitelist before publishing the staker. Once the package has been compiled and tested, it can be published (deployed) using a resource account.

You can run the following commands in your terminal:
 First, give permission to execute the script:
 `chmod +x deploy_staker.sh`

 Then, run the script, passing in 
 1. Your aptos account name as ACCOUNT_NAME.
 2. A random seed from which to create a resource account as SEED i.e. 1234. 
 3. The address for the contract admin as ADMIN_ADDRESS.
 4. Optional boolean flag DEV. Default is `DEV=true`, if not provided. DEV should be true to publish to devnet and testnet, otherwise false.
 
 Ensure that the publisher address in your move.toml is set to "_".
 
`./deploy_staker.sh src 1234 80648ee2984d56281778aaa996005ac45ea5fbd71208f33ed9fa7f9a33c13f6f` 

## Upgrading the Staker

The published `aptos-staker` package can be upgraded via the `upgrade_staker.sh` script, which deploys new versions of the TruAPT and Staker modules.

The script performs the following steps:
1. Uses the `move build-publish-payload` command to generate metatada and bytecode for the modules in this package.
2. Creates a move script to deploy the new bytecode under a given resource account.
3. The move script is then compiled with the command `aptos move compile-script`.
4. And executed with the command `aptos move run-script`

To run the script, make it executable running `chmod +x upgrade_staker.sh`, and make sure to have the `publisher`, `default_admin` and `src_account` profiles in your `.aptos/config.yaml` for the network you are deploying to.

Usage:
```
./upgrade_staker.sh [testnet | mainnet] <upgrade>
```

For example to upgrade the testnet staker:
```
./upgrade_staker.sh testnet upgrade
```
