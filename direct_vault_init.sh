#!/bin/bash
# Direct Vault initialization and unsealing script
# This script is designed to work with cert-manager generated TLS certificates
set -e

# Configuration variables
NAMESPACE=${VAULT_NAMESPACE:-"vault-test-pragmatic"}
VAULT_LEADER_POD="vault-0"
VAULT_INTERNAL_SERVICE="vault-internal"

# Get cluster domain if not provided
if [ -z "${VAULT_DOMAIN}" ]; then
  CLUSTER_DOMAIN=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null | sed 's/console-openshift-console\.//g' || echo "apps.cluster-67wft.67wft.sandbox1936.opentlc.com")
else
  CLUSTER_DOMAIN="${VAULT_DOMAIN}"
fi

# Set debug mode if needed
DEBUG=${DEBUG:-false}
if [ "$DEBUG" = "true" ]; then
  set -x
fi

# Function to log messages with timestamp
vault_log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# TLS configuration
TLS_SECRET_NAME="vault-tls"
TLS_SKIP_VERIFY="true"  # Set to false if using trusted CA certificates

# Unseal keys and root token - can be loaded from environment variables or vault-keys.env file
UNSEAL_KEY_1="${UNSEAL_KEY_1:-}"
UNSEAL_KEY_2="${UNSEAL_KEY_2:-}"
UNSEAL_KEY_3="${UNSEAL_KEY_3:-}"
ROOT_TOKEN="${ROOT_TOKEN:-}"

# Check for keys file and use if available
if [ -f "vault-keys.env" ]; then
  vault_log "Loading unseal keys from vault-keys.env file"
  source vault-keys.env
fi

# Vault service names - adjust if your deployment uses different names
# Use simple pod names for direct access
VAULT_INTERNAL_SERVICE="vault-internal"
VAULT_LEADER_POD="vault-0"

# Function to wait for pod to be ready
wait_for_pod() {
  local pod=$1
  local timeout=120  # Increased timeout for OpenShift environment
  local counter=0
  vault_log "Waiting for $pod to be ready..."

  while [ $counter -lt $timeout ]; do
    if oc get pod $pod -n $NAMESPACE | grep -q "1/1\s*Running"; then
      vault_log "$pod is ready"
      sleep 5  # Give the container a moment to stabilize
      return 0
    fi
    sleep 5
    counter=$((counter+5))
    if [ $((counter % 15)) -eq 0 ]; then
      vault_log "Still waiting for $pod to be ready... ($counter seconds)"
    fi
  done

  vault_log "Timeout waiting for $pod to be ready"
  return 1
}

# Function to check Vault status
# Function to verify TLS certificates
verify_tls_certificates() {
  vault_log "Verifying TLS certificates from cert-manager"

  # Check if the TLS secret exists
  if ! oc get secret $TLS_SECRET_NAME -n $NAMESPACE &>/dev/null; then
    vault_log "Error: TLS secret '$TLS_SECRET_NAME' not found in namespace $NAMESPACE"
    vault_log "Make sure to run apply-vault-cert-manager.sh to create certificates with cert-manager"
    return 1
  fi

  # Verify the secret has the required keys
  if ! oc get secret $TLS_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -q "tls.crt" || \
     ! oc get secret $TLS_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -q "tls.key"; then
    vault_log "Error: TLS secret does not contain the required keys (tls.crt and tls.key)"
    return 1
  fi

  vault_log "TLS certificates verified successfully"
  return 0
}

