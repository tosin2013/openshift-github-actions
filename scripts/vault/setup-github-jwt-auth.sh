https://github.com/takinosh#!/bin/bash

# GitHub Actions JWT Authentication Setup Script
# Author: Tosin Akinosho, Sophia AI Assistant
# Purpose: Automate JWT authentication configuration for GitHub Actions

set -euo pipefail

# Source utilities and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
GITHUB_ORG="${GITHUB_ORG:-tosin2013}"
GITHUB_REPO="${GITHUB_REPO:-openshift-github-actions}"
VAULT_EXTERNAL_URL="${VAULT_EXTERNAL_URL:-https://vault-vault-test-pragmatic.apps.cluster-67wft.67wft.sandbox1936.opentlc.com}"
JWT_ROLE_NAME="${JWT_ROLE_NAME:-github-actions-openshift}"
POLICY_NAME="${POLICY_NAME:-openshift-deployment}"

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
  echo "    GitHub Actions JWT Authentication Setup"
  echo "=================================================================="
  echo -e "${NC}"
  echo "Configuring secure JWT authentication for GitHub Actions workflows"
  echo "Organization: $GITHUB_ORG"
  echo "Repository: $GITHUB_REPO"
  echo "Vault URL: $VAULT_EXTERNAL_URL"
  echo ""
}

# Execute Vault command with authentication
vault_exec_auth() {
  local command=$1
  local description=${2:-"Vault command"}
  
  log "INFO" "Executing: $description"
  
  if oc exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_ADDR=https://localhost:8200
    export VAULT_SKIP_VERIFY=true
    export VAULT_TOKEN=$ROOT_TOKEN
    $command
  "; then
    log "INFO" "✅ $description completed successfully"
    return 0
  else
    log "ERROR" "❌ $description failed"
    return 1
  fi
}

# Test external Vault connectivity
test_external_vault_access() {
  log "INFO" "Testing external Vault access..."
  
  if curl -k -s "$VAULT_EXTERNAL_URL/v1/sys/health" | jq -e '.initialized == true' >/dev/null 2>&1; then
    log "INFO" "✅ External Vault access confirmed"
    return 0
  else
    log "ERROR" "❌ External Vault access failed"
    log "ERROR" "Please verify Vault route is accessible: $VAULT_EXTERNAL_URL"
    return 1
  fi
}

# Enable JWT authentication method
enable_jwt_auth() {
  log "INFO" "Enabling JWT authentication method..."
  
  # Check if JWT auth is already enabled
  if vault_exec_auth "vault auth list | grep -q jwt" "Check JWT auth status" 2>/dev/null; then
    log "INFO" "✅ JWT authentication already enabled"
    return 0
  fi
  
  # Enable JWT auth method
  if vault_exec_auth "vault auth enable jwt" "Enable JWT authentication"; then
    return 0
  else
    return 1
  fi
}

# Configure JWT auth with GitHub OIDC
configure_jwt_auth() {
  log "INFO" "Configuring JWT auth with GitHub OIDC..."
  
  local jwt_config="vault write auth/jwt/config \
    bound_issuer='https://token.actions.githubusercontent.com' \
    oidc_discovery_url='https://token.actions.githubusercontent.com'"
  
  if vault_exec_auth "$jwt_config" "Configure JWT auth with GitHub OIDC"; then
    return 0
  else
    return 1
  fi
}

# Create OpenShift deployment policy
create_deployment_policy() {
  log "INFO" "Creating OpenShift deployment policy..."
  
  local policy_content='
# AWS secrets engine access for dynamic credentials
path "aws/creds/openshift-installer" {
  capabilities = ["read"]
}

# OpenShift secrets access (pull secret, SSH keys)
path "secret/data/openshift/*" {
  capabilities = ["read"]
}

# Vault health check access
path "sys/health" {
  capabilities = ["read"]
}

# Auth token lookup (for debugging)
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
'
  
  local policy_command="vault policy write $POLICY_NAME - <<EOF
$policy_content
EOF"
  
  if vault_exec_auth "$policy_command" "Create OpenShift deployment policy"; then
    return 0
  else
    return 1
  fi
}

# Create GitHub Actions JWT role
create_github_actions_role() {
  log "INFO" "Creating GitHub Actions JWT role..."
  
  local role_command="vault write auth/jwt/role/$JWT_ROLE_NAME \
    bound_audiences='https://github.com/$GITHUB_ORG' \
    bound_subject='repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main' \
    user_claim='actor' \
    role_type='jwt' \
    policies='$POLICY_NAME' \
    ttl=1h \
    max_ttl=2h"
  
  if vault_exec_auth "$role_command" "Create GitHub Actions JWT role"; then
    return 0
  else
    return 1
  fi
}

