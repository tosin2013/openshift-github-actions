# Getting Started with OpenShift 4.18 Multi-Cloud Automation

This guide will help you get started with automated OpenShift 4.18 deployments across AWS, Azure, and Google Cloud Platform using GitHub Actions and HashiCorp Vault.

## Prerequisites

Before you begin, ensure you have the following:

### Required Accounts and Access
- GitHub account with Actions enabled
- HashiCorp Vault instance (HCP Vault or self-hosted)
- Cloud provider accounts with appropriate permissions:
  - AWS account with IAM permissions for OpenShift installation
  - Azure subscription with service principal for OpenShift installation
  - GCP project with service account for OpenShift installation
- Red Hat account with OpenShift pull secret
- Domain name with DNS management capabilities

### Required Tools (for local development)
- `git` - Version control
- `oc` - OpenShift CLI
- `openshift-install` - OpenShift installer
- `vault` - HashiCorp Vault CLI
- Cloud provider CLIs:
  - `aws` - AWS CLI
  - `az` - Azure CLI
  - `gcloud` - Google Cloud CLI

## Quick Start

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-org/openshift-github-actions.git
cd openshift-github-actions
```

### Step 2: Set Up HashiCorp Vault

1. **Configure Vault Authentication**
   
   Follow the [Vault Setup Guide](common/vault-setup.md) to:
   - Set up JWT authentication for GitHub Actions
   - Configure dynamic secrets for cloud providers
   - Store OpenShift pull secret and SSH keys

2. **Store Required Secrets**

   ```bash
   # Store OpenShift pull secret
   vault kv put secret/openshift/pull-secret pullSecret='{"auths":{"cloud.openshift.com":...}}'
   
   # Store SSH keys for each environment
   vault kv put secret/openshift/ssh-keys/dev \
     private_key="$(cat ~/.ssh/id_rsa)" \
     public_key="$(cat ~/.ssh/id_rsa.pub)"
   ```

### Step 3: Configure Cloud Provider Credentials

#### AWS
```bash
# Configure AWS dynamic credentials
vault auth -method=aws
vault write aws/config/root \
    access_key=YOUR_ACCESS_KEY \
    secret_key=YOUR_SECRET_KEY \
    region=us-east-1

vault write aws/roles/openshift-installer \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:*",
        "route53:*",
        "s3:*",
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

#### Azure
```bash
# Configure Azure dynamic credentials
vault write azure/config \
    subscription_id=YOUR_SUBSCRIPTION_ID \
    tenant_id=YOUR_TENANT_ID \
    client_id=YOUR_CLIENT_ID \
    client_secret=YOUR_CLIENT_SECRET

vault write azure/roles/openshift-installer \
    azure_roles=-<<EOF
[
  {
    "role_name": "Contributor",
    "scope": "/subscriptions/YOUR_SUBSCRIPTION_ID"
  }
]
EOF
```

#### GCP
```bash
# Configure GCP service account key
vault write gcp/config \
    credentials=@path/to/service-account-key.json

vault write gcp/roleset/openshift-installer \
    project="your-project-id" \
    secret_type="service_account_key" \
    bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/your-project-id" {
  roles = [
    "roles/compute.admin",
    "roles/dns.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/storage.admin"
  ]
}
EOF
```

### Step 4: Configure GitHub Repository

1. **Set Repository Secrets**

   In your GitHub repository, go to Settings > Secrets and variables > Actions, and add:

   ```
   VAULT_URL=https://your-vault-instance.com:8200
   VAULT_JWT_AUDIENCE=https://github.com/your-org
   VAULT_ROLE=github-actions-role
   ```

2. **Configure Branch Protection**

   Set up branch protection rules for the main branch to require:
   - Pull request reviews
   - Status checks to pass
   - Branches to be up to date

### Step 5: Deploy Your First Cluster

1. **Navigate to GitHub Actions**
   
   Go to your repository's Actions tab.

2. **Select a Deployment Workflow**
   
   Choose one of:
   - "Deploy OpenShift on AWS"
   - "Deploy OpenShift on Azure"
   - "Deploy OpenShift on GCP"

3. **Provide Required Parameters**
   
   Fill in the workflow inputs:
   - Cluster name (e.g., `dev-cluster-001`)
   - Region (e.g., `us-east-1` for AWS)
   - Node count (e.g., `3`)
   - Instance/VM/Machine type
   - Base domain (e.g., `example.com`)
   - Environment (`dev`, `staging`, or `production`)

4. **Run the Workflow**
   
   Click "Run workflow" to start the deployment.

5. **Monitor Progress**
   
   Watch the workflow execution in real-time. The deployment typically takes 30-45 minutes.

## What Happens During Deployment

1. **Validation**: Input parameters are validated
2. **Authentication**: Credentials are retrieved from Vault
3. **Configuration**: Install-config.yaml is generated
4. **Installation**: OpenShift installer provisions infrastructure and installs the cluster
5. **Configuration**: Post-installation cluster configuration
6. **Validation**: Cluster health and functionality checks
7. **Storage**: Cluster credentials are stored in Vault

## Accessing Your Cluster

After successful deployment:

1. **Download kubeconfig**
   
   The kubeconfig file is available as a workflow artifact.

2. **Access via CLI**
   
   ```bash
   export KUBECONFIG=path/to/downloaded/kubeconfig
   oc get nodes
   oc get clusterversion
   ```

3. **Access Web Console**
   
   ```bash
   oc whoami --show-console
   ```

## Next Steps

- [Configure cluster monitoring](common/monitoring-setup.md)
- [Set up GitOps with ArgoCD](common/gitops-setup.md)
- [Configure backup and disaster recovery](common/backup-setup.md)
- [Set up multi-cluster management](common/multicluster-setup.md)

## Troubleshooting

If you encounter issues:

1. Check the [troubleshooting guide](common/troubleshooting.md)
2. Review workflow logs in GitHub Actions
3. Check Vault audit logs for authentication issues
4. Verify cloud provider permissions and quotas

## Support

For additional support:
- Review the comprehensive documentation in the `docs/` directory
- Check existing GitHub issues
- Create a new issue with detailed information about your problem

---

**Next**: [Prerequisites](prerequisites.md) | [Vault Setup](common/vault-setup.md)
