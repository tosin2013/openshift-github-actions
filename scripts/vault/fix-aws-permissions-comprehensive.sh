#!/bin/bash

# Comprehensive AWS Permissions Fix for Vault Dynamic Credential Generation
# Author: Sophia AI Assistant
# Purpose: Fix AWS IAM permissions to enable proper Vault dynamic credential generation

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration
AWS_POLICY_NAME="VaultDynamicCredentialManagement"
AWS_USER_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
print_banner() {
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "    Comprehensive AWS Permissions Fix for Vault Integration"
  echo "=================================================================="
  echo -e "${NC}"
  echo "This script will fix AWS IAM permissions to enable proper"
  echo "Vault dynamic credential generation for OpenShift deployments."
  echo ""
}

# Check AWS CLI and get current user
check_aws_setup() {
  log "INFO" "Checking AWS CLI configuration..."
  
  if ! command -v aws &> /dev/null; then
    log "ERROR" "AWS CLI is not installed. Please install it first."
    exit 1
  fi
  
  if ! aws sts get-caller-identity &> /dev/null; then
    log "ERROR" "AWS CLI is not configured or credentials are invalid."
    log "INFO" "Please run 'aws configure' or set AWS environment variables."
    exit 1
  fi
  
  local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
  AWS_USER_NAME=$(echo "$user_arn" | cut -d'/' -f2)
  
  log "INFO" "✅ AWS CLI configured for user: $AWS_USER_NAME"
  log "INFO" "✅ User ARN: $user_arn"
}

# Create comprehensive IAM policy for Vault
create_vault_iam_policy() {
  log "INFO" "Creating comprehensive IAM policy for Vault dynamic credential management..."
  
  local policy_file="/tmp/vault-comprehensive-iam-policy.json"
  
  cat > "$policy_file" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "iam:AttachUserPolicy",
        "iam:PutUserPolicy",
        "iam:DeleteUser",
        "iam:DeleteAccessKey",
        "iam:DetachUserPolicy",
        "iam:DeleteUserPolicy",
        "iam:GetUser",
        "iam:GetUserPolicy",
        "iam:ListAccessKeys",
        "iam:ListAttachedUserPolicies",
        "iam:ListUserPolicies",
        "iam:TagUser",
        "iam:UntagUser",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF
  
  local account_id=$(aws sts get-caller-identity --query Account --output text)
  local policy_arn="arn:aws:iam::${account_id}:policy/${AWS_POLICY_NAME}"
  
  # Check if policy already exists
  if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
    log "INFO" "Policy $AWS_POLICY_NAME already exists. Updating..."
    
    # Create a new version of the policy
    local version_id=$(aws iam create-policy-version \
      --policy-arn "$policy_arn" \
      --policy-document file://"$policy_file" \
      --set-as-default \
      --query 'PolicyVersion.VersionId' --output text)
    
    log "INFO" "✅ Policy updated to version: $version_id"
  else
    log "INFO" "Creating new policy: $AWS_POLICY_NAME"
    
    aws iam create-policy \
      --policy-name "$AWS_POLICY_NAME" \
      --policy-document file://"$policy_file" \
      --description "Comprehensive IAM policy for Vault dynamic credential management"
    
    log "INFO" "✅ Policy created successfully"
  fi
  
  echo "$policy_arn"
}

# Attach policy to current user
attach_policy_to_user() {
  local policy_arn=$1
  
  log "INFO" "Attaching policy to user: $AWS_USER_NAME"
  
  # Check if policy is already attached
  if aws iam list-attached-user-policies --user-name "$AWS_USER_NAME" \
     --query "AttachedPolicies[?PolicyArn=='$policy_arn'].PolicyName" \
     --output text | grep -q "$AWS_POLICY_NAME"; then
    log "INFO" "Policy already attached to user"
  else
    aws iam attach-user-policy \
      --user-name "$AWS_USER_NAME" \
      --policy-arn "$policy_arn"
    
    log "INFO" "✅ Policy attached to user successfully"
  fi
}

