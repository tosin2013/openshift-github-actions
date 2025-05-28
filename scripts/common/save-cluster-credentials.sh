#!/bin/bash

# Save cluster credentials to HashiCorp Vault
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
REGION=""
ENVIRONMENT="dev"
INSTALLATION_DIR="installation-dir"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Save OpenShift cluster credentials to HashiCorp Vault.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --environment ENV           Environment (dev, staging, production)
  --installation-dir DIR      Installation directory (default: installation-dir)
  --help                      Show this help message

EXAMPLES:
  # Save AWS cluster credentials
  $0 --provider aws --cluster-name my-cluster --region us-east-1

  # Save with custom installation directory
  $0 --provider azure --cluster-name my-cluster --region eastus \\
     --installation-dir /path/to/install-dir

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --installation-dir)
      INSTALLATION_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      log "ERROR" "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$PROVIDER" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Check if vault command is available
if ! command_exists vault; then
  log "ERROR" "HashiCorp Vault CLI is not installed or not in PATH"
  exit 1
fi

# Validate installation directory
if [ ! -d "$INSTALLATION_DIR" ]; then
  log "ERROR" "Installation directory not found: $INSTALLATION_DIR"
  exit 1
fi

# Check required files
validate_files "$INSTALLATION_DIR/auth/kubeconfig" "$INSTALLATION_DIR/auth/kubeadmin-password"

