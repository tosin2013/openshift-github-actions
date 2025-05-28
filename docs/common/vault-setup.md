# HashiCorp Vault Setup for OpenShift Multi-Cloud Automation

This guide explains how to configure HashiCorp Vault for secure credential management in OpenShift multi-cloud deployments. We provide two deployment options:

1. **Self-hosted Vault on OpenShift** (Recommended): A cost-effective approach that deploys Vault directly on your OpenShift cluster using our GitHub Actions workflow
2. **HashiCorp Cloud Platform (HCP) Vault**: A managed service option with additional features but higher cost

## Overview

HashiCorp Vault provides:
- Centralized secret management
- Dynamic credential generation
- Fine-grained access control
- Comprehensive audit logging
- Integration with GitHub Actions

## Deployment Options

### Option 1: Self-hosted Vault on OpenShift (Recommended)

#### Prerequisites
- Existing OpenShift cluster with administrative access
- Storage class available for persistent volumes
- `oc` CLI and `kubectl` access to the cluster
- GitHub repository for OpenShift automation

#### Deployment Process
We provide a GitHub Actions workflow that automates the deployment of Vault on your OpenShift cluster:

1. Navigate to the Actions tab in your GitHub repository
2. Select the "Deploy HashiCorp Vault on OpenShift" workflow
3. Click "Run workflow" and provide the following information:
   - OpenShift cluster context
   - Namespace for Vault (default: `vault`)
   - Storage class for persistent volumes
   - Number of Vault replicas (default: 3)
   - Whether to enable the Vault UI (default: true)
4. The workflow will:
   - Deploy Vault using the official Helm chart
   - Initialize and unseal Vault
   - Configure authentication methods
   - Set up necessary policies
   - Create a Route for the Vault UI (if enabled)

For more details on the deployment process, see the [workflow file](/.github/workflows/deploy-vault-on-openshift.yml).

### Option 2: HashiCorp Cloud Platform (HCP) Vault

#### Prerequisites
- HashiCorp Cloud Platform (HCP) account at https://portal.cloud.hashicorp.com/
- Vault CLI installed locally
- Administrative access to HCP Vault cluster
- Cloud provider accounts with appropriate permissions
- GitHub repository for OpenShift automation

## Self-hosted Vault on OpenShift Configuration

### Manual Configuration (Post-Deployment)

If you need to manually configure your self-hosted Vault after deployment, follow these steps:

#### 1. Connect to Vault

```bash
# Set environment variables (replace with your actual values)
export VAULT_ADDR="https://vault-route-vault.apps.your-cluster.example.com"
export VAULT_TOKEN="your-root-token"
export VAULT_SKIP_VERIFY="true"  # For self-signed certificates

# Test connection
vault status
```

#### 2. Configure Cloud Provider Secret Engines

```bash
# AWS Secret Engine
vault write aws/config/root \
    access_key=YOUR_AWS_ACCESS_KEY \
    secret_key=YOUR_AWS_SECRET_KEY \
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
        "ec2:*", "route53:*", "iam:*", "elasticloadbalancing:*",
        "s3:*", "kms:*", "cloudwatch:*", "autoscaling:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Azure Secret Engine
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

# GCP Secret Engine
vault write gcp/config \
    credentials=@/path/to/your/service-account.json

vault write gcp/roleset/openshift-installer \
    project="your-gcp-project" \
    secret_type="service_account_key" \
    bindings=-<<EOF
{
  "resource": "//cloudresourcemanager.googleapis.com/projects/your-gcp-project",
  "roles": [
    "roles/compute.admin",
    "roles/iam.serviceAccountUser",
    "roles/dns.admin",
    "roles/storage.admin"
  ]
}
EOF
```

#### 3. Configure GitHub Actions Authentication