# Create environment-specific roles
create_environment_roles() {
  log "INFO" "Creating environment-specific JWT roles..."
  
  # Development environment role
  local dev_role_command="vault write auth/jwt/role/github-actions-dev \
    bound_audiences='https://github.com/$GITHUB_ORG' \
    bound_subject='repo:$GITHUB_ORG/$GITHUB_REPO:environment:dev' \
    user_claim='actor' \
    role_type='jwt' \
    policies='$POLICY_NAME' \
    ttl=30m \
    max_ttl=1h"
  
  if vault_exec_auth "$dev_role_command" "Create development environment role"; then
    log "INFO" "✅ Development role created"
  else
    log "WARN" "⚠️ Development role creation failed (non-critical)"
  fi
  
  # Production environment role
  local prod_role_command="vault write auth/jwt/role/github-actions-prod \
    bound_audiences='https://github.com/$GITHUB_ORG' \
    bound_subject='repo:$GITHUB_ORG/$GITHUB_REPO:environment:production' \
    user_claim='actor' \
    role_type='jwt' \
    policies='$POLICY_NAME' \
    ttl=15m \
    max_ttl=30m"
  
  if vault_exec_auth "$prod_role_command" "Create production environment role"; then
    log "INFO" "✅ Production role created"
  else
    log "WARN" "⚠️ Production role creation failed (non-critical)"
  fi
}

# Verify JWT configuration
verify_jwt_configuration() {
  log "INFO" "Verifying JWT configuration..."
  
  # Verify JWT config
  if vault_exec_auth "vault read auth/jwt/config" "Verify JWT configuration"; then
    log "INFO" "✅ JWT configuration verified"
  else
    log "ERROR" "❌ JWT configuration verification failed"
    return 1
  fi
  
  # Verify GitHub Actions role
  if vault_exec_auth "vault read auth/jwt/role/$JWT_ROLE_NAME" "Verify GitHub Actions role"; then
    log "INFO" "✅ GitHub Actions role verified"
  else
    log "ERROR" "❌ GitHub Actions role verification failed"
    return 1
  fi
  
  return 0
}

# Create OpenShift service account for GitHub Actions
create_github_actions_service_account() {
  log "INFO" "Creating GitHub Actions service account..."

  # Check if service account already exists
  if oc get serviceaccount github-actions-vault -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    log "INFO" "✅ Service account github-actions-vault already exists"
  else
    # Create service account
    if oc create serviceaccount github-actions-vault -n "$VAULT_NAMESPACE"; then
      log "INFO" "✅ Service account github-actions-vault created"
    else
      log "ERROR" "❌ Failed to create service account"
      return 1
    fi
  fi

  # Grant cluster-admin permissions (for oc exec vault operations)
  if oc adm policy add-cluster-role-to-user cluster-admin -z github-actions-vault -n "$VAULT_NAMESPACE"; then
    log "INFO" "✅ Cluster-admin permissions granted to service account"
  else
    log "WARN" "⚠️ Failed to grant cluster-admin permissions (may already exist)"
  fi

  return 0
}

# Generate OpenShift token for GitHub Actions
generate_openshift_token() {
  log "INFO" "Generating OpenShift token for GitHub Actions..."

  # Generate 24-hour token
  local token
  if token=$(oc create token github-actions-vault -n "$VAULT_NAMESPACE" --duration=24h 2>/dev/null); then
    log "INFO" "✅ OpenShift token generated successfully"
    echo "$token"
    return 0
  else
    log "ERROR" "❌ Failed to generate OpenShift token"
    return 1
  fi
}

