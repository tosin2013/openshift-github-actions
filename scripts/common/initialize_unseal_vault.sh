#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Causes a pipeline to return the exit status of the last command in the pipe that returned a non-zero return value.

# --- Constants ---
MAX_RETRIES=30
RETRY_DELAY=10
VAULT_INIT_TIMEOUT=300  # 5 minutes for Vault initialization
VAULT_UNSEAL_TIMEOUT=300  # 5 minutes for unsealing

echo "Starting Vault Initialization and Unsealing Process from script..."

# Inputs from GitHub Actions (passed as environment variables)
NAMESPACE="${GITHUB_EVENT_INPUTS_NAMESPACE}"
REPLICAS="${GITHUB_EVENT_INPUTS_REPLICAS}"
AUTO_UNSEAL_ENABLED="${GITHUB_EVENT_INPUTS_AUTO_UNSEAL}"
# CLOUD_PROVIDER="${GITHUB_EVENT_INPUTS_CLOUD_PROVIDER}" # If needed

# Secrets (ensure these are available as env vars when running locally if needed)
# SECRETS_VAULT_ROOT_TOKEN
# SECRETS_VAULT_UNSEAL_KEY_0, _1, _2, _3, _4

# GITHUB_ENV and GITHUB_OUTPUT should be set to file paths for local testing
# e.g., GITHUB_ENV=$(mktemp) GITHUB_OUTPUT=$(mktemp) ./scripts/vault/initialize_unseal_vault.sh
if [ -z "$GITHUB_ENV" ] || [ -z "$GITHUB_OUTPUT" ]; then
    log_error "GITHUB_ENV and GITHUB_OUTPUT must be set to valid file paths for this script to run."
fi

# --- Helper Functions ---
log_info() {
    echo "ℹ️  $1"
}

log_warning() {
    echo "⚠️  $1" >&2
}

log_error() {
    echo "::error::$1" >&2
    exit 1
}

