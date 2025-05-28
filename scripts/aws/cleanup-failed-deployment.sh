#!/bin/bash

# Cleanup failed OpenShift deployment on AWS
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

# Default values
CLUSTER_NAME=""
REGION=""
FORCE_CLEANUP=false

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Cleanup failed OpenShift deployment resources on AWS.

OPTIONS:
  --cluster-name NAME         Cluster name
  --region REGION             AWS region
  --force                     Force cleanup without confirmation
  --help                      Show this help message

EXAMPLES:
  # Cleanup failed deployment
  $0 --cluster-name my-cluster --region us-east-1

  # Force cleanup without confirmation
  $0 --cluster-name my-cluster --region us-east-1 --force

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --force)
      FORCE_CLEANUP=true
      shift
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
if [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Check if AWS CLI is available
if ! command_exists aws; then
  log "ERROR" "AWS CLI is not installed or not in PATH"
  exit 1
fi

# Validate AWS credentials
validate_aws_credentials() {
  log "INFO" "Validating AWS credentials"
  
  if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    log "ERROR" "AWS credentials are not valid or not configured"
    exit 1
  fi
  
  log "INFO" "AWS credentials validated"
}

# Confirm cleanup
confirm_cleanup() {
  if [ "$FORCE_CLEANUP" = "true" ]; then
    log "INFO" "Force cleanup enabled, skipping confirmation"
    return 0
  fi
  
  log "WARN" "This will attempt to cleanup AWS resources for cluster: $CLUSTER_NAME"
  log "WARN" "This action cannot be undone!"
  
  read -p "Are you sure you want to proceed? (yes/no): " confirmation
  
  if [ "$confirmation" != "yes" ]; then
    log "INFO" "Cleanup cancelled by user"
    exit 0
  fi
}

# Find and cleanup EC2 instances
cleanup_ec2_instances() {
  log "INFO" "Cleaning up EC2 instances"
  
  local instances=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
              "Name=instance-state-name,Values=running,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$instances" ]; then
    log "INFO" "Found EC2 instances to terminate: $instances"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $instances
    log "INFO" "EC2 instances termination initiated"
  else
    log "INFO" "No EC2 instances found for cleanup"
  fi
}

# Cleanup security groups
cleanup_security_groups() {
  log "INFO" "Cleaning up security groups"
  
  local security_groups=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
    --query 'SecurityGroups[].GroupId' \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$security_groups" ]; then
    log "INFO" "Found security groups to delete: $security_groups"
    
    # Wait for instances to terminate before deleting security groups
    log "INFO" "Waiting for instances to terminate before deleting security groups"
    sleep 60
    
    for sg in $security_groups; do
      log "DEBUG" "Attempting to delete security group: $sg"
      if aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null; then
        log "INFO" "Deleted security group: $sg"
      else
        log "WARN" "Failed to delete security group: $sg (may have dependencies)"
      fi
    done
  else
    log "INFO" "No security groups found for cleanup"
  fi
}

# Cleanup load balancers
cleanup_load_balancers() {
  log "INFO" "Cleaning up load balancers"
  
  # Classic Load Balancers
  local classic_lbs=$(aws elb describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerName" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$classic_lbs" ]; then
    log "INFO" "Found classic load balancers to delete: $classic_lbs"
    for lb in $classic_lbs; do
      aws elb delete-load-balancer --region "$REGION" --load-balancer-name "$lb"
      log "INFO" "Deleted classic load balancer: $lb"
    done
  fi
  
  # Application/Network Load Balancers
  local alb_nlbs=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$alb_nlbs" ]; then
    log "INFO" "Found ALB/NLB load balancers to delete: $alb_nlbs"
    for lb in $alb_nlbs; do
      aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb"
      log "INFO" "Deleted ALB/NLB load balancer: $lb"
    done
  fi
  
  if [ -z "$classic_lbs" ] && [ -z "$alb_nlbs" ]; then
    log "INFO" "No load balancers found for cleanup"
  fi
}

