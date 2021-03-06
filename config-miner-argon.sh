#!/usr/bin/env bash

# Script created 2020-06-02 by WhoaBuddy
# Revised on 2020-06-03 for ARGON (Phase 2)
# Revised on 2020-06-08 to add checks and balances
# Revised on 2020-07-06 with minor changes
# Hosted on GitHub by AbsorbingChaos
# Link: https://github.com/AbsorbingChaos/bks-setup-miner
# Based on Bash3 Boilerplate. Copyright (c) 2014, kvz.io
# Link: https://kvz.io/blog/2013/11/21/bash-best-practices/

##############
# INIT SETUP #
##############

set -o errexit
set -o pipefail
set -o nounset

# Add warning to beginning since this is from an older phase of testnet.
printf '\n\e[1;31m%-6s\e[m\n' "NOTE: This script was created for a previous phase of the Blockstack Testnet (Argon), and is stored here for historic purposes."
printf '\e[1;31m%-6s\e[m\n' "Please review the readme for the most updated version."
read -rsn1 -p"Press any key to continue . . ."
echo

# Setup initial variables allowing for different
# actions in the future, if needed.
__action="${1:-}"
__debug=false

# Check if debug options requested and set var
# and notify user of extra options.
if [ "$__action" == "debug" ];
  then
    __debug=true
    printf '\n\e[1;33m%-6s\e[m' "SCRIPT: DEBUG MODE ENABLED."
    printf '\n\e[1;33m%-6s\e[m' "DEBUG: script output will be recorded to file,"
    printf '\n\e[1;33m%-6s\e[m' "DEBUG: cargo will be launched with env vars:"
    printf '\n\e[1;33m%-6s\e[m' "DEBUG: BLOCKSTACK_DEBUG=1 and RUST_BACKTRACE=full"
fi

###################
# PRE-REQUISUITES #
###################

printf '\n\e[1;36m%-6s\e[m\n' "SCRIPT: STARTING BLOCKSTACK ARGON MINER SETUP."

# Ubuntu software prerequisites
printf '\e[1;32m%-6s\e[m\n' "SCRIPT: Running apt-get for OS pre-reqs."
sudo apt-get update
sudo apt-get install -y build-essential cmake libssl-dev pkg-config jq git bc

# Node Version Manager (nvm)
if [ -d $HOME/.nvm ]; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: NVM detected."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: NVM not found, installing."
  # install nvm
  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
fi

# shellcheck source=src/.nvm/nvm.sh
source $HOME/.nvm/nvm.sh
# shellcheck source=src/.bashrc
source $HOME/.bashrc

# Node.js
if which node > /dev/null; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: Node.js detected."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: Node.js not found, installing via NVM."
  # install node via nvm
  nvm install node
fi

# Rust
if which rustc > /dev/null; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: Rust detected."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: Rust not found, installing."
  # install rust with defaults
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# shellcheck source=src/.cargo/env
source $HOME/.cargo/env

########################
# MINER SETUP / CONFIG #
########################

# stacks-blockchain repository
# https://github.com/blockstack/stacks-blockchain
if [ -d "$HOME/stacks-blockchain" ]; then
  if [ "$__debug" == true ];
    then
      # DEBUG: if true, we want to remove it and download
      # a fresh copy of the stacks-blockchain repository
      printf '\e[1;33m%-6s\e[m\n' "DEBUG: stacks-blockchain directory detected. removing."
      # remove stacks-blockchain local directory
      rm -rf $HOME/stacks-blockchain
      printf '\e[1;33m%-6s\e[m\n' "DEBUG: cloning stacks-blockchain directory via git."
      # clone stacks-blockchain repo
      git clone https://github.com/blockstack/stacks-blockchain.git $HOME/stacks-blockchain
  else
    printf '\e[1;32m%-6s\e[m\n' "SCRIPT: stacks-blockchain directory detected. updating via git."
    # switch to directory
    cd $HOME/stacks-blockchain
    # update from github repo
    git pull
  fi
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: stacks-blockchain directory not found, cloning via git."
  # clone stacks-blockchain repo
  git clone https://github.com/blockstack/stacks-blockchain.git $HOME/stacks-blockchain
