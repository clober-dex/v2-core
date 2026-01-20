#!/usr/bin/env bash
set -euo pipefail

source .env

# usage: ./script/deploy.sh base|arbitrum
NETWORK="${1:-}"
if [[ -z "$NETWORK" ]]; then
  echo "Usage: $0 [base|arbitrum]"
  exit 1
fi

case "$NETWORK" in
  base|arbitrum)
    ;;
  *)
    echo "Usage: $0 [base|arbitrum]"
    exit 1
    ;;
esac

forge script ./script/Deploy.s.sol:DeployScript \
  --sig "run()" \
  --rpc-url "$NETWORK" \
  --account clober-deployer \
  --password="$KEYSTORE_PASSWORD" \
  --verify \
  --broadcast