```bash
# Replace with your actual GitHub organization and repository name
GITHUB_ORG="your-github-org"
REPO_NAME="openshift-github-actions"

# Configure JWT auth for GitHub Actions
vault write auth/jwt/role/github-actions-role \
    bound_audiences="https://github.com/${GITHUB_ORG}" \
    bound_subject="repo:${GITHUB_ORG}/${REPO_NAME}:ref:refs/heads/main" \
    user_claim="actor" \
    role_type="jwt" \
    policies="openshift-deployment" \
    ttl=1h
```

### Integrating with GitHub Actions

To use your self-hosted Vault with GitHub Actions, add the following secrets to your GitHub repository:

- `VAULT_ADDR`: The URL of your Vault instance (e.g., `https://vault-route-vault.apps.your-cluster.example.com`)
- `VAULT_ROLE`: The JWT role to authenticate with (e.g., `github-actions-role`)

Then update your workflow files to authenticate with Vault:

```yaml
- name: Authenticate to Vault
  uses: hashicorp/vault-action@v2
  with:
    url: ${{ secrets.VAULT_ADDR }}
    role: ${{ secrets.VAULT_ROLE }}
    method: jwt
    jwtGithubAudience: https://github.com/your-github-org
    secrets: |
      aws/creds/openshift-installer access_key | AWS_ACCESS_KEY_ID ;
      aws/creds/openshift-installer secret_key | AWS_SECRET_ACCESS_KEY
```

### Backup and Recovery

Regularly back up your Vault data by creating snapshots:

```bash
# Create a snapshot
oc exec -n vault vault-0 -- vault operator raft snapshot save /tmp/vault-snapshot.bak

# Copy the snapshot to your local machine
oc cp -n vault vault-0:/tmp/vault-snapshot.bak ./vault-snapshot.bak
```

To restore from a snapshot:

```bash
# Copy the snapshot to the Vault pod
oc cp ./vault-snapshot.bak -n vault vault-0:/tmp/vault-snapshot.bak

# Restore from the snapshot
oc exec -n vault vault-0 -- vault operator raft snapshot restore /tmp/vault-snapshot.bak
```

## HCP Vault Setup (Alternative Option)

### 1. Create HCP Vault Cluster

1. **Navigate to HCP Portal**
   - Go to https://portal.cloud.hashicorp.com/
   - Sign in or create an account

2. **Create New Vault Cluster**
   - Click "Create" → "Vault"
   - Configure cluster settings:
     - **Cluster Name**: `openshift-vault` (or your preferred name)
     - **Cloud Provider**: Choose AWS, Azure, or GCP
     - **Region**: Select region close to your OpenShift deployments
     - **Tier**: Development (for testing) or Standard (for production)
   - Click "Create cluster"

3. **Wait for Cluster Creation**
   - Cluster creation takes 5-10 minutes
   - Note the **Public Cluster URL** when ready
   - Example: `https://openshift-vault-vault-public-vault-xxxxxxxx.hashicorp.cloud:8200`

### 2. Install Vault CLI

**macOS:**
```bash
brew install vault
```

**Linux (Ubuntu/Debian):**
```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault
```

**Windows:**
Download from https://www.vaultproject.io/downloads

### 3. Connect to HCP Vault