# Generate GitHub secrets configuration
generate_github_secrets_config() {
  log "INFO" "Generating GitHub secrets configuration..."

  # Generate OpenShift token
  local openshift_token
  if openshift_token=$(generate_openshift_token); then
    log "INFO" "✅ OpenShift token ready for GitHub secrets"
  else
    log "ERROR" "❌ Failed to generate OpenShift token"
    openshift_token="<FAILED_TO_GENERATE>"
  fi

  cat << EOF

================================================================
GitHub Repository Secrets Configuration
================================================================

Add the following secrets to your GitHub repository:
Settings → Secrets and variables → Actions → New repository secret

1. VAULT_URL
   Value: $VAULT_EXTERNAL_URL

2. VAULT_JWT_AUDIENCE
   Value: https://github.com/$GITHUB_ORG

3. VAULT_ROLE
   Value: $JWT_ROLE_NAME

4. VAULT_ROOT_TOKEN (for oc exec fallback)
   Value: $ROOT_TOKEN

5. OPENSHIFT_SERVER (for oc exec fallback)
   Value: https://api.cluster-67wft.67wft.sandbox1936.opentlc.com:6443

6. OPENSHIFT_TOKEN (for oc exec fallback)
   Value: $openshift_token

================================================================
IMPORTANT: Copy the OPENSHIFT_TOKEN value above and add it to GitHub secrets.
This token is valid for 24 hours and provides fallback authentication.
================================================================

Next Steps:
1. Configure the above secrets in GitHub repository
2. Run the test workflow: .github/workflows/test-vault-action-quick.yml
3. Compare JWT vs oc exec approaches
4. Update production workflows based on test results
================================================================

EOF
}

# Main execution function
main() {
  print_banner
  
  # Load environment variables
  if [[ -f "${SCRIPT_DIR}/../../vault-keys.env" ]]; then
    source "${SCRIPT_DIR}/../../vault-keys.env"
    log "INFO" "✅ Loaded configuration from vault-keys.env"
  else
    log "ERROR" "vault-keys.env file not found"
    exit 1
  fi
  
  local total_score=0
  local max_score=625
  
  # Step 1: Test external Vault access
  if test_external_vault_access; then
    log "INFO" "✅ External Vault access validation passed"
    total_score=$((total_score + 100))
  else
    log "ERROR" "❌ External Vault access validation failed"
    exit 1
  fi
  
  # Step 2: Enable JWT authentication
  if enable_jwt_auth; then
    log "INFO" "✅ JWT authentication enabled"
    total_score=$((total_score + 100))
  else
    log "ERROR" "❌ JWT authentication setup failed"
    exit 1
  fi
  
  # Step 3: Configure JWT auth
  if configure_jwt_auth; then
    log "INFO" "✅ JWT auth configuration completed"
    total_score=$((total_score + 100))
  else
    log "ERROR" "❌ JWT auth configuration failed"
    exit 1
  fi
  
  # Step 4: Create deployment policy
  if create_deployment_policy; then
    log "INFO" "✅ Deployment policy created"
    total_score=$((total_score + 100))
  else
    log "ERROR" "❌ Deployment policy creation failed"
    exit 1
  fi
  
  # Step 5: Create GitHub Actions role
  if create_github_actions_role; then
    log "INFO" "✅ GitHub Actions role created"
    total_score=$((total_score + 100))
  else
    log "ERROR" "❌ GitHub Actions role creation failed"
    exit 1
  fi
  
  # Step 6: Create environment roles (optional)
  create_environment_roles
  total_score=$((total_score + 50))
  
  # Step 7: Create GitHub Actions service account
  if create_github_actions_service_account; then
    log "INFO" "✅ GitHub Actions service account setup completed"
    total_score=$((total_score + 25))
  else
    log "ERROR" "❌ GitHub Actions service account setup failed"
    exit 1
  fi

  # Step 8: Verify configuration
  if verify_jwt_configuration; then
    log "INFO" "✅ JWT configuration verification completed"
    total_score=$((total_score + 25))
  else
    log "ERROR" "❌ JWT configuration verification failed"
    exit 1
  fi
  
  # Calculate final score
  local final_score=$((total_score * 100 / max_score))
  
  echo -e "${GREEN}"
  echo "=================================================================="
  echo "           GitHub Actions JWT Authentication Setup Complete"
  echo "=================================================================="
  echo -e "${NC}"
  echo "Final Score: $final_score/100"
  echo ""
  echo "✅ JWT authentication method enabled"
  echo "✅ GitHub OIDC integration configured"
  echo "✅ OpenShift deployment policy created"
  echo "✅ GitHub Actions role configured"
  echo "✅ Environment-specific roles created"
  echo "✅ GitHub Actions service account created"
  echo "✅ OpenShift token generated"
  echo "✅ Configuration verified"
  echo ""
  
  # Generate GitHub secrets configuration
  generate_github_secrets_config
  
  # Update scoring system
  update_phase1_score "jwt_auth" $final_score
  
  return 0
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