# Function to check Vault status
check_vault_status() {
  local pod=$1
  vault_log "Checking Vault status on $pod"
  
  local status_output
  status_output=$(oc exec $pod -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault status -format=json -tls-skip-verify" 2>/dev/null)
  local exit_code=$?
  
  # Vault status command returns exit code 2 when sealed, which is still valid for our purposes
  if [ $exit_code -ne 0 ] && [ $exit_code -ne 2 ]; then
    vault_log "Warning: Could not get Vault status on $pod"
    return 1
  fi
  
  # Check if we got valid JSON output
  if echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -e . >/dev/null 2>&1; then
    vault_log "Successfully retrieved Vault status from $pod"
    echo "$status_output"
    return 0
  else
    vault_log "Warning: Invalid status output from $pod"
    return 1
  fi
}

# Function to initialize Vault
initialize_vault() {
  vault_log "Initializing Vault on $VAULT_LEADER_POD"
  
  # Run vault operator init
  local init_output
  init_output=$(oc exec $VAULT_LEADER_POD -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault operator init -key-shares=5 -key-threshold=3 -format=json -tls-skip-verify" 2>/dev/null)
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    vault_log "Error initializing Vault: $init_output"
    return 1
  fi
  
  # Extract JSON from initialization output (pure JSON, no log messages)
  local json_output
  json_output=$(echo "$init_output" | jq -c '.' 2>/dev/null)

  vault_log "Extracted initialization JSON: ${json_output:0:100}..."
  
  # Extract unseal keys and root token
  UNSEAL_KEY_1=$(echo "$json_output" | jq -r '.unseal_keys_b64[0]')
  UNSEAL_KEY_2=$(echo "$json_output" | jq -r '.unseal_keys_b64[1]')
  UNSEAL_KEY_3=$(echo "$json_output" | jq -r '.unseal_keys_b64[2]')
  ROOT_TOKEN=$(echo "$json_output" | jq -r '.root_token')
  
  # Save keys to file
  cat > vault-keys.env <<EOF
# Vault unseal keys and root token
UNSEAL_KEY_1="$UNSEAL_KEY_1"
UNSEAL_KEY_2="$UNSEAL_KEY_2"
UNSEAL_KEY_3="$UNSEAL_KEY_3"
ROOT_TOKEN="$ROOT_TOKEN"
EOF
  
  vault_log "Vault initialized successfully"
  vault_log "Unseal keys and root token saved to vault-keys.env"
  return 0
}

# Function to unseal Vault
unseal_vault() {
  local pod=$1
  vault_log "Unsealing $pod"
  
  # Check if already unsealed
  local status_output
  status_output=$(check_vault_status "$pod")
  if [ $? -ne 0 ]; then
    vault_log "Warning: Could not check if $pod is already unsealed"
  else
    # Extract JSON from mixed output (log messages + JSON)
    local json_output
    json_output=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -c '.' 2>/dev/null)
    
    local sealed
    sealed=$(echo "$json_output" | jq -r '.sealed')
    
    if [ "$sealed" == "false" ]; then
      vault_log "$pod is already unsealed"
      return 0
    fi
  fi
  
  # Apply unseal keys
  vault_log "Applying unseal key 1"
  oc exec $pod -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault operator unseal -tls-skip-verify $UNSEAL_KEY_1" > /dev/null
  
  vault_log "Applying unseal key 2"
  oc exec $pod -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault operator unseal -tls-skip-verify $UNSEAL_KEY_2" > /dev/null
  
  vault_log "Applying unseal key 3"
  oc exec $pod -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault operator unseal -tls-skip-verify $UNSEAL_KEY_3" > /dev/null
  
  # Verify unsealed
  status_output=$(check_vault_status "$pod")
  if [ $? -ne 0 ]; then
    vault_log "Error: Could not verify if $pod was unsealed"
    return 1
  fi
  
  local json_output
  json_output=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -c '.' 2>/dev/null)
  sealed=$(echo "$json_output" | jq -r '.sealed')
  
  if [ "$sealed" == "false" ]; then
    vault_log "$pod successfully unsealed"
    return 0
  else
    vault_log "Error: Failed to unseal $pod"
    return 1
  fi
}
# Verify TLS certificates before proceeding
verify_tls_certificates || {
  vault_log "Error: TLS certificate verification failed. Please ensure cert-manager has created the required certificates."
  exit 1
}

# Check if Vault is already initialized
vault_log "Checking Vault initialization status on $VAULT_LEADER_POD"
STATUS_OUTPUT=$(check_vault_status "$VAULT_LEADER_POD")

if [ $? -ne 0 ]; then
  vault_log "ERROR: Could not check Vault initialization status"
  exit 1
fi

# Extract JSON from mixed output (log messages + JSON)
# First extract just the JSON part, then use jq for parsing
JSON_OUTPUT=$(echo "$STATUS_OUTPUT" | sed -n '/^{/,/^}$/p' | jq -c '.' 2>/dev/null)
vault_log "Extracted JSON: ${JSON_OUTPUT:0:200}..."

# Check if we have valid JSON
if [ -z "$JSON_OUTPUT" ]; then
  vault_log "ERROR: Could not extract JSON from Vault status output"
  vault_log "Raw output: $STATUS_OUTPUT"
  exit 1
fi

# Parse initialization status
INIT_STATUS=$(echo "$JSON_OUTPUT" | jq -r .initialized 2>/dev/null)
if [ -z "$INIT_STATUS" ]; then
  vault_log "WARNING: Could not parse initialization status, assuming not initialized"
  INIT_STATUS="false"
fi
vault_log "Initialization status: $INIT_STATUS"

# Parse sealed status
SEALED_STATUS=$(echo "$JSON_OUTPUT" | jq -r .sealed 2>/dev/null)
if [ -z "$SEALED_STATUS" ]; then
  vault_log "WARNING: Could not parse sealed status, assuming sealed"
  SEALED_STATUS="true"
fi
vault_log "Sealed status: $SEALED_STATUS"

vault_log "Vault initialization status: $INIT_STATUS"
vault_log "Vault sealed status: $SEALED_STATUS"