# Check Vault status with timeout
check_vault_status() {
    local pod_name=$1
    local timeout=${2:-60}  # Default 60 seconds
    local start_time=$(date +%s)
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        local status_output
        status_output=$(oc exec -n "$NAMESPACE" "$pod_name" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "$status_output"
            return 0
        fi
        
        sleep 2
    done
    
    log_warning "Timed out waiting for Vault status on $pod_name"
    return 1
}

log_info "Namespace: $NAMESPACE"
log_info "Replicas: $REPLICAS"
log_info "Auto-unseal enabled: $AUTO_UNSEAL_ENABLED"

# --- Helper function to get pod names ---
get_vault_pod_names() {
  oc get pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'
}

# --- Wait for all Vault pods to be in Running state ---
echo "Ensuring all Vault pods are in Running state..."
# This loop assumes pods are being created by Helm or another process.
# For local testing of *just this script*, pods might not exist yet if Helm wasn't run.
# If running this script standalone after a 'helm delete' and 'oc new-project',
# there will be no pods to find. The script is designed to run *after* Helm deployment.
# For now, we'll proceed, but if no pods are found, it will fail here.
# This is expected if Helm hasn't deployed Vault into the new 'vault' namespace yet.

EXPECTED_POD_COUNT=$( [ -z "$REPLICAS" ] && echo "1" || echo "$REPLICAS" ) # Default to 1 if REPLICAS is not set for some reason

for i in {1..30}; do
  RUNNING_PODS_OUTPUT=$(oc get pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null || true)
  RUNNING_PODS_COUNT=$(echo "$RUNNING_PODS_OUTPUT" | wc -w | tr -d ' ')
  
  TOTAL_PODS_OUTPUT=$(oc get pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" --no-headers 2>/dev/null || true)
  TOTAL_PODS_COUNT=$(echo "$TOTAL_PODS_OUTPUT" | wc -l | tr -d ' ')
  
  echo "Running pods: $RUNNING_PODS_COUNT/$TOTAL_PODS_COUNT (Expected at least: $EXPECTED_POD_COUNT)"

  # Check if we have at least the expected number of pods and all of them are running
  if [ "$RUNNING_PODS_COUNT" -ge "$EXPECTED_POD_COUNT" ] && [ "$RUNNING_PODS_COUNT" -eq "$TOTAL_PODS_COUNT" ] && [ "$TOTAL_PODS_COUNT" -gt 0 ]; then
    echo "All $TOTAL_PODS_COUNT Vault pods are running."
    break
  fi

  if [ $i -eq 30 ]; then
    echo "::error::Timed out waiting for all Vault pods to be Running. Current state:"
    oc get pods -l app.kubernetes.io/name=vault -n "$NAMESPACE" || echo "Could not get pod status."
    echo "If this is a local test of the script *without* running Helm first, this failure is expected as no pods exist."
    exit 1
  fi
  echo "Waiting for Vault pods to be Running... ($i/30)"
  sleep 10
done

# Variables to hold the effective root token and unseal keys for script's internal use
EFFECTIVE_ROOT_TOKEN=""
EFFECTIVE_UNSEAL_KEYS=() # Array

if [ "$AUTO_UNSEAL_ENABLED" == "false" ]; then
  echo "Manual unsealing process initiated..."

  echo "Checking initialization status of vault-0..."
  VAULT_0_STATUS_OUTPUT_PRE_INIT=$(oc exec -n "$NAMESPACE" vault-0 -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null)
  VAULT_0_STATUS_EXIT_CODE_PRE_INIT=$?

  IS_INITIALIZED="false" 

  if [ $VAULT_0_STATUS_EXIT_CODE_PRE_INIT -eq 0 ]; then
      IS_INITIALIZED="true"
  elif [ $VAULT_0_STATUS_EXIT_CODE_PRE_INIT -eq 2 ]; then
      PARSED_INIT_STATUS=$(echo "$VAULT_0_STATUS_OUTPUT_PRE_INIT" | jq -r '.initialized')
      if [ "$PARSED_INIT_STATUS" == "true" ]; then
          IS_INITIALIZED="true"
      else
          IS_INITIALIZED="false"
      fi
  else
      echo "::warning::Could not determine pre-initialization status of vault-0 (exit code $VAULT_0_STATUS_EXIT_CODE_PRE_INIT). Output: $VAULT_0_STATUS_OUTPUT_PRE_INIT. Assuming not initialized."
      IS_INITIALIZED="false"
  fi
  echo "Initial check: vault-0 IS_INITIALIZED = $IS_INITIALIZED"

  if [ "$IS_INITIALIZED" == "true" ]; then
    echo "Vault is already initialized. Using unseal keys and root token from secrets if provided..."
    EFFECTIVE_ROOT_TOKEN="$SECRETS_VAULT_ROOT_TOKEN"
    [ ! -z "$SECRETS_VAULT_UNSEAL_KEY_0" ] && EFFECTIVE_UNSEAL_KEYS+=("$SECRETS_VAULT_UNSEAL_KEY_0")
    [ ! -z "$SECRETS_VAULT_UNSEAL_KEY_1" ] && EFFECTIVE_UNSEAL_KEYS+=("$SECRETS_VAULT_UNSEAL_KEY_1")
    [ ! -z "$SECRETS_VAULT_UNSEAL_KEY_2" ] && EFFECTIVE_UNSEAL_KEYS+=("$SECRETS_VAULT_UNSEAL_KEY_2")
    [ ! -z "$SECRETS_VAULT_UNSEAL_KEY_3" ] && EFFECTIVE_UNSEAL_KEYS+=("$SECRETS_VAULT_UNSEAL_KEY_3")
    [ ! -z "$SECRETS_VAULT_UNSEAL_KEY_4" ] && EFFECTIVE_UNSEAL_KEYS+=("$SECRETS_VAULT_UNSEAL_KEY_4")

    [ ! -z "$SECRETS_VAULT_ROOT_TOKEN" ] && echo "VAULT_ROOT_TOKEN=$SECRETS_VAULT_ROOT_TOKEN" >> "$GITHUB_ENV"
    for i in {0..4}; do
        secret_key_var="SECRETS_VAULT_UNSEAL_KEY_$i"
        if [ ! -z "${!secret_key_var}" ]; then
            echo "VAULT_UNSEAL_KEY_$i=${!secret_key_var}" >> "$GITHUB_ENV"
        fi
    done
  else
    echo "Initializing Vault on vault-0 (5 keys, 3 threshold)..."
    INIT_COMMAND_STDERR_FILE=$(mktemp)
    set +e 
    INIT_OUTPUT=$(oc exec -n "$NAMESPACE" vault-0 -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault operator init -key-shares=5 -key-threshold=3 -format=json" 2> "$INIT_COMMAND_STDERR_FILE")
    INIT_EXIT_CODE=$?
    set -e 
    INIT_STDERR_CONTENT=$(cat "$INIT_COMMAND_STDERR_FILE")
    rm "$INIT_COMMAND_STDERR_FILE"

    echo "DEBUG: Vault Operator Init Command Exit Code: $INIT_EXIT_CODE"
    echo "DEBUG: Vault Operator Init Command STDOUT: $INIT_OUTPUT"
    echo "DEBUG: Vault Operator Init Command STDERR: $INIT_STDERR_CONTENT"

    if [ $INIT_EXIT_CODE -ne 0 ] || [ -z "$INIT_OUTPUT" ]; then
      echo "::error::Vault operator init command failed (Code: $INIT_EXIT_CODE) or produced no output."
      echo "::group::vault-0 pod logs on init failure"
      oc logs -n "$NAMESPACE" vault-0 --tail=50 || echo "Failed to get vault-0 logs."
      echo "::endgroup::"
      exit 1
    fi

    EFFECTIVE_ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
    if [ -z "$EFFECTIVE_ROOT_TOKEN" ] || [ "$EFFECTIVE_ROOT_TOKEN" == "null" ]; then
        echo "::error::Failed to parse root token from init output. Output was: $INIT_OUTPUT"
        exit 1
    fi
    echo "::add-mask::$EFFECTIVE_ROOT_TOKEN"
    echo "VAULT_ROOT_TOKEN=$EFFECTIVE_ROOT_TOKEN" >> "$GITHUB_ENV"
    echo "Root token stored in GITHUB_ENV."

    echo "Storing unseal keys..."
    for j in {0..4}; do
      KEY=$(echo "$INIT_OUTPUT" | jq -r ".unseal_keys_b64[$j]")
      if [ -z "$KEY" ] || [ "$KEY" == "null" ]; then
          echo "::error::Failed to parse unseal key $j from init output. Output was: $INIT_OUTPUT"
      fi
      echo "::add-mask::$KEY"
      EFFECTIVE_UNSEAL_KEYS+=("$KEY")
      echo "VAULT_UNSEAL_KEY_$j=$KEY" >> "$GITHUB_ENV"
    done
    echo "Unseal keys stored in GITHUB_ENV."
  fi

  echo "Proceeding to unseal all Vault pods manually..."
  for pod_name in $(get_vault_pod_names); do
    echo "Processing pod $pod_name for unsealing..."
    
    IS_POD_SEALED_FOR_UNSEAL_LOGIC="true" 
    CURRENT_STATUS_OUTPUT_UNSEAL=$(oc exec -n "$NAMESPACE" "$pod_name" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null)
    CURRENT_STATUS_EXIT_CODE_UNSEAL=$?
    echo "Debug: Pod $pod_name, vault status raw exit code (before unseal attempt): $CURRENT_STATUS_EXIT_CODE_UNSEAL"

    if [ $CURRENT_STATUS_EXIT_CODE_UNSEAL -eq 0 ]; then 
        IS_POD_SEALED_FOR_UNSEAL_LOGIC="false"
    elif [ $CURRENT_STATUS_EXIT_CODE_UNSEAL -eq 2 ]; then 
        IS_POD_SEALED_FOR_UNSEAL_LOGIC="true"
    else 
        echo "::warning::Pod $pod_name: 'vault status' command failed (Code: $CURRENT_STATUS_EXIT_CODE_UNSEAL). Output: $CURRENT_STATUS_OUTPUT_UNSEAL. Assuming sealed."
    fi
    echo "Debug: Pod $pod_name, determined IS_POD_SEALED_FOR_UNSEAL_LOGIC: $IS_POD_SEALED_FOR_UNSEAL_LOGIC"

    if [ "$IS_POD_SEALED_FOR_UNSEAL_LOGIC" == "true" ]; then
      echo "Vault pod $pod_name is considered sealed. Attempting to unseal..."
      if [ ${#EFFECTIVE_UNSEAL_KEYS[@]} -lt 3 ]; then # Check against threshold (3)
          echo "::error::Not enough unseal keys available (found ${#EFFECTIVE_UNSEAL_KEYS[@]}, need at least 3). Cannot unseal $pod_name."
          continue
      fi
      
      UNSEAL_SUCCESS=false
      for attempt in {1..3}; do
        echo "Unseal attempt $attempt for $pod_name..."
        for k_idx in 0 1 2; do # Apply first 3 keys
            if [ -n "${EFFECTIVE_UNSEAL_KEYS[$k_idx]}" ]; then
                oc exec -n "$NAMESPACE" "$pod_name" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault operator unseal ${EFFECTIVE_UNSEAL_KEYS[$k_idx]}" || echo "Warning: Command to apply key $k_idx failed for $pod_name attempt $attempt"
                sleep 1
            else
                echo "::warning::Unseal key $k_idx is empty. Skipping for $pod_name."
            fi
        done
        sleep 2

        POST_UNSEAL_STATUS_JSON=$(oc exec -n "$NAMESPACE" "$pod_name" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null)
        POST_UNSEAL_STATUS_EXIT_CODE=$?
        
        if [ $POST_UNSEAL_STATUS_EXIT_CODE -eq 0 ]; then
            echo "Successfully unsealed pod $pod_name."
            UNSEAL_SUCCESS=true; break
        fi
        echo "Warning: Failed to unseal pod $pod_name on attempt $attempt (vault status exit code: $POST_UNSEAL_STATUS_EXIT_CODE). Retrying..."
        sleep 3
      done
      if [ "$UNSEAL_SUCCESS" == "false" ]; then echo "::error::Failed to unseal pod $pod_name."; fi
    else
      echo "Vault pod $pod_name is already unsealed."
    fi
  done
  echo "Manual unsealing process completed for all pods."

else 
  echo "Auto-unsealing is enabled. Skipping manual init/unseal. Waiting 60s for stabilization..."
  sleep 60
  if [ ! -z "$SECRETS_VAULT_ROOT_TOKEN" ]; then
      EFFECTIVE_ROOT_TOKEN="$SECRETS_VAULT_ROOT_TOKEN" 
      echo "VAULT_ROOT_TOKEN=$SECRETS_VAULT_ROOT_TOKEN" >> "$GITHUB_ENV"
      echo "Root token from secret (for auto-unseal scenario) stored in GITHUB_ENV."
  else
      echo "::warning::Auto-unseal is enabled, but no VAULT_ROOT_TOKEN secret was provided."
  fi
fi

echo "Verifying unseal and initialization status of all Vault pods..."
ALL_OPERATIONAL=true 
for pod_name in $(get_vault_pod_names); do
  echo "Verifying status of $pod_name..."
  IS_POD_OPERATIONAL_THIS_ROUND=false
  for attempt in {1..3}; do 
    echo "Verification attempt $attempt for $pod_name..."
    set +e 
    VAULT_STATUS_OUTPUT_VERIFY=$(oc exec -n "$NAMESPACE" "$pod_name" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json")
    OC_EXEC_EXIT_CODE_VERIFY=$?
    set -e 

    echo "Debug (Verification): Pod $pod_name, vault status raw exit code: $OC_EXEC_EXIT_CODE_VERIFY"
    if [ $OC_EXEC_EXIT_CODE_VERIFY -eq 0 ]; then
      echo "Pod $pod_name is initialized and unsealed."
      IS_POD_OPERATIONAL_THIS_ROUND=true; break
    else
      INITIALIZED_STATUS_VERIFY="unknown"
      SEALED_STATUS_VERIFY="unknown"
      if [ -n "$VAULT_STATUS_OUTPUT_VERIFY" ]; then # Only parse if output is not empty
        INITIALIZED_STATUS_VERIFY=$(echo "$VAULT_STATUS_OUTPUT_VERIFY" | jq -r '.initialized' 2>/dev/null || echo "parse_error")
        SEALED_STATUS_VERIFY=$(echo "$VAULT_STATUS_OUTPUT_VERIFY" | jq -r '.sealed' 2>/dev/null || echo "parse_error")
      fi
      echo "Warning: Pod $pod_name not fully operational (Code: $OC_EXEC_EXIT_CODE_VERIFY). Initialized: $INITIALIZED_STATUS_VERIFY, Sealed: $SEALED_STATUS_VERIFY. Attempt $attempt/3."
    fi
    if [ $attempt -lt 3 ]; then sleep 5; fi
  done
  if [ "$IS_POD_OPERATIONAL_THIS_ROUND" == "false" ]; then
    echo "::error::Pod $pod_name did not become operational."; ALL_OPERATIONAL=false;
  fi
done

if [ "$ALL_OPERATIONAL" == "true" ]; then
  echo "All Vault pods are confirmed initialized and unsealed successfully."
  echo "all_pods_unsealed=true" >> "$GITHUB_OUTPUT"
else
  echo "::error::Not all Vault pods are operational after unsealing attempts."
  echo "all_pods_unsealed=false" >> "$GITHUB_OUTPUT"
  echo "::group::Vault Pod Logs on Failure"
  for pod_name_log_fail in $(get_vault_pod_names); do
    echo "--- Logs for $pod_name_log_fail ---"
    oc logs -n "$NAMESPACE" "$pod_name_log_fail" --tail=100 || echo "Failed to get logs for $pod_name_log_fail"
  done
  echo "::endgroup::"
  exit 1
fi
echo "Vault initialization and unsealing verification step completed."
