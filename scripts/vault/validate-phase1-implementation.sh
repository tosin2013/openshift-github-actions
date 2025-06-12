#!/bin/bash

# Phase 1 AWS OpenShift Integration Validation Script
# Author: Sophia AI Assistant
# Purpose: Comprehensive validation of Phase 1 implementation

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
VALIDATION_LOG="/tmp/phase1-validation-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation scores
VAULT_SCORE=0
AWS_SCORE=0
JWT_SCORE=0
WORKFLOW_SCORE=0
OVERALL_SCORE=0

# Print banner
print_banner() {
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "    Phase 1 AWS OpenShift Integration Validation"
  echo "=================================================================="
  echo -e "${NC}"
  echo "Comprehensive validation of Vault HA, AWS integration, and"
  echo "GitHub Actions workflow readiness for OpenShift deployments."
  echo ""
  echo "Log file: $VALIDATION_LOG"
  echo ""
}

# Validate Vault HA cluster
validate_vault_cluster() {
  log "INFO" "=== Validating Vault HA Cluster ==="
  local score=0
  
  # Check Vault pods
  local vault_pods
  if vault_pods=$(oc get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault --no-headers 2>/dev/null); then
    local pod_count=$(echo "$vault_pods" | wc -l)
    local running_count=$(echo "$vault_pods" | grep -c "Running" || true)
    
    if [[ $running_count -eq 3 ]]; then
      log "INFO" "✅ All 3 Vault pods are running"
      score=$((score + 25))
    elif [[ $running_count -gt 0 ]]; then
      log "WARN" "⚠️  Only $running_count/3 Vault pods are running"
      score=$((score + 15))
    else
      log "ERROR" "❌ No Vault pods are running"
    fi
  else
    log "ERROR" "❌ Cannot get Vault pod status"
  fi
  
  # Check Vault status
  if vault_status_check >/dev/null 2>&1; then
    log "INFO" "✅ Vault is accessible and operational"
    score=$((score + 25))
  else
    log "ERROR" "❌ Vault is not accessible"
  fi
  
  # Check TLS configuration
  local vault_route
  if vault_route=$(oc get route vault -n "$VAULT_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null); then
    if [[ -n "$vault_route" ]]; then
      log "INFO" "✅ Vault external route configured: $vault_route"
      score=$((score + 25))
    fi
  else
    log "WARN" "⚠️  Vault external route not found"
  fi
  
  # Check HA cluster formation
  if vault_exec "vault status" "Vault HA status check" | grep -q "HA Mode.*active"; then
    log "INFO" "✅ Vault HA cluster is active"
    score=$((score + 25))
  else
    log "WARN" "⚠️  Vault HA cluster status unclear"
  fi
  
  VAULT_SCORE=$score
  log "INFO" "Vault cluster validation score: $score/100"
}

# Validate AWS secrets engine
validate_aws_integration() {
  log "INFO" "=== Validating AWS Secrets Engine Integration ==="
  local score=0
  
  # Check if AWS secrets engine is enabled
  if vault_secrets_engine_enabled "aws"; then
    log "INFO" "✅ AWS secrets engine is enabled"
    score=$((score + 25))
  else
    log "ERROR" "❌ AWS secrets engine is not enabled"
  fi
  
  # Check AWS root configuration
  if vault_exec "vault read aws/config/root" "AWS root config check" >/dev/null 2>&1; then
    log "INFO" "✅ AWS root credentials are configured"
    score=$((score + 25))
  else
    log "ERROR" "❌ AWS root credentials are not configured"
  fi
  
  # Check OpenShift installer role
  if vault_exec "vault read aws/roles/openshift-installer" "OpenShift installer role check" >/dev/null 2>&1; then
    log "INFO" "✅ OpenShift installer role exists"
    score=$((score + 25))
  else
    log "ERROR" "❌ OpenShift installer role does not exist"
  fi
  
  # Test dynamic credential generation
  local creds_output
  if creds_output=$(vault_exec "vault read aws/creds/openshift-installer -format=json" "Dynamic credential test" 2>/dev/null); then
    local access_key
    access_key=$(echo "$creds_output" | jq -r '.data.access_key' 2>/dev/null)
    
    if [[ -n "$access_key" && "$access_key" != "null" ]]; then
      log "INFO" "✅ Dynamic credential generation successful"
      score=$((score + 25))
    else
      log "ERROR" "❌ Dynamic credential generation failed"
    fi
  else
    log "ERROR" "❌ Cannot generate dynamic credentials"
  fi
  
  AWS_SCORE=$score
  log "INFO" "AWS integration validation score: $score/100"
}

# Validate JWT authentication setup
validate_jwt_auth() {
  log "INFO" "=== Validating JWT Authentication Setup ==="
  local score=0
  
  # Check if JWT auth method is enabled
  if vault_auth_method_enabled "jwt"; then
    log "INFO" "✅ JWT auth method is enabled"
    score=$((score + 30))
  else
    log "WARN" "⚠️  JWT auth method is not enabled (will be configured in next phase)"
  fi
  
  # Check for GitHub OIDC configuration
  if vault_exec "vault read auth/jwt/config" "JWT config check" >/dev/null 2>&1; then
    log "INFO" "✅ JWT authentication is configured"
    score=$((score + 35))
  else
    log "WARN" "⚠️  JWT authentication not configured (next phase)"
  fi
  
  # Check for GitHub Actions role
  if vault_exec "vault read auth/jwt/role/github-actions-openshift" "GitHub Actions role check" >/dev/null 2>&1; then
    log "INFO" "✅ GitHub Actions JWT role exists"
    score=$((score + 35))
  else
    log "WARN" "⚠️  GitHub Actions JWT role not configured (next phase)"
  fi
  
  JWT_SCORE=$score
  log "INFO" "JWT authentication validation score: $score/100"
}

# Validate GitHub Actions workflow readiness
validate_workflow_readiness() {
  log "INFO" "=== Validating GitHub Actions Workflow Readiness ==="
  local score=0
  
  # Check for workflow files
  if [[ -f ".github/workflows/deploy-openshift-multicloud.yml" ]]; then
    log "INFO" "✅ Multi-cloud deployment workflow exists"
    score=$((score + 25))
  else
    log "ERROR" "❌ Multi-cloud deployment workflow missing"
  fi
  
  # Check for OpenShift secrets in Vault
  if vault_exec "vault kv get secret/openshift/pull-secret" "Pull secret check" >/dev/null 2>&1; then
    log "INFO" "✅ OpenShift pull secret configured in Vault"
    score=$((score + 25))
  else
    log "WARN" "⚠️  OpenShift pull secret not configured in Vault"
  fi
  
  # Check for SSH keys
  if vault_exec "vault kv get secret/openshift/ssh-keys/dev" "SSH keys check" >/dev/null 2>&1; then
    log "INFO" "✅ SSH keys configured in Vault"
    score=$((score + 25))
  else
    log "WARN" "⚠️  SSH keys not configured in Vault"
  fi
  
  # Check for base domain configuration
  if vault_exec "vault kv get secret/openshift/config/dev" "Base domain check" >/dev/null 2>&1; then
    log "INFO" "✅ Base domain configured in Vault"
    score=$((score + 25))
  else
    log "WARN" "⚠️  Base domain not configured in Vault"
  fi
  
  WORKFLOW_SCORE=$score
  log "INFO" "Workflow readiness validation score: $score/100"
}

# Calculate overall score and provide recommendations
generate_validation_report() {
  OVERALL_SCORE=$(( (VAULT_SCORE + AWS_SCORE + JWT_SCORE + WORKFLOW_SCORE) / 4 ))
  
  echo ""
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "           Phase 1 Validation Report"
  echo "=================================================================="
  echo -e "${NC}"
  
  echo "Component Scores:"
  echo "  Vault HA Cluster:      $VAULT_SCORE/100"
  echo "  AWS Integration:       $AWS_SCORE/100"
  echo "  JWT Authentication:    $JWT_SCORE/100"
  echo "  Workflow Readiness:    $WORKFLOW_SCORE/100"
  echo ""
  echo "Overall Score:           $OVERALL_SCORE/100"
  echo ""
  
  if [[ $OVERALL_SCORE -ge 90 ]]; then
    echo -e "${GREEN}🎉 EXCELLENT: Phase 1 implementation is ready for production!${NC}"
    echo "✅ All critical components are operational"
    echo "✅ Ready to proceed with GitHub Actions deployment"
  elif [[ $OVERALL_SCORE -ge 75 ]]; then
    echo -e "${GREEN}✅ GOOD: Phase 1 implementation is solid with minor gaps${NC}"
    echo "🔧 Consider completing JWT authentication setup"
    echo "✅ Core functionality is ready for testing"
  elif [[ $OVERALL_SCORE -ge 60 ]]; then
    echo -e "${YELLOW}⚠️  NEEDS IMPROVEMENT: Phase 1 requires attention${NC}"
    echo "🔧 Fix AWS integration issues"
    echo "🔧 Complete Vault secrets configuration"
  else
    echo -e "${RED}❌ CRITICAL: Phase 1 implementation needs significant work${NC}"
    echo "🚨 Address Vault cluster issues"
    echo "🚨 Fix AWS secrets engine configuration"
  fi
  
  echo ""
  echo "Next Steps:"
  if [[ $AWS_SCORE -lt 75 ]]; then
    echo "1. Run: ./scripts/vault/fix-aws-permissions-comprehensive.sh"
  fi
  if [[ $WORKFLOW_SCORE -lt 75 ]]; then
    echo "2. Run: ./scripts/vault/add-openshift-secrets.sh"
  fi
  if [[ $JWT_SCORE -lt 50 ]]; then
    echo "3. Run: ./scripts/vault/setup-github-jwt-auth.sh"
  fi
  if [[ $OVERALL_SCORE -ge 75 ]]; then
    echo "4. Test GitHub Actions workflow: Deploy OpenShift Multi-Cloud"
  fi
  
  echo ""
  echo "Documentation: docs/vault/aws-integration-setup.md"
  echo "Log file: $VALIDATION_LOG"
}

# Main function
main() {
  print_banner
  
  # Redirect output to log file
  exec > >(tee -a "$VALIDATION_LOG")
  exec 2>&1
  
  log "INFO" "Starting Phase 1 validation..."
  log "INFO" "Vault namespace: $VAULT_NAMESPACE"
  
  # Run validations
  validate_vault_cluster
  validate_aws_integration
  validate_jwt_auth
  validate_workflow_readiness
  
  # Generate report
  generate_validation_report
  
  log "INFO" "Phase 1 validation completed!"
  
  # Return appropriate exit code
  if [[ $OVERALL_SCORE -ge 75 ]]; then
    exit 0
  else
    exit 1
  fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