1. **Generate Admin Token**
   - In HCP console, go to your Vault cluster
   - Click "Generate admin token"
   - Copy the token (it's only shown once)

2. **Set Environment Variables**
   ```bash
   export VAULT_ADDR="https://your-cluster-url:8200"
   export VAULT_TOKEN="your-admin-token"
   export VAULT_NAMESPACE="admin"  # HCP Vault uses admin namespace
   ```

3. **Test Connection**
   ```bash
   vault status
   ```

### 4. Configure HCP Vault

#### Enable Secret Engines

```bash
# Enable KV v2 secret engine for static secrets
vault secrets enable -path=secret kv-v2

# Enable AWS secret engine for dynamic credentials
vault secrets enable aws

# Enable Azure secret engine for dynamic credentials
vault secrets enable azure

# Enable GCP secret engine for dynamic credentials
vault secrets enable gcp
```

#### Configure JWT Authentication for GitHub Actions

```bash
# Enable JWT auth method
vault auth enable jwt

# Configure JWT auth for GitHub Actions
vault write auth/jwt/config \
    bound_issuer="https://token.actions.githubusercontent.com" \
    oidc_discovery_url="https://token.actions.githubusercontent.com"

# Create a role for GitHub Actions
# Replace YOUR_GITHUB_ORG and YOUR_REPO_NAME with your actual values
vault write auth/jwt/role/github-actions-role \
    bound_audiences="https://github.com/YOUR_GITHUB_ORG" \
    bound_subject="repo:YOUR_GITHUB_ORG/YOUR_REPO_NAME:ref:refs/heads/main" \
    user_claim="actor" \
    role_type="jwt" \
    policies="openshift-deployment" \
    ttl=1h
```

#### Create Vault Policies

```bash
vault policy write openshift-deployment - <<EOF
# Read OpenShift secrets
path "secret/data/openshift/*" {
  capabilities = ["read"]
}

# Read AWS dynamic credentials
path "aws/creds/openshift-installer" {
  capabilities = ["read"]
}

# Read Azure dynamic credentials
path "azure/creds/openshift-installer" {
  capabilities = ["read"]
}

# Read GCP dynamic credentials
path "gcp/key/openshift-installer" {
  capabilities = ["read"]
}

# Write cluster metadata
path "secret/data/openshift/clusters/*" {
  capabilities = ["create", "update", "read"]
}
EOF
```

## Cloud Provider Configuration

### AWS Dynamic Credentials

```bash
# Configure AWS secret engine
vault write aws/config/root \
    access_key=YOUR_AWS_ACCESS_KEY \
    secret_key=YOUR_AWS_SECRET_KEY \
    region=us-east-1

# Create role for OpenShift installer
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
        "elasticloadbalancing:*",
        "tag:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Test credential generation
vault read aws/creds/openshift-installer
```

### Azure Dynamic Credentials

```bash
# Configure Azure secret engine
vault write azure/config \
    subscription_id=YOUR_SUBSCRIPTION_ID \
    tenant_id=YOUR_TENANT_ID \
    client_id=YOUR_CLIENT_ID \
    client_secret=YOUR_CLIENT_SECRET

# Create role for OpenShift installer
vault write azure/roles/openshift-installer \
    azure_roles=-<<EOF
[
  {
    "role_name": "Contributor",
    "scope": "/subscriptions/YOUR_SUBSCRIPTION_ID"
  },
  {
    "role_name": "User Access Administrator",
    "scope": "/subscriptions/YOUR_SUBSCRIPTION_ID"
  }
]
EOF

# Test credential generation
vault read azure/creds/openshift-installer
```

### GCP Service Account Keys

```bash
# Configure GCP secret engine
vault write gcp/config \
    credentials=@path/to/service-account-key.json

# Create roleset for OpenShift installer
vault write gcp/roleset/openshift-installer \
    project="your-project-id" \
    secret_type="service_account_key" \
    bindings=-<<EOF
resource "//cloudresourcemanager.googleapis.com/projects/your-project-id" {
  roles = [
    "roles/compute.admin",
    "roles/dns.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/storage.admin",
    "roles/serviceusage.serviceUsageAdmin"
  ]
}
EOF

# Test key generation
vault read gcp/key/openshift-installer
```

## GitHub Repository Configuration

After setting up Vault, you need to configure your GitHub repository with the necessary secrets:

### 1. Add Repository Secrets

In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions** and add:

```
VAULT_URL=https://your-hcp-vault-cluster-url:8200
VAULT_JWT_AUDIENCE=https://github.com/YOUR_GITHUB_ORG
VAULT_ROLE=github-actions-role
```

**Example:**
```
VAULT_URL=https://openshift-vault-vault-public-vault-abc123.hashicorp.cloud:8200
VAULT_JWT_AUDIENCE=https://github.com/mycompany
VAULT_ROLE=github-actions-role
```

### 2. Update Workflow Files

Ensure your workflow files reference the correct Vault URL and role. The workflows in this repository are already configured to use these secret names.

## Store Static Secrets

### OpenShift Pull Secret

1. **Get your pull secret from Red Hat:**
   - Go to https://console.redhat.com/openshift/install/pull-secret
   - Download or copy your pull secret

2. **Store in Vault:**
   ```bash
   # Store OpenShift pull secret (replace with your actual pull secret)
   vault kv put secret/openshift/pull-secret \
       pullSecret='{"auths":{"cloud.openshift.com":{"auth":"...","email":"..."}}}'
   ```

### SSH Keys

```bash
# Generate SSH key pair if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/openshift-key -N ""

# Store SSH keys for each environment
vault kv put secret/openshift/ssh-keys/dev \
    private_key="$(cat ~/.ssh/openshift-key)" \
    public_key="$(cat ~/.ssh/openshift-key.pub)"

vault kv put secret/openshift/ssh-keys/staging \
    private_key="$(cat ~/.ssh/openshift-key)" \
    public_key="$(cat ~/.ssh/openshift-key.pub)"

vault kv put secret/openshift/ssh-keys/production \
    private_key="$(cat ~/.ssh/openshift-key)" \
    public_key="$(cat ~/.ssh/openshift-key.pub)"
```

## Verification

### Test Authentication

```bash
# Test JWT authentication (simulate GitHub Actions)
vault write auth/jwt/login \
    role=github-actions-role \
    jwt=YOUR_GITHUB_TOKEN
```

### Test Secret Access

```bash
# Test reading secrets
vault kv get secret/openshift/pull-secret
vault kv get secret/openshift/ssh-keys/dev

# Test dynamic credentials
vault read aws/creds/openshift-installer
vault read azure/creds/openshift-installer
vault read gcp/key/openshift-installer
```

## Security Best Practices

### 1. Least Privilege Access
- Grant minimum required permissions
- Use separate roles for different environments
- Regularly review and rotate credentials

### 2. Audit Logging
```bash
# Enable audit logging
vault audit enable file file_path=/vault/logs/audit.log
```

### 3. Secret Rotation
```bash
# Set up automatic rotation for root credentials
vault write aws/config/rotate-root
vault write azure/config/rotate-root
```

### 4. Network Security
- Use TLS for all Vault communications
- Restrict network access to Vault
- Use private endpoints where possible

## Troubleshooting

### HCP Vault Specific Issues

1. **Connection Issues**
   ```bash
   # Check if you're using the correct namespace
   export VAULT_NAMESPACE="admin"
   vault status
   ```

2. **Token Expiration**
   - HCP admin tokens expire after 6 hours
   - Generate a new admin token from the HCP console
   - For production, use service principals or other auth methods

3. **Network Access**
   - Ensure your IP is allowed (HCP Vault is publicly accessible by default)
   - Check firewall rules if using VPN or corporate network

### Common Issues

1. **Authentication Failures**
   - Verify JWT configuration
   - Check GitHub token permissions
   - Validate audience and subject claims
   - Ensure `VAULT_NAMESPACE="admin"` is set

2. **Permission Denied**
   - Review Vault policies
   - Check role assignments
   - Verify secret engine configurations
   - Confirm you're in the admin namespace

3. **Dynamic Credential Issues**
   - Validate cloud provider permissions
   - Check secret engine configurations
   - Review credential generation logs
   - Ensure proper IAM roles and permissions

### Debugging Commands

```bash
# Check auth methods
vault auth list

# Check secret engines
vault secrets list

# Check policies
vault policy list
vault policy read openshift-deployment

# Check roles
vault list auth/jwt/role
vault read auth/jwt/role/github-actions-role
```

## Monitoring and Maintenance

### Regular Tasks
- Monitor audit logs
- Rotate root credentials
- Review and update policies
- Test credential generation
- Backup Vault configuration

### Metrics to Monitor
- Authentication success/failure rates
- Secret access patterns
- Dynamic credential generation
- Policy violations

---

**Next**: [GitHub Actions Setup](github-actions-setup.md) | [AWS Account Setup](../aws/account-setup.md)
