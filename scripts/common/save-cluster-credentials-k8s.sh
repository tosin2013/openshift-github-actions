#!/bin/bash

# Save cluster credentials to HashiCorp Vault (Kubernetes version)
# This version works with Vault running in Kubernetes pods
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
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault-test-pragmatic}"
VAULT_POD="${VAULT_POD:-vault-0}"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Save OpenShift cluster credentials to HashiCorp Vault (Kubernetes version).

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

# Check if oc command is available
if ! command_exists oc; then
  log "ERROR" "OpenShift CLI (oc) is not installed or not in PATH"
  exit 1
fi

# Check if we can access the Vault pod
if ! oc get pod "$VAULT_POD" -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
  log "ERROR" "Cannot access Vault pod: $VAULT_POD in namespace: $VAULT_NAMESPACE"
  exit 1
fi

# Get Vault root token
get_vault_token() {
  # Try to get token from vault-keys.env
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
      echo "$VAULT_ROOT_TOKEN"
      return 0
    elif [[ -n "${ROOT_TOKEN:-}" ]]; then
      echo "$ROOT_TOKEN"
      return 0
    fi
  fi
  
  log "ERROR" "Could not find Vault root token in vault-keys.env"
  exit 1
}

# Execute vault command in Kubernetes pod
vault_exec() {
  local vault_token=$(get_vault_token)
  local vault_command="$*"
  
  oc exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$vault_token'
    export VAULT_ADDR=https://localhost:8200
    export VAULT_SKIP_VERIFY=true
    $vault_command
  "
}

# Validate installation directory
if [ ! -d "$INSTALLATION_DIR" ]; then
  log "ERROR" "Installation directory not found: $INSTALLATION_DIR"
  exit 1
fi

# Check required files
if [ ! -f "$INSTALLATION_DIR/auth/kubeconfig" ]; then
  log "ERROR" "Kubeconfig file not found: $INSTALLATION_DIR/auth/kubeconfig"
  exit 1
fi

if [ ! -f "$INSTALLATION_DIR/auth/kubeadmin-password" ]; then
  log "ERROR" "Kubeadmin password file not found: $INSTALLATION_DIR/auth/kubeadmin-password"
  exit 1
fi

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
    local kubeconfig_data=$(cat "$kubeconfig_path" | base64 -w 0)
    
    vault_exec vault kv put "$vault_path" \
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
    
    vault_exec vault kv put "$vault_path" \
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
  local metadata=$(cat /tmp/cluster-metadata.json | base64 -w 0)
  
  vault_exec vault kv put "$vault_path" \
    metadata="$metadata" \
    provider="$PROVIDER" \
    region="$REGION" \
    environment="$ENVIRONMENT" \
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  log "INFO" "Cluster metadata saved to Vault: $vault_path"
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
  
  # Save credentials and metadata
  save_kubeconfig
  save_kubeadmin_password
  save_cluster_metadata
  
  # Cleanup temporary files
  rm -f /tmp/cluster-metadata.json
  
  log "INFO" "Cluster credentials saved successfully to Vault"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## ✅ Cluster Credentials Saved"
    add_to_step_summary "Successfully saved cluster credentials to Vault"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Environment**: $ENVIRONMENT"
  fi
  
  return 0
}

# Run main function
main "$@"