# Initialize Vault if not already initialized
if [ "$INIT_STATUS" != "true" ]; then
  initialize_vault
  if [ $? -ne 0 ]; then
    vault_log "ERROR: Failed to initialize Vault"
    exit 1
  fi
else
  vault_log "Vault is already initialized. Using existing unseal keys and root token."
  
  # Check if we have unseal keys and root token
  if [ -n "$UNSEAL_KEY_1" ] && [ -n "$UNSEAL_KEY_2" ] && [ -n "$UNSEAL_KEY_3" ] && [ -n "$ROOT_TOKEN" ]; then
    vault_log "Using unseal keys and root token from script variables"
  else
    vault_log "ERROR: Vault is initialized but no unseal keys or root token provided"
    exit 1
  fi
fi

# Unseal the leader pod
vault_log "Unsealing the leader pod: $VAULT_LEADER_POD"
unseal_vault "$VAULT_LEADER_POD"

if [ $? -ne 0 ]; then
  vault_log "ERROR: Failed to unseal the leader pod $VAULT_LEADER_POD"
  exit 1
fi

# Function to join a pod to the Raft cluster
join_raft_cluster() {
  local pod=$1
  vault_log "Joining $pod to the Raft cluster"
  
  # Construct the leader URL using the service name for proper DNS resolution
  # This should match the SANs in the TLS certificate
  local leader_url="https://${VAULT_LEADER_POD}.${VAULT_INTERNAL_SERVICE}:8200"
  vault_log "Using leader URL: $leader_url"
  
  # Verify TLS certificates exist in the pod
  local cert_check
  cert_check=$(oc exec $pod -n $NAMESPACE -- sh -c "ls -la /vault/userconfig/vault-tls/" 2>&1)
  vault_log "Certificate files in pod $pod: $cert_check"
  
  # Check if the leader pod is unsealed and ready to accept join requests
  local leader_status
  leader_status=$(check_vault_status "$VAULT_LEADER_POD")
  local leader_sealed
  leader_sealed=$(echo "$leader_status" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)
  
  if [ "$leader_sealed" == "true" ]; then
    vault_log "ERROR: Leader pod is sealed. Cannot join $pod to the Raft cluster."
    return 1
  fi
  
  vault_log "Leader pod is unsealed. Proceeding with join operation."
  
  # Execute the join command with proper TLS skip verification
  local join_output
  join_output=$(oc exec $pod -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && vault operator raft join -tls-skip-verify -leader-ca-cert=/vault/userconfig/vault-tls/tls.crt -leader-client-cert=/vault/userconfig/vault-tls/tls.crt -leader-client-key=/vault/userconfig/vault-tls/tls.key $leader_url" 2>&1)
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    vault_log "Warning: Failed to join $pod to the Raft cluster. Error details:"
    vault_log "$join_output"
    
    # Check for specific error patterns
    if echo "$join_output" | grep -q "TLS certificate"; then
      vault_log "TLS certificate issue detected. Verifying certificate content and SANs..."
      oc exec $pod -n $NAMESPACE -- sh -c "openssl x509 -in /vault/userconfig/vault-tls/tls.crt -text -noout | grep -A1 'Subject Alternative Name'" 2>&1
    elif echo "$join_output" | grep -q "Vault is sealed"; then
      vault_log "Leader Vault is sealed. This should not happen as we verified it earlier."
      vault_log "Attempting to unseal leader again..."
      unseal_vault "$VAULT_LEADER_POD"
    fi
    
    return 1
  else
    vault_log "Successfully joined $pod to the Raft cluster"
    return 0
  fi
}

# Function to check Raft cluster status
check_raft_status() {
  vault_log "Checking Raft cluster status"
  
  local raft_status
  raft_status=$(oc exec $VAULT_LEADER_POD -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=$TLS_SKIP_VERIFY && export VAULT_ADDR=https://localhost:8200 && export VAULT_TOKEN=$ROOT_TOKEN && vault operator raft list-peers -tls-skip-verify" 2>&1)
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    vault_log "Warning: Failed to get Raft cluster status: $raft_status"
    return 1
  else
    echo "$raft_status" > /tmp/raft-peers.txt
    vault_log "Current Raft cluster status:"
    echo "$raft_status"
    return 0
  fi
}

# Get the Raft cluster status to see if other nodes are already joined
check_raft_status || {
  vault_log "Warning: Failed to get Raft cluster status, will proceed with joining nodes anyway"
  # Create an empty file so the script can continue
  touch /tmp/raft-peers.txt
}

# First ensure the leader pod is fully unsealed and operational
vault_log "Ensuring leader pod is fully unsealed and operational before joining other nodes"
status_output=$(check_vault_status "$VAULT_LEADER_POD")
leader_sealed=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)

if [ "$leader_sealed" == "true" ]; then
  vault_log "Leader pod is still sealed. Unsealing again..."
  unseal_vault "$VAULT_LEADER_POD"
  
  # Verify leader is unsealed now
  sleep 5
  status_output=$(check_vault_status "$VAULT_LEADER_POD")
  leader_sealed=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)
  
  if [ "$leader_sealed" == "true" ]; then
    vault_log "ERROR: Failed to unseal leader pod after multiple attempts. Cannot proceed with HA setup."
    exit 1
  fi