fi

# keychain file with private keys
if [ -f "$HOME/keychain.json" ]; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: keychain file detected."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: keychain file not found, creating via blockstack-cli."
  # create a keychain including privateKey and btcAddress
  npx blockstack-cli@1.1.0-beta.1 make_keychain -t > $HOME/keychain.json
fi

# test BTC balance check
btc_balance=$(curl "https://sidecar.staging.blockstack.xyz/sidecar/v1/faucets/btc/$(jq -r '.keyInfo .btcAddress' $HOME/keychain.json)" | jq -r .balance)
btc_balance=$(echo $btc_balance*1000 | bc)
btc_balance=$(echo ${btc_balance%.*})
if [[ "$btc_balance" -gt "0" ]]; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: test BTC balance detected. skipping faucet request."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: test BTC balance not found, requesting from faucet."
  # request test BTC from faucet using btcAddress from keychain
  # usually takes 1-2 minutes
  curl -X POST https://sidecar.staging.blockstack.xyz/sidecar/v1/faucets/btc\?address\="$(jq -r '.keyInfo .btcAddress' $HOME/keychain.json)"
  printf '\n'
fi

# Argon miner config file
if [ -f $HOME/stacks-blockchain/testnet/stacks-node/conf/argon-miner-conf.toml ]; then
  printf '\e[1;32m%-6s\e[m\n' "SCRIPT: Argon config file detected."
else
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: Argon config file not found, downloading."
  # download argon miner config file from GitHub repo
  curl https://raw.githubusercontent.com/AbsorbingChaos/bks-setup-miner/master/argon-miner-conf.toml --output $HOME/stacks-blockchain/testnet/stacks-node/conf/argon-miner-conf.toml
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: Adding private key to Argon config file."
  # replace seed with privateKey from keychain
  sed -i "s/replace-with-your-private-key/$(jq -r '.keyInfo .privateKey' $HOME/keychain.json)/g" ./stacks-blockchain/testnet/stacks-node/conf/argon-miner-conf.toml
fi

# check the test BTC balance before starting the miner
# otherwise those UTXOs might not exist!
btc_balance=$(curl "https://sidecar.staging.blockstack.xyz/sidecar/v1/faucets/btc/$(jq -r '.keyInfo .btcAddress' $HOME/keychain.json)" | jq -r .balance)
btc_balance=$(echo $btc_balance*1000 | bc)
btc_balance=$(echo ${btc_balance%.*})
until [[ "$btc_balance" -gt "0" ]]; do
  printf '\e[1;31m%-6s\e[m\n' "SCRIPT: test BTC balance not found - checking again in 30 seconds."
  sleep 30
  btc_balance=$(curl "https://sidecar.staging.blockstack.xyz/sidecar/v1/faucets/btc/$(jq -r '.keyInfo .btcAddress' $HOME/keychain.json)" | jq -r .balance)
  btc_balance=$(echo $btc_balance*1000 | bc)
  btc_balance=$(echo ${btc_balance%.*})
done

printf '\e[1;32m%-6s\e[m\n\n' "SCRIPT: All checks passed, starting miner with cargo."
# change working directory to stacks-blockchain folder
cd $HOME/stacks-blockchain

if [ "$__debug" == true ];
  then
    # DEBUG: if true, record terminal output to a file
    # and start miner using environment vars for debugging
    __stamp=$(date +"%Y%m%d-%H%M%S")
    __file="bks-miner-$__stamp.txt"
    printf '\e[1;33m%-6s\e[m\n' "DEBUG: terminal output saved to:"
    printf '\e[1;33m%-6s\e[m\n' "DEBUG: $(pwd)/$__file"
    script -c "BLOCKSTACK_DEBUG=1 RUST_BACKTRACE=full cargo testnet start --config ./testnet/stacks-node/conf/argon-miner-conf.toml" $__file
  else
    # start the miner!
    cargo testnet start --config ./testnet/stacks-node/conf/argon-miner-conf.toml
fi
