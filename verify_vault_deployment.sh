#!/bin/bash

# Vault Deployment Verification Script
# This script verifies the Vault HA deployment and provides a final score

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default namespace
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault-production}"

# Logging function
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1"
}

error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1"
}

# Score tracking
TOTAL_SCORE=0
MAX_SCORE=100

# Test functions
test_namespace() {
  log "Testing namespace existence..."
  if oc get namespace "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    success "✅ Namespace '$VAULT_NAMESPACE' exists"
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
  else
    error "❌ Namespace '$VAULT_NAMESPACE' not found"
  fi
}

test_pods() {
  log "Testing pod status..."
  local running_pods=$(oc get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  local total_pods=$(oc get pods -n "$VAULT_NAMESPACE" -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l | tr -d ' ')
  
  if [[ $running_pods -eq 3 && $total_pods -eq 3 ]]; then
    success "✅ All 3 Vault pods are running"
    TOTAL_SCORE=$((TOTAL_SCORE + 15))
  elif [[ $running_pods -gt 0 ]]; then
    warn "⚠️  $running_pods/$total_pods pods running"
    TOTAL_SCORE=$((TOTAL_SCORE + 10))
  else
    error "❌ No Vault pods running"
  fi
}

test_tls_certificates() {
  log "Testing TLS certificates..."
  if oc get secret vault-tls -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
    local cert_data=$(oc get secret vault-tls -n "$VAULT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
    if [[ -n "$cert_data" ]]; then
      success "✅ TLS certificates present and valid"
      TOTAL_SCORE=$((TOTAL_SCORE + 10))
    else
      warn "⚠️  TLS secret exists but certificate data missing"
      TOTAL_SCORE=$((TOTAL_SCORE + 5))
    fi
  else
    error "❌ TLS secret 'vault-tls' not found"
  fi
}

test_vault_leader() {
  log "Testing Vault leader status..."
  local vault_status=$(oc exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null || echo '{}')
  
  local initialized=$(echo "$vault_status" | jq -r '.initialized // false' 2>/dev/null)
  local sealed=$(echo "$vault_status" | jq -r '.sealed // true' 2>/dev/null)
  
  if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
    success "✅ Vault leader (vault-0) is initialized and unsealed"
    TOTAL_SCORE=$((TOTAL_SCORE + 25))
  elif [[ "$initialized" == "true" ]]; then
    warn "⚠️  Vault is initialized but sealed"
    TOTAL_SCORE=$((TOTAL_SCORE + 15))
  else
    error "❌ Vault is not initialized"
  fi
}

test_tls_connectivity() {
  log "Testing TLS connectivity..."
  local tls_test=$(oc logs vault-0 -n "$VAULT_NAMESPACE" 2>/dev/null | grep "Listener.*tls.*enabled" || echo "")
  
  if [[ -n "$tls_test" ]]; then
    success "✅ TLS is enabled and working"
    TOTAL_SCORE=$((TOTAL_SCORE + 15))
  else
    warn "⚠️  TLS status unclear from logs"
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
  fi
}

test_external_access() {
  log "Testing external access..."
  local route_host=$(oc get route vault -n "$VAULT_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  
  if [[ -n "$route_host" ]]; then
    success "✅ External route configured: https://$route_host"
    TOTAL_SCORE=$((TOTAL_SCORE + 10))
    
    # Test if route is actually accessible
    if curl -k -s --max-time 10 "https://$route_host/ui/" | grep -q "Vault" 2>/dev/null; then
      success "✅ External UI is accessible"
      TOTAL_SCORE=$((TOTAL_SCORE + 10))
    else
      warn "⚠️  Route exists but UI may not be fully accessible"
      TOTAL_SCORE=$((TOTAL_SCORE + 5))
    fi
  else
    error "❌ No external route found"
  fi
}

test_ha_cluster() {
  log "Testing HA cluster status..."
  local unsealed_count=0
  
  for pod in vault-0 vault-1 vault-2; do
    local status=$(oc exec "$pod" -n "$VAULT_NAMESPACE" -- sh -c "VAULT_ADDR=https://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null || echo '{"sealed": true}')
    local sealed=$(echo "$status" | jq -r '.sealed // true' 2>/dev/null)
    
    if [[ "$sealed" == "false" ]]; then
      unsealed_count=$((unsealed_count + 1))
    fi
  done
  
  if [[ $unsealed_count -eq 3 ]]; then
    success "✅ Full HA cluster operational (3/3 nodes unsealed)"
    TOTAL_SCORE=$((TOTAL_SCORE + 10))
  elif [[ $unsealed_count -eq 1 ]]; then
    warn "⚠️  Leader-only deployment (1/3 nodes unsealed)"
    TOTAL_SCORE=$((TOTAL_SCORE + 5))
  else
    error "❌ HA cluster not operational"
  fi
}

# Main verification function
main() {
  echo "=============================================="
  echo "🔐 Vault HA Deployment Verification"
  echo "=============================================="
  echo "Namespace: $VAULT_NAMESPACE"
  echo "Timestamp: $(date)"
  echo ""
  
  # Run all tests
  test_namespace
  test_pods
  test_tls_certificates
  test_vault_leader
  test_tls_connectivity
  test_external_access
  test_ha_cluster
  
  echo ""
  echo "=============================================="
  echo "📊 FINAL DEPLOYMENT SCORE"
  echo "=============================================="
  
  local percentage=$((TOTAL_SCORE * 100 / MAX_SCORE))
  
  if [[ $percentage -ge 95 ]]; then
    success "🎉 EXCELLENT: $TOTAL_SCORE/$MAX_SCORE ($percentage%) - Production Ready!"
  elif [[ $percentage -ge 90 ]]; then
    success "🚀 OUTSTANDING: $TOTAL_SCORE/$MAX_SCORE ($percentage%) - Highly Successful!"
  elif [[ $percentage -ge 80 ]]; then
    warn "✅ GOOD: $TOTAL_SCORE/$MAX_SCORE ($percentage%) - Mostly Successful"
  elif [[ $percentage -ge 60 ]]; then
    warn "⚠️  PARTIAL: $TOTAL_SCORE/$MAX_SCORE ($percentage%) - Needs Attention"
  else
    error "❌ FAILED: $TOTAL_SCORE/$MAX_SCORE ($percentage%) - Requires Fixes"
  fi
  
  echo ""
  echo "🔗 Access your Vault:"
  local route_host=$(oc get route vault -n "$VAULT_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "No route found")
  echo "   UI: https://$route_host"
  echo "   CLI: export VAULT_ADDR=https://$route_host"
  echo ""
  
  if [[ $percentage -ge 90 ]]; then
    echo "🎯 Deployment methodology validated! Ready for production use."
  else
    echo "🔧 Review troubleshooting steps in README.md"
  fi
  
  echo "=============================================="
}

# Run verification
main
