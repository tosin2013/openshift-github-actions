# ADR-006: AWS OpenShift Integration Strategy

**Status:** Proposed  
**Date:** 2025-06-04  
**Authors:** Tosin Akinosho, Sophia AI Assistant  
**Reviewers:** Development Team  

> **Note:** This ADR represents our current understanding and proposed approach. Implementation details may evolve based on research findings, testing results, and new discoveries during the development process. Any significant changes will be documented through ADR updates or new ADRs as appropriate.

## Context

Building on our proven Vault HA deployment (95% success rate) and multi-cloud integration strategy (ADR-003), we need to establish a comprehensive approach for automated OpenShift 4.18 deployments on AWS using GitHub Actions with dynamic credential management.

### Current State
- ✅ **Vault HA Foundation**: Production-ready with 95% success rate (ADR-001)
- ✅ **Multi-Cloud Strategy**: Central hub model defined (ADR-003)
- ✅ **Dynamic Secrets Framework**: Zero-trust credential management (ADR-005)
- ✅ **GitHub Actions Architecture**: Workflow orchestration strategy (ADR-004)
- ⚠️ **AWS Integration Gap**: No AWS-specific deployment automation
- ⚠️ **IPI Deployment Gap**: No Installer Provisioned Infrastructure automation

### Requirements
1. **IPI Deployment**: Automated OpenShift 4.18 installation on AWS
2. **Dynamic IAM Credentials**: Just-in-time AWS credential provisioning
3. **GitHub Actions Integration**: Secure CI/CD workflow automation
4. **Infrastructure Management**: Complete AWS resource lifecycle
5. **Security Compliance**: Zero long-lived credentials, complete audit trail
6. **Operational Excellence**: Monitoring, backup, and disaster recovery

## Decision

Implement **AWS IPI Deployment with Dynamic IAM Integration** using our Vault HA cluster:

### Architecture: AWS OpenShift Deployment Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              AWS Deployment Workflow                │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │ Vault   │  │ AWS     │  │OpenShift│             │   │
│  │  │ Auth    │  │ Creds   │  │ Install │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ JWT Authentication
                              │ Dynamic IAM Credentials
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Vault HA  │      │    AWS      │      │ OpenShift   │
│   Cluster   │      │ Resources   │      │  Cluster    │
│             │      │             │      │             │
│ AWS Secrets │----->│ • VPC       │----->│ • Masters   │
│ Engine      │      │ • Subnets   │      │ • Workers   │
│             │      │ • Security  │      │ • Ingress   │
│             │      │ • IAM       │      │ • Storage   │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Core Integration Strategy

#### 1. **AWS Secrets Engine Configuration**
```hcl
# Enable AWS secrets engine in Vault
vault secrets enable -path=aws aws

# Configure root credentials (stored securely in Vault)
vault write aws/config/root \
  access_key=$AWS_ROOT_ACCESS_KEY \
  secret_key=$AWS_ROOT_SECRET_KEY \
  region=us-east-1

# Create role for OpenShift installation
vault write aws/roles/openshift-installer \
  credential_type=iam_user \
  default_sts_ttl=1800 \
  max_sts_ttl=3600 \
  policy_document=@aws-openshift-installer-policy.json
```

#### 2. **AWS IAM Policy for OpenShift IPI**
```json
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
        "route53:*",
        "s3:*",
        "sts:AssumeRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

#### 3. **GitHub Actions Workflow Integration**
```yaml
name: Deploy OpenShift on AWS
on:
  workflow_dispatch:
    inputs:
      cluster_name:
        description: 'OpenShift cluster name'
        required: true
      aws_region:
        description: 'AWS region'
        required: true
        default: 'us-east-1'
      environment:
        description: 'Environment (dev/staging/prod)'
        required: true
        default: 'dev'

jobs:
  deploy-openshift-aws:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Vault
        uses: hashicorp/vault-action@v2
        with:
          url: ${{ secrets.VAULT_URL }}
          method: jwt
          role: github-actions-${{ inputs.environment }}
          secrets: |
            aws/creds/openshift-installer access_key | AWS_ACCESS_KEY_ID ;
            aws/creds/openshift-installer secret_key | AWS_SECRET_ACCESS_KEY
      
      - name: Install OpenShift CLI
        run: |
          curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
          tar -xzf openshift-install-linux.tar.gz
          sudo mv openshift-install /usr/local/bin/
      
      - name: Generate Install Config
        run: |
          ./scripts/generate-aws-install-config.sh \
            --cluster-name ${{ inputs.cluster_name }} \
            --region ${{ inputs.aws_region }} \
            --environment ${{ inputs.environment }}
      
      - name: Deploy OpenShift Cluster
        run: |
          openshift-install create cluster --dir=cluster-config --log-level=info
      
      - name: Store Cluster Credentials in Vault
        run: |
          vault kv put openshift/clusters/aws-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            kubeconfig=@cluster-config/auth/kubeconfig \
            kubeadmin_password=@cluster-config/auth/kubeadmin-password \
            console_url="$(cat cluster-config/auth/kubeadmin-password | head -1)" \
            api_url="$(oc whoami --show-server)"
