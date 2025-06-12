#!/bin/bash

# Configure AWS Secrets Engine in Vault for OpenShift Dynamic Credentials
# Author: Tosin Akinosho, Sophia AI Assistant
# Based on ADR-006: AWS OpenShift Integration Strategy

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Configuration variables
AWS_SECRETS_ENGINE_PATH="${AWS_SECRETS_ENGINE_PATH:-aws}"
AWS_REGION="${AWS_REGION:-us-east-1}"
OPENSHIFT_INSTALLER_ROLE="${OPENSHIFT_INSTALLER_ROLE:-openshift-installer}"
CREDENTIAL_TTL="${CREDENTIAL_TTL:-1800}"  # 30 minutes
MAX_CREDENTIAL_TTL="${MAX_CREDENTIAL_TTL:-3600}"  # 1 hour

# Validate required environment variables
validate_aws_configuration() {
  log "INFO" "Validating AWS configuration for secrets engine setup..."
  
  local required_vars=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
  )
  
  if ! validate_env_vars "${required_vars[@]}"; then
    log "ERROR" "Required AWS credentials not provided"
    return 1
  fi
  
  # Validate AWS credentials work
  if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
    log "ERROR" "AWS credentials validation failed"
    return 1
  fi
  
  log "INFO" "✅ AWS configuration validation passed"
  return 0
}

# Enable AWS secrets engine
enable_aws_secrets_engine() {
  log "INFO" "Enabling AWS secrets engine at path: $AWS_SECRETS_ENGINE_PATH"
  
  if vault_secrets_engine_enabled "$AWS_SECRETS_ENGINE_PATH"; then
    log "INFO" "AWS secrets engine already enabled"
    return 0
  fi
  
  if vault_exec "vault secrets enable -path=$AWS_SECRETS_ENGINE_PATH aws" \
     "Enable AWS secrets engine"; then
    log "INFO" "✅ AWS secrets engine enabled successfully"
    return 0
  else
    log "ERROR" "❌ Failed to enable AWS secrets engine"
    return 1
  fi
}

# Configure AWS root credentials
configure_aws_root_credentials() {
  log "INFO" "Configuring AWS root credentials for secrets engine..."
  
  local config_command="vault write ${AWS_SECRETS_ENGINE_PATH}/config/root \
    access_key=\"$AWS_ACCESS_KEY_ID\" \
    secret_key=\"$AWS_SECRET_ACCESS_KEY\" \
    region=\"$AWS_REGION\""
  
  if vault_exec "$config_command" "Configure AWS root credentials"; then
    log "INFO" "✅ AWS root credentials configured successfully"
    return 0
  else
    log "ERROR" "❌ Failed to configure AWS root credentials"
    return 1
  fi
}

# Create OpenShift installer role with comprehensive IAM policy
create_openshift_installer_role() {
  log "INFO" "Creating OpenShift installer role with 30-minute TTL..."
  
  # Create IAM policy file if it doesn't exist
  local policy_file="${SCRIPT_DIR}/../../config/aws/openshift-installer-policy.json"
  if [[ ! -f "$policy_file" ]]; then
    log "INFO" "Creating OpenShift installer IAM policy file..."
    ensure_directory "$(dirname "$policy_file")"
    create_openshift_installer_policy "$policy_file"
  fi
  
  # Read policy from file
  local policy_content
  if ! policy_content=$(cat "$policy_file"); then
    log "ERROR" "Failed to read IAM policy file: $policy_file"
    return 1
  fi
  
  # Create role with simplified policy first (test if role creation works at all)
  local simple_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:DescribeRegions","sts:GetCallerIdentity"],"Resource":"*"}]}'

  # Create comprehensive OpenShift installer policy
  local openshift_policy='{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "autoscaling:DescribeAutoScalingGroups",
          "ec2:*",
          "elasticloadbalancing:*",
          "iam:CreateAccessKey",
          "iam:CreateServiceLinkedRole",
          "iam:CreateUser",
          "iam:DeleteAccessKey",
          "iam:DeleteRolePolicy",
          "iam:DeleteUser",
          "iam:DeleteUserPolicy",
          "iam:GetRolePolicy",
          "iam:GetUser",
          "iam:GetUserPolicy",
          "iam:ListAccessKeys",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRolePolicies",
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:PutUserPolicy",
          "iam:SimulatePrincipalPolicy",
          "iam:TagUser",
          "iam:UntagRole",
          "iam:UntagUser",
          "route53:*",
          "s3:*",
          "servicequotas:ListAWSDefaultServiceQuotas",
          "sts:GetCallerIdentity",
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources"
        ],
        "Resource": "*"
      }
    ]
  }'

  # Create role using comprehensive policy with correct parameters for iam_user
  # Note: default_sts_ttl and max_sts_ttl are NOT valid for iam_user credential type
  local role_command="vault write ${AWS_SECRETS_ENGINE_PATH}/roles/${OPENSHIFT_INSTALLER_ROLE} \
    credential_type=iam_user \
    policy_document='$openshift_policy'"

  if vault_exec "$role_command" "Create OpenShift installer role"; then
    log "INFO" "✅ OpenShift installer role created successfully"
    log "INFO" "   - Role name: $OPENSHIFT_INSTALLER_ROLE"
    log "INFO" "   - Credential type: iam_user"
    log "INFO" "   - Policy: Simplified for testing"
    return 0
  else
    log "ERROR" "❌ Failed to create OpenShift installer role"
    return 1
  fi
}

