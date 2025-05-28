#!/bin/bash
set -e

# Check if required parameters are provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <namespace> [pod_name]"
  exit 1
fi

NAMESPACE="$1"
POD_NAME="${2:-vault-0}"

log_info() {
  echo "ℹ️  $1"
}

log_warning() {
  echo "⚠️  $1"
}

log_error() {
  echo "::error::$1" >&2
  exit 1
}

# Function to check if Vault is initialized
is_vault_initialized() {
  local pod=$1
  local namespace=$2
  
  if oc exec -n "$namespace" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null | \
     jq -e '.initialized == true' >/dev/null 2>&1; then
    return 0  # Vault is initialized
  else
    return 1  # Vault is not initialized or error occurred
  fi
}

log_info "Checking if Vault is already initialized on pod '$POD_NAME'..."

# Check if Vault is already initialized
if is_vault_initialized "$POD_NAME" "$NAMESPACE"; then
  log_info "Vault is already initialized on pod '$POD_NAME'."
  exit 0
fi

log_info "Vault is not initialized. Starting initialization on pod '$POD_NAME'..."

# Initialize Vault
log_info "Initializing Vault on pod '$POD_NAME'..."
INIT_OUTPUT=$(oc exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator init -key-shares=5 -key-threshold=3 -format=json" 2>&1) || {
  log_error "Failed to initialize Vault on pod '$POD_NAME'. Error: $INIT_OUTPUT"
}

# Create directory for initialization artifacts
INIT_DIR="/tmp/vault-init-$(date +%s)"
mkdir -p "$INIT_DIR"

# Save initialization output for debugging
echo "$INIT_OUTPUT" > "${INIT_DIR}/vault-init.json"

# Extract and save root token and unseal keys
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
for i in {0..4}; do
  KEY=$(echo "$INIT_OUTPUT" | jq -r ".unseal_keys_b64[$i]")
  echo "$KEY" > "${INIT_DIR}/unseal-key-${i}.txt"
done

# Save root token to file
echo "$ROOT_TOKEN" > "${INIT_DIR}/root-token.txt"

log_info "Vault initialized successfully on pod '$POD_NAME'."
log_warning "IMPORTANT: Securely store the following information:"
log_warning "Root token: ${ROOT_TOKEN:0:8}...${ROOT_TOKEN: -8}"
log_warning "Unseal keys saved to: $INIT_DIR/"

# Output the directory containing the initialization artifacts
echo "VAULT_INIT_DIR=$INIT_DIR" >> $GITHUB_ENV

# If running in GitHub Actions, mask the sensitive values
if [ -n "$GITHUB_ACTIONS" ]; then
  echo "::add-mask::${ROOT_TOKEN}"
  for i in {0..4}; do
    KEY=$(cat "${INIT_DIR}/unseal-key-${i}.txt")
    echo "::add-mask::${KEY}"
  done
  
  # Set outputs for GitHub Actions
  echo "root_token=${ROOT_TOKEN}" >> $GITHUB_OUTPUT
  for i in {0..4}; do
    KEY_NAME="unseal_key_$i"
    KEY=$(cat "${INIT_DIR}/unseal-key-${i}.txt")
    echo "${KEY_NAME}=${KEY}" >> $GITHUB_OUTPUT
  done
fi

exit 0
