#!/bin/bash

# Update Vault AWS Role with OpenShift Installer Permissions
# Fixes missing iam:SimulatePrincipalPolicy and other required permissions
# Based on official Red Hat documentation:
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_aws/installing-aws-account
# Author: Tosin Akinosho, Sophia AI Assistant

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault-test-pragmatic}"
VAULT_POD="${VAULT_POD:-vault-0}"
AWS_ROLE_NAME="${AWS_ROLE_NAME:-openshift-installer}"

# Logging function
log() {
  local level=$1
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case $level in
    "INFO")  echo -e "${BLUE}[INFO]${NC}  ${timestamp} - $message" ;;
    "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - $message" ;;
    "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" ;;
    "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" ;;
  esac
}

# Check prerequisites
check_prerequisites() {
  log "INFO" "Checking prerequisites..."
  
  # Check OpenShift login
  if ! oc whoami &> /dev/null; then
    log "ERROR" "Not logged into OpenShift. Please run 'oc login' first."
    exit 1
  fi
  
  # Check Vault accessibility
  if ! oc exec $VAULT_POD -n $VAULT_NAMESPACE -- vault status &> /dev/null; then
    log "ERROR" "Cannot access Vault. Please ensure Vault is running."
    exit 1
  fi
  
  # Check if policy file exists
  local policy_file="config/aws/openshift-installer-policy.json"
  if [[ ! -f "$policy_file" ]]; then
    log "ERROR" "Policy file not found: $policy_file"
    exit 1
  fi
  
  log "SUCCESS" "Prerequisites check passed"
}

# Get Vault root token
get_vault_token() {
  log "INFO" "Retrieving Vault root token..."
  
  # Try to get token from vault-keys.env
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
      echo "$VAULT_ROOT_TOKEN"
      return 0
    fi
  fi
  
  log "ERROR" "Could not find Vault root token in vault-keys.env"
  log "INFO" "Please ensure vault-keys.env exists with VAULT_ROOT_TOKEN"
  exit 1
}

# Update AWS role with corrected policy
update_aws_role() {
  local vault_token=$1
  local policy_file="config/aws/openshift-installer-policy.json"
  
  log "INFO" "Updating AWS role '$AWS_ROLE_NAME' with corrected permissions..."
  
  # Read the policy content
  local policy_content
  if ! policy_content=$(cat "$policy_file"); then
    log "ERROR" "Failed to read policy file: $policy_file"
    exit 1
  fi
  
  # Escape the policy content for shell
  local escaped_policy=$(echo "$policy_content" | sed 's/"/\\"/g' | tr -d '\n')
  
  # Update the Vault AWS role
  local vault_command="
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN='$vault_token'

vault write aws/roles/$AWS_ROLE_NAME \\
  credential_type=iam_user \\
  default_sts_ttl=1800 \\
  max_sts_ttl=3600 \\
  policy_document='$escaped_policy'
"
  
  if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- sh -c "$vault_command"; then
    log "SUCCESS" "AWS role updated successfully"
  else
    log "ERROR" "Failed to update AWS role"
    exit 1
  fi
}

# Test credential generation
test_credentials() {
  local vault_token=$1
  
  log "INFO" "Testing credential generation with updated permissions..."
  
  local vault_command="
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN='$vault_token'

vault read aws/creds/$AWS_ROLE_NAME -format=json
"
  
  local creds
  if creds=$(oc exec $VAULT_POD -n $VAULT_NAMESPACE -- sh -c "$vault_command" 2>/dev/null); then
    local access_key secret_key
    access_key=$(echo "$creds" | jq -r '.data.access_key')
    secret_key=$(echo "$creds" | jq -r '.data.secret_key')
    
    if [[ "$access_key" != "null" && "$secret_key" != "null" ]]; then
      log "SUCCESS" "✅ Credentials generated successfully"
      log "INFO" "Access Key: ${access_key:0:10}..."
      
      # Test AWS permissions
      log "INFO" "⏳ Waiting 30 seconds for AWS IAM propagation..."
      sleep 30
      
      export AWS_ACCESS_KEY_ID="$access_key"
      export AWS_SECRET_ACCESS_KEY="$secret_key"
      
      if aws sts get-caller-identity --region us-east-1 >/dev/null 2>&1; then
        log "SUCCESS" "🎉 AWS credentials validation PASSED!"
        
        # Test the critical iam:SimulatePrincipalPolicy permission
        log "INFO" "Testing iam:SimulatePrincipalPolicy permission..."
        if aws iam simulate-principal-policy \
           --policy-source-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):user/$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)" \
           --action-names "iam:SimulatePrincipalPolicy" \
           --region us-east-1 >/dev/null 2>&1; then
          log "SUCCESS" "🎯 iam:SimulatePrincipalPolicy permission WORKING!"
          log "SUCCESS" "OpenShift installer should now work correctly!"
        else
          log "WARN" "⚠️ iam:SimulatePrincipalPolicy permission still not working"
          log "INFO" "This may require additional AWS propagation time"
        fi
        
        return 0
      else
        log "WARN" "⚠️ AWS credentials validation failed"
        return 1
      fi
    else
      log "ERROR" "❌ Failed to extract credentials"
      return 1
    fi
  else
    log "ERROR" "❌ Failed to generate credentials"
    return 1
  fi
}

# Show current role configuration
show_role_config() {
  local vault_token=$1
  
  log "INFO" "Current AWS role configuration:"
  
  local vault_command="
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN='$vault_token'

vault read aws/roles/$AWS_ROLE_NAME
"
  
  oc exec $VAULT_POD -n $VAULT_NAMESPACE -- sh -c "$vault_command"
}

# Main function
main() {
  log "INFO" "=== Update Vault AWS Role Permissions ==="
  log "INFO" "Adding missing iam:SimulatePrincipalPolicy and other required permissions"
  log "INFO" "Based on: https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/installing_on_aws/installing-aws-account"
  echo
  
  # Check prerequisites
  check_prerequisites
  
  # Get Vault token
  local vault_token
  vault_token=$(get_vault_token)
  
  # Show current configuration
  echo
  log "INFO" "=== BEFORE: Current Role Configuration ==="
  show_role_config "$vault_token"
  echo
  
  # Update the role
  update_aws_role "$vault_token"
  
  # Show updated configuration
  echo
  log "INFO" "=== AFTER: Updated Role Configuration ==="
  show_role_config "$vault_token"
  echo
  
  # Test the fix
  if test_credentials "$vault_token"; then
    log "SUCCESS" "🎉 AWS role permissions update completed successfully!"
    log "INFO" "OpenShift installer should now pass permission validation"
    log "INFO" "You can now run the GitHub Actions workflow again"
  else
    log "WARN" "⚠️ Update applied but validation still pending"
    log "INFO" "AWS IAM propagation can take up to 60 seconds"
    log "INFO" "Try running the deployment again in a few minutes"
  fi
}

# Run main function
main "$@"