# Cleanup S3 buckets
cleanup_s3_buckets() {
  log "INFO" "Cleaning up S3 buckets"
  
  local buckets=$(aws s3api list-buckets \
    --query "Buckets[?contains(Name, '$CLUSTER_NAME')].Name" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$buckets" ]; then
    log "INFO" "Found S3 buckets to delete: $buckets"
    for bucket in $buckets; do
      log "DEBUG" "Emptying S3 bucket: $bucket"
      aws s3 rm "s3://$bucket" --recursive --region "$REGION" 2>/dev/null || true
      
      log "DEBUG" "Deleting S3 bucket: $bucket"
      if aws s3api delete-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
        log "INFO" "Deleted S3 bucket: $bucket"
      else
        log "WARN" "Failed to delete S3 bucket: $bucket"
      fi
    done
  else
    log "INFO" "No S3 buckets found for cleanup"
  fi
}

# Cleanup Route53 records
cleanup_route53_records() {
  log "INFO" "Cleaning up Route53 records"
  
  # This is a simplified cleanup - in production you'd want more sophisticated logic
  local hosted_zones=$(aws route53 list-hosted-zones \
    --query "HostedZones[?contains(Name, '$CLUSTER_NAME')].Id" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$hosted_zones" ]; then
    log "WARN" "Found hosted zones that may need manual cleanup: $hosted_zones"
    log "WARN" "Please review and cleanup Route53 records manually if needed"
  else
    log "INFO" "No Route53 hosted zones found for cleanup"
  fi
}

# Cleanup IAM roles and policies
cleanup_iam_resources() {
  log "INFO" "Cleaning up IAM resources"
  
  # Find IAM roles
  local roles=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, '$CLUSTER_NAME')].RoleName" \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$roles" ]; then
    log "INFO" "Found IAM roles to delete: $roles"
    for role in $roles; do
      # Detach policies first
      local attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$role" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || echo "")
      
      for policy in $attached_policies; do
        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
        log "DEBUG" "Detached policy $policy from role $role"
      done
      
      # Delete instance profiles
      local instance_profiles=$(aws iam list-instance-profiles-for-role \
        --role-name "$role" \
        --query 'InstanceProfiles[].InstanceProfileName' \
        --output text 2>/dev/null || echo "")
      
      for profile in $instance_profiles; do
        aws iam remove-role-from-instance-profile --instance-profile-name "$profile" --role-name "$role"
        aws iam delete-instance-profile --instance-profile-name "$profile"
        log "DEBUG" "Deleted instance profile: $profile"
      done
      
      # Delete role
      aws iam delete-role --role-name "$role"
      log "INFO" "Deleted IAM role: $role"
    done
  else
    log "INFO" "No IAM roles found for cleanup"
  fi
}

# Cleanup VPC resources
cleanup_vpc_resources() {
  log "INFO" "Cleaning up VPC resources"
  
  # Find VPC by cluster tag
  local vpc_id=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null || echo "None")
  
  if [ "$vpc_id" != "None" ] && [ -n "$vpc_id" ]; then
    log "INFO" "Found VPC to cleanup: $vpc_id"
    
    # Cleanup NAT gateways
    local nat_gateways=$(aws ec2 describe-nat-gateways \
      --region "$REGION" \
      --filter "Name=vpc-id,Values=$vpc_id" \
      --query 'NatGateways[].NatGatewayId' \
      --output text 2>/dev/null || echo "")
    
    for nat in $nat_gateways; do
      aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$nat"
      log "INFO" "Deleted NAT gateway: $nat"
    done
    
    # Cleanup internet gateways
    local igws=$(aws ec2 describe-internet-gateways \
      --region "$REGION" \
      --filters "Name=attachment.vpc-id,Values=$vpc_id" \
      --query 'InternetGateways[].InternetGatewayId' \
      --output text 2>/dev/null || echo "")
    
    for igw in $igws; do
      aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$igw" --vpc-id "$vpc_id"
      aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$igw"
      log "INFO" "Deleted internet gateway: $igw"
    done
    
    # Wait a bit for resources to be cleaned up
    sleep 30
    
    # Try to delete VPC
    if aws ec2 delete-vpc --region "$REGION" --vpc-id "$vpc_id" 2>/dev/null; then
      log "INFO" "Deleted VPC: $vpc_id"
    else
      log "WARN" "Failed to delete VPC: $vpc_id (may have remaining dependencies)"
    fi
  else
    log "INFO" "No VPC found for cleanup"
  fi
}

# Main cleanup function
main() {
  log "INFO" "Starting AWS cleanup for cluster: $CLUSTER_NAME"
  log "INFO" "Region: $REGION"
  
  # Validate prerequisites
  validate_aws_credentials
  
  # Confirm cleanup
  confirm_cleanup
  
  # Run cleanup steps
  cleanup_ec2_instances
  cleanup_load_balancers
  cleanup_s3_buckets
  cleanup_route53_records
  cleanup_iam_resources
  cleanup_security_groups
  cleanup_vpc_resources
  
  log "INFO" "AWS cleanup completed"
  log "WARN" "Please verify that all resources have been cleaned up properly"
  log "WARN" "Some resources may require manual cleanup due to dependencies"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## AWS Cleanup Completed"
    add_to_step_summary "⚠️ Cleanup attempted for failed deployment"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary ""
    add_to_step_summary "**Cleanup Actions:**"
    add_to_step_summary "- EC2 instances terminated"
    add_to_step_summary "- Load balancers deleted"
    add_to_step_summary "- S3 buckets cleaned up"
    add_to_step_summary "- IAM resources removed"
    add_to_step_summary "- Security groups deleted"
    add_to_step_summary "- VPC resources cleaned up"
    add_to_step_summary ""
    add_to_step_summary "⚠️ **Please verify all resources were cleaned up properly**"
  fi
  
  return 0
}

# Run main function
main "$@"