fi

vault_log "Leader pod is unsealed and operational. Proceeding with joining and unsealing other nodes."

# Join and unseal the other nodes
for pod in vault-1 vault-2; do
  # Check if the pod is already in the Raft cluster
  if ! grep -q "$pod" /tmp/raft-peers.txt; then
    # Wait for the pod to be ready
    wait_for_pod $pod
    
    # First unseal the pod - this is important for Raft join to work properly
    vault_log "Unsealing $pod before joining to Raft cluster"
    unseal_vault $pod

    # Verify unsealing was successful
    sleep 5
    status_output=$(check_vault_status "$pod")
    sealed=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)

    if [ "$sealed" == "true" ]; then
      vault_log "WARNING: $pod is still sealed. Attempting to join anyway but this may fail."
    else
      vault_log "$pod is unsealed. Now joining to Raft cluster."
    fi
    
    # Join the pod to the Raft cluster
    join_raft_cluster $pod
    
    # If join failed, try restarting the pod and try again
    if [ $? -ne 0 ]; then
      vault_log "Join failed. Restarting $pod to try again."
      oc delete pod $pod -n $NAMESPACE
      wait_for_pod $pod
      unseal_vault $pod
      sleep 5
      join_raft_cluster $pod
    fi
  else
    vault_log "$pod is already part of the Raft cluster"
    # Still ensure it's unsealed
    unseal_vault $pod
  fi
  
  # Final verification
  sleep 5
  status_output=$(check_vault_status "$pod")
  if [ $? -ne 0 ]; then
    vault_log "Warning: Could not verify if $pod was unsealed and joined successfully"
  else
    sealed=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)
    if [ "$sealed" == "false" ]; then
      vault_log "$pod is unsealed and operational"
    else
      vault_log "Warning: $pod is still sealed after applying unseal keys"
    fi
  fi
done

# Update the Raft cluster status after all operations
check_raft_status

vault_log "Vault initialization and unsealing completed"
vault_log "Root token saved to: /tmp/root-token.txt"
vault_log "Unseal keys saved to: /tmp/unseal-keys.txt"

# Check pod status
vault_log "Checking pod status:"
oc get pods -n $NAMESPACE

# Check status of each Vault pod
for pod in vault-0 vault-1 vault-2; do
  vault_log "Status of $pod:"
  status_output=$(check_vault_status "$pod")
  if [ $? -ne 0 ]; then
    vault_log "Warning: Could not get status of $pod"
  else
    # Format the status output for better readability
    echo "$status_output" | sed -n '/^{/,/^}$/p' | jq '.'
  fi
done

# Check route
VAULT_ROUTE=$(oc get route -n $NAMESPACE -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
if [ -n "$VAULT_ROUTE" ]; then
  vault_log "Vault is accessible at: https://$VAULT_ROUTE"
else
  vault_log "Warning: Could not find Vault route"
fi

# Final verification
vault_log "Verifying Vault HA cluster is fully operational:"
SECRETS_LIST=$(oc exec $VAULT_LEADER_POD -n $NAMESPACE -- sh -c "export VAULT_SKIP_VERIFY=true && export VAULT_ADDR=https://localhost:8200 && export VAULT_TOKEN=$ROOT_TOKEN && vault secrets list" 2>&1)
if [ $? -ne 0 ]; then
  vault_log "Warning: Could not list secrets: $SECRETS_LIST"
else
  vault_log "Vault secrets engines:"
  echo "$SECRETS_LIST"
fi

# Check if all pods are unsealed
ALL_UNSEALED=true
for pod in vault-0 vault-1 vault-2; do
  status_output=$(check_vault_status "$pod")
  if [ $? -ne 0 ]; then
    vault_log "Warning: Could not check if $pod is unsealed"
    ALL_UNSEALED=false
  else
    sealed=$(echo "$status_output" | sed -n '/^{/,/^}$/p' | jq -r '.sealed' 2>/dev/null)
    if [ "$sealed" == "true" ]; then
      vault_log "Warning: $pod is still sealed"
      ALL_UNSEALED=false
    fi
  fi
done

if [ "$ALL_UNSEALED" == "true" ]; then
  vault_log "SUCCESS: All Vault pods are unsealed and the HA cluster is fully operational."
else
  vault_log "WARNING: Not all Vault pods are unsealed. The HA cluster may not be fully operational."
fi

vault_log "Troubleshooting completed. Vault HA cluster setup process has finished."
