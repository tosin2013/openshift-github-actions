#!/bin/bash

# Fix AWS IAM Permissions for Vault Dynamic User Creation
# This script creates the necessary IAM policy for your root AWS user

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if AWS CLI is available and configured
check_aws_cli() {
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
  local user_name=$(echo "$user_arn" | cut -d'/' -f2)
  
  log "SUCCESS" "AWS CLI configured for user: $user_name"
  echo "$user_name"
}

# Create the IAM policy for Vault dynamic user creation
create_vault_iam_policy() {
  local policy_name="VaultDynamicUserCreation"
  local policy_file="/tmp/vault-iam-policy.json"
  
  log "INFO" "Creating IAM policy for Vault dynamic user creation..."
  
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
        "iam:ListAccessKeys",
        "iam:ListAttachedUserPolicies",
        "iam:ListUserPolicies",
        "iam:TagUser",
        "iam:UntagUser"
      ],
      "Resource": "*"
    }
  ]
}
EOF
  
  # Check if policy already exists
  if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" &> /dev/null; then
    log "INFO" "Policy $policy_name already exists. Updating..."
    
    # Create a new version of the policy
    local version_id=$(aws iam create-policy-version \
      --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" \
      --policy-document file://"$policy_file" \
      --set-as-default \
      --query 'PolicyVersion.VersionId' --output text)
    
    log "SUCCESS" "Policy updated to version: $version_id"
  else
    log "INFO" "Creating new policy: $policy_name"
    
    aws iam create-policy \
      --policy-name "$policy_name" \
      --policy-document file://"$policy_file" \
      --description "Allows Vault to create and manage dynamic IAM users" > /dev/null
    
    log "SUCCESS" "Policy created: $policy_name"
  fi
  
  rm -f "$policy_file"
  echo "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name"
}

# Attach policy to user
attach_policy_to_user() {
  local user_name=$1
  local policy_arn=$2
  
  log "INFO" "Attaching policy to user: $user_name"
  
  # Check if policy is already attached
  if aws iam list-attached-user-policies --user-name "$user_name" --query "AttachedPolicies[?PolicyArn=='$policy_arn']" --output text | grep -q "$policy_arn"; then
    log "INFO" "Policy already attached to user: $user_name"
  else
    aws iam attach-user-policy --user-name "$user_name" --policy-arn "$policy_arn"
    log "SUCCESS" "Policy attached to user: $user_name"
  fi
}

# Test if the user can create IAM users
test_iam_permissions() {
  local test_user="vault-test-user-$(date +%s)"
  
  log "INFO" "Testing IAM user creation permissions..."
  
  # Try to create a test user
  if aws iam create-user --user-name "$test_user" &> /dev/null; then
    log "SUCCESS" "✅ IAM user creation test passed"
    
    # Clean up test user
    aws iam delete-user --user-name "$test_user" &> /dev/null
    log "INFO" "Test user cleaned up"
    return 0
  else
    log "ERROR" "❌ IAM user creation test failed"
    log "ERROR" "The user still doesn't have permission to create IAM users"
    return 1
  fi
}

# Main function
main() {
  log "INFO" "=== AWS IAM Permissions Fix for Vault ==="
  log "INFO" "This script will add the necessary IAM permissions for Vault dynamic user creation"
  echo
  
  # Check AWS CLI
  local user_name
  user_name=$(check_aws_cli)
  
  # Create IAM policy
  local policy_arn
  policy_arn=$(create_vault_iam_policy)
  
  # Attach policy to user
  attach_policy_to_user "$user_name" "$policy_arn"
  
  # Test permissions
  if test_iam_permissions; then
    log "SUCCESS" "🎉 AWS IAM permissions fixed successfully!"
    log "INFO" "Your AWS user now has the necessary permissions for Vault dynamic user creation"
    echo
    log "INFO" "Next steps:"
    log "INFO" "1. Test Vault credential generation locally"
    log "INFO" "2. Run the GitHub Actions workflow again"
    log "INFO" "3. Verify AWS validation passes"
  else
    log "ERROR" "❌ Permission test failed. Please check your AWS account policies."
    log "INFO" "You may need to contact your AWS administrator if organizational policies are blocking IAM user creation."
    exit 1
  fi
}

# Run main function
main "$@"
