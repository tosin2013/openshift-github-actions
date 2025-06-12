#!/bin/bash

# Master Setup Script for AWS OpenShift Integration with Vault
# Author: Tosin Akinosho, Sophia AI Assistant
# Implements Phase 1 of AWS OpenShift Integration with comprehensive scoring

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
SETUP_LOG_FILE="/tmp/aws-vault-integration-setup.log"
VAULT_ROOT_TOKEN_FILE="/tmp/vault-root-token"

# Colors for enhanced output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
print_banner() {
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "    AWS OpenShift Integration with Vault - Phase 1 Setup"
  echo "=================================================================="
  echo -e "${NC}"
  echo "This script will configure your Vault cluster for AWS OpenShift"
  echo "deployments with dynamic credential management."
  echo ""
  echo "Target: 95% success rate (matching existing Vault HA)"
  echo "Features: 30-minute TTL, Zero long-lived credentials, Full audit"
  echo ""
}

# Check prerequisites
check_prerequisites() {
  log "INFO" "Checking prerequisites..."
  local score=0
  
  # Check if we're logged into OpenShift
  if oc whoami >/dev/null 2>&1; then
    log "INFO" "✅ OpenShift login verified"
    score=$((score + 20))
  else
    log "ERROR" "❌ Not logged into OpenShift. Please run: oc login"
    return 1
  fi
  
  # Check if Vault namespace exists and pods are running
  if oc get namespace "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    log "INFO" "✅ Vault namespace exists: $VAULT_NAMESPACE"
    score=$((score + 20))
  else
    log "ERROR" "❌ Vault namespace not found: $VAULT_NAMESPACE"
    return 1
  fi
  
  # Check Vault pods
  local vault_pods
  vault_pods=$(oc get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l)
  if [[ $vault_pods -ge 1 ]]; then
    log "INFO" "✅ Vault pods found: $vault_pods"
    score=$((score + 20))
  else
    log "ERROR" "❌ No Vault pods found in namespace $VAULT_NAMESPACE"
    return 1
  fi
  
  # Check required tools
  local tools=("jq" "aws")
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      log "INFO" "✅ Tool available: $tool"
      score=$((score + 10))
    else
      log "WARN" "⚠️  Tool not found: $tool (will install if needed)"
    fi
  done
  
  update_phase1_score "foundation" $score
  log "INFO" "Prerequisites check score: $score/80"
  
  return 0
}

# Get Vault root token
get_vault_root_token() {
  log "INFO" "Checking for Vault root token..."
  
  # Check if token file exists
  if [[ -f "$VAULT_ROOT_TOKEN_FILE" ]]; then
    VAULT_ROOT_TOKEN=$(cat "$VAULT_ROOT_TOKEN_FILE")
    log "INFO" "✅ Using existing root token from file"
    return 0
  fi
  
  # Try to get from Kubernetes secret
  if oc get secret vault-init-credentials -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    VAULT_ROOT_TOKEN=$(oc get secret vault-init-credentials -n "$VAULT_NAMESPACE" -o jsonpath='{.data.root_token}' | base64 -d)
    echo "$VAULT_ROOT_TOKEN" > "$VAULT_ROOT_TOKEN_FILE"
    chmod 600 "$VAULT_ROOT_TOKEN_FILE"
    log "INFO" "✅ Retrieved root token from Kubernetes secret"
    return 0
  fi
  
  # Prompt user for token
  echo -e "${YELLOW}"
  echo "Vault root token is required for configuration."
  echo "Please provide the root token for your Vault cluster:"
  echo -e "${NC}"
  read -s -p "Vault Root Token: " VAULT_ROOT_TOKEN
  echo ""
  
  if [[ -z "$VAULT_ROOT_TOKEN" ]]; then
    log "ERROR" "Root token is required"
    return 1
  fi
  
  # Save token for future use
  echo "$VAULT_ROOT_TOKEN" > "$VAULT_ROOT_TOKEN_FILE"
  chmod 600 "$VAULT_ROOT_TOKEN_FILE"
  log "INFO" "✅ Root token saved securely"
  
  return 0
}