```

## Consequences

### Positive
- **Leverages Proven Infrastructure**: 95% success rate Vault HA foundation
- **Complete Automation**: End-to-end OpenShift deployment without manual intervention
- **Security First**: Dynamic IAM credentials with 30-minute TTL
- **AWS Best Practices**: IPI deployment follows AWS recommended patterns
- **Scalable**: Can deploy multiple clusters across different AWS regions
- **Audit Compliance**: Complete trail of all credential access and usage
- **Cost Effective**: Automatic resource cleanup and optimization

### Negative
- **AWS Dependency**: Requires AWS account with appropriate service limits
- **Complexity**: Multi-step workflow with multiple integration points
- **Resource Requirements**: Significant AWS resources during deployment
- **Time Investment**: Initial setup and testing requires substantial effort

### Neutral
- **Learning Curve**: Team needs AWS IPI and Vault secrets engine expertise
- **Monitoring Requirements**: Need comprehensive monitoring across AWS and OpenShift
- **Backup Strategy**: Must implement backup for both Vault and OpenShift data

## Implementation

### Phase 1: AWS Secrets Engine Setup (Week 1)
1. **Configure AWS Secrets Engine**
   ```bash
   # Enable and configure AWS secrets engine
   vault secrets enable -path=aws aws
   vault write aws/config/root access_key=$AWS_ROOT_ACCESS_KEY secret_key=$AWS_ROOT_SECRET_KEY
   
   # Create OpenShift installer role
   vault write aws/roles/openshift-installer \
     credential_type=iam_user \
     policy_document=@aws-openshift-installer-policy.json
   ```

2. **Test Dynamic Credential Generation**
   ```bash
   # Test credential generation
   vault read aws/creds/openshift-installer
   
   # Verify credentials work
   aws sts get-caller-identity
   ```

### Phase 2: GitHub Actions Workflow (Week 2)
1. **Create Workflow Templates**
   - AWS OpenShift deployment workflow
   - Environment-specific configurations
   - Error handling and rollback procedures

2. **Integration Testing**
   - Test Vault authentication from GitHub Actions
   - Validate dynamic credential provisioning
   - End-to-end deployment testing

### Phase 3: Operational Excellence (Week 3)
1. **Monitoring and Alerting**
   - AWS CloudWatch integration
   - OpenShift monitoring setup
   - Vault audit log analysis

2. **Backup and Disaster Recovery**
   - Automated backup procedures
   - Cross-region replication
   - Recovery testing

### Success Metrics
- **Deployment Success Rate**: 95% (matching Vault HA success)
- **Deployment Time**: < 45 minutes for complete cluster
- **Security Compliance**: Zero long-lived credentials in any system
- **Cost Optimization**: Automatic resource cleanup and rightsizing

## Alternatives Considered

### Static IAM Credentials
- **Rejected**: Security risk, no rotation, compliance issues
- **Issues**: Long-lived credentials, manual rotation, audit gaps

### AWS IAM Roles for Service Accounts (IRSA)
- **Rejected**: Doesn't solve GitHub Actions authentication
- **Issues**: Still need initial credentials, complex setup

### Terraform Cloud with AWS Integration
- **Rejected**: Additional vendor dependency and cost
- **Issues**: Another system to manage, integration complexity

### Manual OpenShift Installation
- **Rejected**: Not scalable, error-prone, no automation benefits
- **Issues**: Human error, inconsistent deployments, no audit trail

## References

- [OpenShift IPI on AWS Documentation](https://docs.openshift.com/container-platform/4.18/installing/installing_aws/installing-aws-default.html)
- [Vault AWS Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/aws)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [GitHub Actions with Vault](https://github.com/hashicorp/vault-action)
- **Related ADRs**: ADR-003 (Multi-Cloud Integration), ADR-005 (Dynamic Secrets), ADR-004 (GitHub Actions)