# Test IAM permissions
test_iam_permissions() {
  log "INFO" "Testing IAM permissions for dynamic user creation..."
  
  local test_user_name="vault-test-user-$(date +%s)"
  
  # Test user creation
  if aws iam create-user --user-name "$test_user_name" &> /dev/null; then
    log "INFO" "✅ User creation test passed"
    
    # Test access key creation
    if aws iam create-access-key --user-name "$test_user_name" &> /dev/null; then
      log "INFO" "✅ Access key creation test passed"
      
      # Cleanup test resources
      aws iam list-access-keys --user-name "$test_user_name" \
        --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
        xargs -I {} aws iam delete-access-key --user-name "$test_user_name" --access-key-id {}
      
      aws iam delete-user --user-name "$test_user_name"
      log "INFO" "✅ Test cleanup completed"
      return 0
    else
      log "ERROR" "❌ Access key creation test failed"
      aws iam delete-user --user-name "$test_user_name" &> /dev/null || true
      return 1
    fi
  else
    log "ERROR" "❌ User creation test failed"
    return 1
  fi
}

# Update Vault AWS role configuration
update_vault_aws_role() {
  log "INFO" "Updating Vault AWS role configuration..."
  
  # Source vault keys
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
  else
    log "ERROR" "vault-keys.env file not found"
    return 1
  fi
  
  # Create simplified policy for testing
  local simplified_policy='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:DeleteUser",
          "iam:DeleteAccessKey",
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:TagUser",
          "sts:GetCallerIdentity"
        ],
        "Resource": "*"
      }
    ]
  }'
  
  # Update Vault role with simplified policy
  local vault_command="
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

# Update the role with simplified policy
vault write aws/roles/openshift-installer \\
  credential_type=iam_user \\
  policy_document='$simplified_policy'
"
  
  if oc exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "$vault_command"; then
    log "INFO" "✅ Vault AWS role updated successfully"
    return 0
  else
    log "ERROR" "❌ Failed to update Vault AWS role"
    return 1
  fi
}

# Test Vault credential generation
test_vault_credential_generation() {
  log "INFO" "Testing Vault credential generation..."
  
  # Source vault keys
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
  else
    log "ERROR" "vault-keys.env file not found"
    return 1
  fi
  
  local vault_command="
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$ROOT_TOKEN

# Generate test credentials
vault read aws/creds/openshift-installer -format=json
"
  
  local creds_output
  if creds_output=$(oc exec vault-0 -n "$VAULT_NAMESPACE" -- sh -c "$vault_command" 2>/dev/null); then
    local access_key secret_key
    access_key=$(echo "$creds_output" | jq -r '.data.access_key')
    secret_key=$(echo "$creds_output" | jq -r '.data.secret_key')
    
    if [[ -n "$access_key" && "$access_key" != "null" ]]; then
      log "INFO" "✅ Vault credential generation successful"
      log "INFO" "   Access Key: ${access_key:0:10}..."
      
      # Test the generated credentials
      if AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key" \
         aws sts get-caller-identity &> /dev/null; then
        log "INFO" "✅ Generated credentials are valid"
        return 0
      else
        log "WARN" "⚠️  Generated credentials are invalid (may need propagation time)"
        return 1
      fi
    else
      log "ERROR" "❌ Failed to extract credentials from Vault response"
      return 1
    fi
  else
    log "ERROR" "❌ Failed to generate credentials from Vault"
    return 1
  fi
}

# Main function
main() {
  print_banner
  
  # Check AWS setup
  check_aws_setup
  
  # Create IAM policy
  local policy_arn
  policy_arn=$(create_vault_iam_policy)
  
  # Attach policy to user
  attach_policy_to_user "$policy_arn"
  
  # Test IAM permissions
  if test_iam_permissions; then
    log "INFO" "✅ IAM permissions test passed"
  else
    log "ERROR" "❌ IAM permissions test failed"
    exit 1
  fi
  
  # Update Vault AWS role
  if update_vault_aws_role; then
    log "INFO" "✅ Vault AWS role updated"
  else
    log "ERROR" "❌ Failed to update Vault AWS role"
    exit 1
  fi
  
  # Test Vault credential generation
  if test_vault_credential_generation; then
    log "INFO" "🎉 All tests passed! Vault dynamic credential generation is working"
  else
    log "WARN" "⚠️  Vault credential generation needs attention (may work after AWS propagation)"
  fi
  
  echo ""
  log "INFO" "=== Summary ==="
  log "INFO" "✅ AWS IAM policy created/updated: $AWS_POLICY_NAME"
  log "INFO" "✅ Policy attached to user: $AWS_USER_NAME"
  log "INFO" "✅ Vault AWS role configuration updated"
  log "INFO" ""
  log "INFO" "Next steps:"
  log "INFO" "1. Wait 1-2 minutes for AWS IAM propagation"
  log "INFO" "2. Run: ./scripts/vault/setup-aws-integration.sh"
  log "INFO" "3. Test GitHub Actions workflow"
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