# Get AWS credentials
get_aws_credentials() {
  log "INFO" "Collecting AWS credentials for secrets engine..."
  
  echo -e "${YELLOW}"
  echo "AWS credentials are required to configure the secrets engine."
  echo "These will be stored securely in Vault and used to generate"
  echo "dynamic credentials with 30-minute TTL."
  echo ""
  echo "Required:"
  echo "1. AWS Access Key ID (with IAM permissions)"
  echo "2. AWS Secret Access Key"
  echo "3. AWS Region (optional, defaults to us-east-1)"
  echo -e "${NC}"
  
  # Get AWS Access Key ID
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
  fi
  
  # Get AWS Secret Access Key
  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
  fi
  
  # Get AWS Region
  if [[ -z "${AWS_REGION:-}" ]]; then
    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
  fi
  
  # Export for use by other scripts
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
  
  log "INFO" "✅ AWS credentials collected"
  return 0
}

# Test Vault connectivity and authentication
test_vault_connectivity() {
  log "INFO" "Testing Vault connectivity and authentication..."
  
  # Test basic connectivity
  if vault_exec "vault status" "Vault connectivity test"; then
    log "INFO" "✅ Vault connectivity successful"
  else
    log "ERROR" "❌ Vault connectivity failed"
    return 1
  fi
  
  # Test authentication
  if vault_exec "VAULT_TOKEN=$VAULT_ROOT_TOKEN vault token lookup" "Root token authentication"; then
    log "INFO" "✅ Vault authentication successful"
  else
    log "ERROR" "❌ Vault authentication failed"
    return 1
  fi
  
  return 0
}

# Run AWS secrets engine configuration
configure_aws_secrets() {
  log "INFO" "Configuring AWS secrets engine..."
  
  # Export root token for the configuration script
  export VAULT_ROOT_TOKEN
  
  # Run the AWS secrets engine configuration
  if "${SCRIPT_DIR}/configure-aws-secrets-engine.sh"; then
    log "INFO" "✅ AWS secrets engine configuration completed"
    return 0
  else
    log "ERROR" "❌ AWS secrets engine configuration failed"
    return 1
  fi
}

# Generate comprehensive report
generate_setup_report() {
  local overall_score
  overall_score=$(calculate_phase1_score)
  
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "           AWS OpenShift Integration Setup Report"
  echo "=================================================================="
  echo -e "${NC}"
  
  display_phase1_score_report
  
  echo ""
  echo "Next Steps:"
  if [[ $overall_score -ge 80 ]]; then
    echo -e "${GREEN}✅ Setup successful! You can now proceed with:${NC}"
    echo "1. Configure GitHub Actions JWT authentication"
    echo "2. Test dynamic credential generation"
    echo "3. Update GitHub Actions workflows"
  else
    echo -e "${RED}❌ Setup needs attention. Please review the errors above.${NC}"
    echo "1. Check Vault cluster health"
    echo "2. Verify AWS credentials"
    echo "3. Review configuration logs"
  fi
  
  echo ""
  echo "Log file: $SETUP_LOG_FILE"
  echo "Documentation: docs/vault/aws-integration-setup.md"
}

# Main setup function
main() {
  print_banner
  
  # Redirect output to log file
  exec > >(tee -a "$SETUP_LOG_FILE")
  exec 2>&1
  
  log "INFO" "Starting AWS OpenShift Integration setup..."
  log "INFO" "Log file: $SETUP_LOG_FILE"
  
  # Run setup steps
  if ! check_prerequisites; then
    log "ERROR" "Prerequisites check failed"
    exit 1
  fi
  
  if ! get_vault_root_token; then
    log "ERROR" "Failed to get Vault root token"
    exit 1
  fi
  
  if ! get_aws_credentials; then
    log "ERROR" "Failed to get AWS credentials"
    exit 1
  fi
  
  if ! test_vault_connectivity; then
    log "ERROR" "Vault connectivity test failed"
    exit 1
  fi
  
  if configure_aws_secrets; then
    # Update AWS secrets engine score based on successful configuration
    update_phase1_score "aws_secrets_engine" 90
    log "INFO" "✅ AWS secrets engine configuration completed successfully"
  else
    log "ERROR" "AWS secrets engine configuration failed"
    update_phase1_score "aws_secrets_engine" 30
    exit 1
  fi
  
  generate_setup_report
  
  log "INFO" "Setup completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