# Extract cluster information
extract_cluster_info() {
  log "INFO" "Extracting cluster information"
  
  # Set KUBECONFIG for oc commands
  export KUBECONFIG="$INSTALLATION_DIR/auth/kubeconfig"
  
  # Extract basic cluster information
  local cluster_id=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "unknown")
  local cluster_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
  local api_url=$(oc whoami --show-server 2>/dev/null || echo "unknown")
  local console_url=$(oc whoami --show-console 2>/dev/null || echo "unknown")
  
  # Get cluster domain
  local cluster_domain=""
  if [[ "$console_url" =~ https://console-openshift-console\.apps\.(.+) ]]; then
    cluster_domain="${BASH_REMATCH[1]}"
  fi
  
  # Create cluster metadata
  cat > /tmp/cluster-metadata.json << EOF
{
  "cluster_name": "$CLUSTER_NAME",
  "cluster_id": "$cluster_id",
  "provider": "$PROVIDER",
  "region": "$REGION",
  "environment": "$ENVIRONMENT",
  "cluster_version": "$cluster_version",
  "api_url": "$api_url",
  "console_url": "$console_url",
  "cluster_domain": "$cluster_domain",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "created_by": "${GITHUB_ACTOR:-$(whoami)}"
}
EOF
  
  log "INFO" "Cluster metadata extracted"
  log "DEBUG" "Cluster ID: $cluster_id"
  log "DEBUG" "Cluster Version: $cluster_version"
  log "DEBUG" "API URL: $api_url"
  log "DEBUG" "Console URL: $console_url"
}

# Save kubeconfig to Vault
save_kubeconfig() {
  log "INFO" "Saving kubeconfig to Vault"
  
  local kubeconfig_path="$INSTALLATION_DIR/auth/kubeconfig"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/kubeconfig"
  
  if [ -f "$kubeconfig_path" ]; then
    local kubeconfig_data=$(cat "$kubeconfig_path")
    
    vault kv put "$vault_path" \
      kubeconfig="$kubeconfig_data" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log "INFO" "Kubeconfig saved to Vault: $vault_path"
  else
    log "ERROR" "Kubeconfig file not found: $kubeconfig_path"
    return 1
  fi
}

# Save kubeadmin password to Vault
save_kubeadmin_password() {
  log "INFO" "Saving kubeadmin password to Vault"
  
  local password_path="$INSTALLATION_DIR/auth/kubeadmin-password"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/kubeadmin"
  
  if [ -f "$password_path" ]; then
    local password=$(cat "$password_path")
    
    vault kv put "$vault_path" \
      password="$password" \
      username="kubeadmin" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log "INFO" "Kubeadmin password saved to Vault: $vault_path"
  else
    log "ERROR" "Kubeadmin password file not found: $password_path"
    return 1
  fi
}

# Save cluster metadata to Vault
save_cluster_metadata() {
  log "INFO" "Saving cluster metadata to Vault"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/metadata"
  local metadata=$(cat /tmp/cluster-metadata.json)
  
  vault kv put "$vault_path" \
    metadata="$metadata" \
    provider="$PROVIDER" \
    region="$REGION" \
    environment="$ENVIRONMENT" \
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  log "INFO" "Cluster metadata saved to Vault: $vault_path"
}

# Save installation logs to Vault (optional)
save_installation_logs() {
  log "INFO" "Saving installation logs to Vault"
  
  local log_path="$INSTALLATION_DIR/.openshift_install.log"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/logs"
  
  if [ -f "$log_path" ]; then
    # Only save the last 10000 lines to avoid hitting Vault size limits
    local log_data=$(tail -n 10000 "$log_path" | base64 -w 0)
    
    vault kv put "$vault_path" \
      installation_log="$log_data" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log "INFO" "Installation logs saved to Vault: $vault_path"
  else
    log "WARN" "Installation log file not found: $log_path"
  fi
}

# Save terraform state (if exists)
save_terraform_state() {
  log "INFO" "Checking for Terraform state"
  
  local tf_state_path="$INSTALLATION_DIR/terraform.tfstate"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/terraform"
  
  if [ -f "$tf_state_path" ]; then
    local tf_state=$(cat "$tf_state_path" | base64 -w 0)
    
    vault kv put "$vault_path" \
      terraform_state="$tf_state" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    log "INFO" "Terraform state saved to Vault: $vault_path"
  else
    log "DEBUG" "No Terraform state file found"
  fi
}

# Create cluster inventory entry
create_cluster_inventory() {
  log "INFO" "Creating cluster inventory entry"
  
  local vault_path="secret/openshift/inventory/$ENVIRONMENT/$PROVIDER"
  
  # Get existing inventory or create new
  local existing_inventory=""
  if vault kv get -field=clusters "$vault_path" >/dev/null 2>&1; then
    existing_inventory=$(vault kv get -field=clusters "$vault_path")
  fi
  
  # Create new inventory entry
  local cluster_entry="{\"name\":\"$CLUSTER_NAME\",\"region\":\"$REGION\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  
  # Add to existing inventory (this is simplified - in production you'd use jq)
  local new_inventory="$existing_inventory,$cluster_entry"
  if [ -z "$existing_inventory" ]; then
    new_inventory="$cluster_entry"
  fi
  
  vault kv put "$vault_path" \
    clusters="[$new_inventory]" \
    updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  log "INFO" "Cluster inventory updated: $vault_path"
}

# Verify saved credentials
verify_saved_credentials() {
  log "INFO" "Verifying saved credentials"
  
  local paths=(
    "secret/openshift/clusters/$CLUSTER_NAME/kubeconfig"
    "secret/openshift/clusters/$CLUSTER_NAME/kubeadmin"
    "secret/openshift/clusters/$CLUSTER_NAME/metadata"
  )
  
  for path in "${paths[@]}"; do
    if vault kv get "$path" >/dev/null 2>&1; then
      log "INFO" "✅ Verified: $path"
    else
      log "ERROR" "❌ Failed to verify: $path"
      return 1
    fi
  done
  
  log "INFO" "All credentials verified successfully"
  return 0
}

# Main function
main() {
  log "INFO" "Starting credential save process"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Region: $REGION"
  log "INFO" "Environment: $ENVIRONMENT"
  
  # Extract cluster information
  extract_cluster_info
  
  # Save all credentials and metadata
  save_kubeconfig
  save_kubeadmin_password
  save_cluster_metadata
  save_installation_logs
  save_terraform_state
  create_cluster_inventory
  
  # Verify everything was saved correctly
  verify_saved_credentials
  
  # Cleanup temporary files
  rm -f /tmp/cluster-metadata.json
  
  log "INFO" "Cluster credentials saved successfully to Vault"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## Cluster Credentials Saved"
    add_to_step_summary "✅ Successfully saved cluster credentials to Vault"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Environment**: $ENVIRONMENT"
    add_to_step_summary ""
    add_to_step_summary "**Saved Items:**"
    add_to_step_summary "- Kubeconfig"
    add_to_step_summary "- Kubeadmin password"
    add_to_step_summary "- Cluster metadata"
    add_to_step_summary "- Installation logs"
    add_to_step_summary "- Cluster inventory"
  fi
  
  return 0
}

# Run main function
main "$@"