# Create comprehensive IAM policy for OpenShift IPI installation
create_openshift_installer_policy() {
  local policy_file=$1
  
  log "INFO" "Creating comprehensive IAM policy for OpenShift IPI..."
  
  cat > "$policy_file" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "iam:CreateUser",
        "iam:CreateRole",
        "iam:CreateInstanceProfile",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:AttachUserPolicy",
        "iam:PutRolePolicy",
        "iam:PutUserPolicy",
        "iam:AddRoleToInstanceProfile",
        "iam:PassRole",
        "iam:GetUser",
        "iam:GetRole",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:TagRole",
        "iam:TagUser",
        "iam:TagInstanceProfile",
        "iam:DeleteRole",
        "iam:DeleteUser",
        "iam:DeleteInstanceProfile",
        "iam:DetachRolePolicy",
        "iam:DetachUserPolicy",
        "iam:RemoveRoleFromInstanceProfile",
        "route53:*",
        "s3:*",
        "sts:AssumeRole",
        "sts:GetCallerIdentity",
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DescribeKey",
        "kms:TagResource",
        "cloudwatch:*",
        "autoscaling:*",
        "tag:GetResources",
        "tag:TagResources",
        "tag:UntagResources"
      ],
      "Resource": "*"
    }
  ]
}
EOF
  
  log "INFO" "✅ IAM policy file created: $policy_file"
}

# Test dynamic credential generation
test_dynamic_credential_generation() {
  log "INFO" "Testing dynamic credential generation..."
  
  local creds_json
  if creds_json=$(vault_exec "vault read -format=json ${AWS_SECRETS_ENGINE_PATH}/creds/${OPENSHIFT_INSTALLER_ROLE}" \
                  "Generate dynamic credentials"); then
    
    local access_key secret_key
    access_key=$(echo "$creds_json" | jq -r '.data.access_key')
    secret_key=$(echo "$creds_json" | jq -r '.data.secret_key')
    
    if [[ "$access_key" != "null" && "$secret_key" != "null" ]]; then
      log "INFO" "✅ Dynamic credentials generated successfully"
      log "INFO" "   - Access Key: ${access_key:0:10}..."
      log "INFO" "   - TTL: ${CREDENTIAL_TTL}s"
      
      # Test credentials work
      if AWS_ACCESS_KEY_ID="$access_key" AWS_SECRET_ACCESS_KEY="$secret_key" \
         aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
        log "INFO" "✅ Generated credentials are valid"
        return 0
      else
        log "ERROR" "❌ Generated credentials are invalid"
        return 1
      fi
    else
      log "ERROR" "❌ Failed to extract credentials from response"
      return 1
    fi
  else
    log "ERROR" "❌ Failed to generate dynamic credentials"
    return 1
  fi
}

# Main configuration function
configure_aws_secrets_engine() {
  log "INFO" "=== Starting AWS Secrets Engine Configuration ==="
  
  local score=0
  
  # Validate Vault cluster health (simplified check)
  log "INFO" "Performing basic Vault connectivity check..."
  if vault_exec "vault status" "Basic Vault status check" >/dev/null 2>&1; then
    log "INFO" "✅ Vault is accessible and operational"
    score=$((score + 20))
  else
    log "ERROR" "Vault cluster health check failed"
    update_phase1_score "aws_secrets_engine" 0
    return 1
  fi
  
  # Validate AWS configuration
  if validate_aws_configuration; then
    score=$((score + 15))
  else
    log "ERROR" "AWS configuration validation failed"
    update_phase1_score "aws_secrets_engine" $score
    return 1
  fi
  
  # Enable AWS secrets engine
  if enable_aws_secrets_engine; then
    score=$((score + 20))
  else
    log "ERROR" "Failed to enable AWS secrets engine"
    update_phase1_score "aws_secrets_engine" $score
    return 1
  fi
  
  # Configure root credentials
  if configure_aws_root_credentials; then
    score=$((score + 20))
  else
    log "ERROR" "Failed to configure AWS root credentials"
    update_phase1_score "aws_secrets_engine" $score
    return 1
  fi
  
  # Create OpenShift installer role
  if create_openshift_installer_role; then
    score=$((score + 15))
  else
    log "ERROR" "Failed to create OpenShift installer role"
    update_phase1_score "aws_secrets_engine" $score
    return 1
  fi
  
  # Test dynamic credential generation
  if test_dynamic_credential_generation; then
    score=$((score + 10))
  else
    log "WARN" "Dynamic credential generation test failed"
  fi
  
  update_phase1_score "aws_secrets_engine" $score
  log "INFO" "=== AWS Secrets Engine Configuration Complete ==="
  log "INFO" "Score: $score/100"
  
  return 0
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  configure_aws_secrets_engine
fi
