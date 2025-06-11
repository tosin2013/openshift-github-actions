# OpenShift 4.18 Multi-Cloud Automation

This repository contains GitHub Actions workflows for automating OpenShift 4.18 installations across AWS, Azure, and Google Cloud Platform using Installer Provisioned Infrastructure (IPI). These workflows leverage HashiCorp Vault for secure credential management and follow best practices for multi-cloud deployments.

## Features

- 🚀 Automated OpenShift 4.18 IPI deployments on AWS, Azure, and GCP
- 🔐 Secure credential management with HashiCorp Vault
- 🔄 Comprehensive testing and validation workflows
- 📊 Operational workflows for updates and maintenance
- 🏗️ Infrastructure as Code with consistent configurations
- 📚 Comprehensive documentation and troubleshooting guides

## Prerequisites

- GitHub account with Actions enabled
- OpenShift cluster with admin access (for Vault deployment)
- HashiCorp Vault instance or HCP Vault (can be deployed using included scripts)
- Cloud provider accounts (AWS, Azure, GCP) with appropriate permissions
- OpenShift Pull Secret from Red Hat (saved as `~/pull-secret.json`)
- Domain name with DNS management capabilities
- cert-manager installed on OpenShift cluster
- Helm 3.x installed locally

## Quick Start

1. **Clone this repository**
   ```bash
   git clone https://github.com/tosin2013/openshift-github-actions.git
   cd openshift-github-actions
   ```

2. **Deploy HashiCorp Vault (if needed)**
   ```bash
   # Deploy Vault HA cluster with TLS (3-step process)
   export VAULT_NAMESPACE="vault-production"

   # Step 1: Deploy Vault infrastructure with TLS
   ./deploy_vault_ha_tls_complete.sh

   # Step 2: Initialize and unseal Vault cluster
   ./direct_vault_init.sh

   # Step 3: Verify deployment and get score
   ./verify_vault_deployment.sh
   ```

3. **Prepare OpenShift Pull Secret**
   ```bash
   # Download from https://console.redhat.com/openshift/install/pull-secret
   # Save as ~/pull-secret.json
   ```

4. **Configure AWS Integration in Vault**
   ```bash
   # Configure AWS credentials and secrets engine in Vault
   ./scripts/vault/setup-aws-integration.sh
   ```

5. **Add Required Secrets to Vault**
   ```bash
   # This script adds pull secret and SSH keys to Vault
   ./scripts/vault/add-openshift-secrets.sh
   ```

6. **Configure GitHub repository secrets**
   - Add your Vault URL and authentication details
   - See [GitHub Actions Setup](docs/common/github-actions-setup.md)

7. **Run a deployment workflow**
   - Navigate to Actions tab in GitHub
   - Select your desired cloud provider workflow
   - Provide required parameters and deploy

## Repository Structure

```
openshift-github-actions/
├── .github/
│   └── workflows/          # GitHub Actions workflow definitions
├── scripts/
│   ├── aws/               # AWS-specific scripts
│   ├── azure/             # Azure-specific scripts
│   ├── gcp/               # GCP-specific scripts
│   ├── vault/             # Vault setup and management scripts
│   └── common/            # Common utilities and functions
├── config/
│   ├── aws/               # AWS configuration templates
│   ├── azure/             # Azure configuration templates
│   ├── gcp/               # GCP configuration templates
│   └── common/            # Common configurations
├── docs/
│   ├── aws/               # AWS-specific documentation
│   ├── azure/             # Azure-specific documentation
│   ├── gcp/               # GCP-specific documentation
│   └── common/            # Common documentation
└── tests/
    ├── unit/              # Unit tests
    ├── integration/       # Integration tests
    └── validation/        # Cluster validation tests
```


**Vault HA Architecture:**
```mermaid
graph TD
    subgraph "OpenShift Cluster 4.18"
        I[Cert-Manager] --> J[TLS Certificate for Vault]
        subgraph "vault Namespace"
            K[Helm Release: vault] --> B[Vault StatefulSet]
            B --> C1[vault-0 Active]
            B --> C2[vault-1 Standby]
            B --> C3[vault-2 Standby]
            C1 --> D[Persistent Volume]
            C2 --> D
            C3 --> D
            C1 --> E[ConfigMap: vault-config]
            C2 --> E
            C3 --> E
            F[Service Account] --> vaultSCC[SCC: vault-scc]
            C1 --> F
            C2 --> F
            C3 --> F
            J --> C1
            J --> C2
            J --> C3
            SVC[Service: vault] --> C1
            SVC --> C2
            SVC --> C3
        end
    end
    G[OpenShift Route: HTTPS] --> SVC
    User[User/Application] --> G
    C1 --> H[Vault UI/API]
```



## 🔐 Vault Secrets Setup (Required)

Before deploying OpenShift clusters, you must add the required secrets to Vault using the automated setup script.

### Required Secrets

The deployment workflows require these secrets in Vault:
- **Pull Secret**: OpenShift pull secret from Red Hat (`secret/data/openshift/pull-secret`)
- **SSH Keys**: SSH key pair for cluster access (`secret/data/openshift/ssh-keys/dev`)

### Automated Setup

```bash
# 1. Download your pull secret from Red Hat
# https://console.redhat.com/openshift/install/pull-secret
# Save as ~/pull-secret.json

# 2. Configure AWS integration in Vault (REQUIRED FIRST)
./scripts/vault/setup-aws-integration.sh

# 3. Run the automated OpenShift secrets setup script
./scripts/vault/add-openshift-secrets.sh
```

### What the Scripts Do

**AWS Integration Setup (`setup-aws-integration.sh`):**
1. ✅ **Validates Vault connectivity** - Ensures Vault is accessible
2. ✅ **Enables AWS secrets engine** - Sets up dynamic credential generation
3. ✅ **Configures AWS root credentials** - Stores AWS access keys securely
4. ✅ **Creates OpenShift installer role** - IAM role with required permissions
5. ✅ **Tests dynamic credentials** - Validates credential generation works

**OpenShift Secrets Setup (`add-openshift-secrets.sh`):**
1. ✅ **Validates Vault connectivity** - Ensures Vault is accessible
2. ✅ **Enables KV secrets engine** - Sets up `secret/` path if needed
3. ✅ **Adds pull secret** - Reads from `~/pull-secret.json` and stores in Vault
4. ✅ **Generates SSH keys** - Creates RSA 4096-bit key pair for cluster access
5. ✅ **Verifies setup** - Confirms all secrets are properly stored

### Manual Verification

```bash
# Check if secrets exist in Vault
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/pull-secret
oc exec vault-0 -n vault-test-pragmatic -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/ssh-keys/dev
```

## Supported Cloud Providers

### Amazon Web Services (AWS)
- **Regions**: All AWS regions where OpenShift 4.18 is supported
- **Instance Types**: Configurable master and worker node types
- **Networking**: VPC with public/private subnets
- **Storage**: EBS volumes with configurable types and sizes

### Microsoft Azure
- **Regions**: All Azure regions where OpenShift 4.18 is supported
- **VM Sizes**: Configurable master and worker VM sizes
- **Networking**: Virtual Network with subnets
- **Storage**: Managed disks with configurable types and sizes

### Google Cloud Platform (GCP)
- **Regions**: All GCP regions where OpenShift 4.18 is supported
- **Machine Types**: Configurable master and worker machine types
- **Networking**: VPC with subnets
- **Storage**: Persistent disks with configurable types and sizes

## Workflows

### Deployment Workflows
- `deploy-aws.yml` - Deploy OpenShift cluster on AWS
- `deploy-azure.yml` - Deploy OpenShift cluster on Azure
- `deploy-gcp.yml` - Deploy OpenShift cluster on GCP

### Operational Workflows
- `update-cluster.yml` - Update existing OpenShift clusters
- `destroy-cluster.yml` - Safely destroy OpenShift clusters
- `validate-cluster.yml` - Validate cluster health and configuration

### Utility Workflows
- `validate-config.yml` - Validate configuration files
- `run-tests.yml` - Execute test suites

## Documentation

- [Getting Started Guide](docs/getting-started.md)
- [Prerequisites](docs/prerequisites.md)
- [AWS Setup](docs/aws/account-setup.md)
- [Azure Setup](docs/azure/account-setup.md)
- [GCP Setup](docs/gcp/account-setup.md)
- [Vault Setup](docs/common/vault-setup.md)
- [GitHub Actions Setup](docs/common/github-actions-setup.md)
- [Troubleshooting](docs/common/troubleshooting.md)

## Security

This repository implements security best practices:

- Credentials are never stored in code or logs
- HashiCorp Vault provides centralized secret management
- Dynamic credentials are used where possible
- All deployments include security validation
- Audit trails are maintained for all operations

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to contribute to this project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support and questions:
- Check the [documentation](docs/)
- Review [troubleshooting guides](docs/common/troubleshooting.md)
- Open an issue in this repository

---

## 🔐 Vault HA Deployment with TLS (Production Ready)

**Deployment Score: 95/100 | Repeatability: 95/100**

Enterprise-grade HashiCorp Vault High Availability deployment on OpenShift with complete automation.

### ✅ Key Features
- **Complete automation** - single command deployment
- **95% success rate** - enterprise-grade reliability
- **TLS encryption** - end-to-end security with cert-manager
- **HA cluster** - leader + standby configuration
- **Production ready** - comprehensive verification and monitoring

### 🚀 Quick Start

```bash
# Complete 5-step Vault HA deployment with AWS integration
export VAULT_NAMESPACE="vault-production"

# Step 1: Deploy infrastructure (3-5 minutes)
./deploy_vault_ha_tls_complete.sh

# Step 2: Initialize and unseal (2-3 minutes)
./direct_vault_init.sh
# If script hangs, manually verify: oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status"
# If pods sealed, run: ./ensure-all-pods-unsealed.sh

# Step 3: Verify and score (1-2 minutes)
./verify_vault_deployment.sh
# If script hangs, manually verify: for pod in vault-0 vault-1 vault-2; do oc exec $pod -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" | grep -E "(Initialized|Sealed|HA Mode)"; done

# Step 4: Configure AWS credentials in Vault (2-3 minutes)
./scripts/vault/setup-aws-integration.sh

# Step 5: Add OpenShift secrets to Vault (1-2 minutes)
./scripts/vault/add-openshift-secrets.sh
```

**Expected time:** 10-15 minutes total
**Expected score:** 95/100

### ⚠️ Script Hanging Issues (macOS/Linux)

If scripts hang during status checks, use these manual steps:

```bash
# If Step 2 hangs, manually verify and complete:
# 1. Check current status
oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status"

# 2. If pods are sealed, run automated unsealing
./ensure-all-pods-unsealed.sh

# 3. Verify all pods are unsealed
for pod in vault-0 vault-1 vault-2; do
  echo "=== $pod ==="
  oc exec $pod -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" | grep -E "(Initialized|Sealed|HA Mode)"
done

# If Step 3 hangs, manually verify deployment:
# 1. Check external access
VAULT_ROUTE=$(oc get route vault -n $VAULT_NAMESPACE -o jsonpath='{.spec.host}')
curl -k -s "https://$VAULT_ROUTE/v1/sys/health" | jq '.initialized, .sealed'

# 2. Verify HA cluster status
oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" | grep "HA Mode"
```

**Note:** Scripts may hang on status detection but infrastructure works correctly. Use Ctrl+C to cancel hanging scripts and verify manually.

### 📚 Documentation

- **[Quick Start Guide](docs/guides/quick-start.md)** - Get started in minutes
- **[Architecture Decisions](docs/adrs/)** - Technical methodology and decisions
- **[Troubleshooting](docs/troubleshooting/)** - Common issues and solutions

### 📋 Prerequisites
- OpenShift cluster with admin access
- cert-manager installed and operational
- Helm 3.x installed
- Python 3.x with Jinja2

### 🎯 Key Scripts

**Core Deployment Scripts (run in order):**
- **`deploy_vault_ha_tls_complete.sh`** - Main Vault HA deployment automation
- **`direct_vault_init.sh`** - Vault initialization and unsealing (**REQUIRED after deployment**)
- **`verify_vault_deployment.sh`** - Deployment verification and scoring

**Configuration Scripts (run in order after Step 3):**
- **`scripts/vault/setup-aws-integration.sh`** - **REQUIRED**: Configure AWS credentials and secrets engine in Vault
- **`scripts/vault/add-openshift-secrets.sh`** - **REQUIRED**: Add OpenShift secrets to Vault (run after AWS setup)

**TLS and Troubleshooting Scripts:**
- **`apply-vault-cert-manager.sh`** - TLS certificate management with cert-manager
- **`ensure-all-pods-unsealed.sh`** - Automated pod unsealing for HA cluster completion
- **`fix-vault-tls-configuration.sh`** - Comprehensive TLS configuration fix and validation

### 🏗️ Architecture

**Three-Phase Deployment Methodology:**
1. **Infrastructure Setup** (`deploy_vault_ha_tls_complete.sh`)
   - Deploy pods, services, routes with HTTP
   - TLS upgrade with automatic ConfigMap patching and pod restart
   - cert-manager certificate generation
2. **Vault Operations** (`direct_vault_init.sh`)
   - Initialize Vault cluster with 5 unseal keys
   - Unseal leader and standby nodes
   - Form HA Raft cluster
3. **Verification** (`verify_vault_deployment.sh`)
   - Comprehensive testing and scoring
   - External access validation
   - HA cluster health checks

See [ADR-001](docs/adrs/001-two-phase-vault-deployment.md) for detailed technical decisions.

### 🎯 Expected Results
- **Infrastructure**: 100% success (all pods, services, routes operational)
- **TLS Integration**: 100% success (HTTPS working internally and externally)
- **Vault Leader**: 100% success (vault-0 initialized and unsealed)
- **HA Cluster**: 95% success (leader + standby nodes operational)
- **External Access**: 100% success (UI accessible via HTTPS)
- **Overall Score**: 95/100

### 🔧 Troubleshooting Common Issues

**1. Script Hanging During Status Checks**
```bash
# If direct_vault_init.sh hangs:
# 1. Cancel with Ctrl+C
# 2. Check if Vault is already initialized
oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status"

# 3. If sealed, run automated unsealing
./ensure-all-pods-unsealed.sh

# If verify_vault_deployment.sh hangs:
# 1. Cancel with Ctrl+C
# 2. Manual verification
for pod in vault-0 vault-1 vault-2; do
  oc exec $pod -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" | grep -E "(Initialized|Sealed|HA Mode)"
done
```

**2. TLS Configuration Issues**
```bash
# Check TLS secret exists
oc get secret vault-tls -n $VAULT_NAMESPACE

# Verify certificate
oc get certificate vault-tls -n $VAULT_NAMESPACE -o yaml

# Fix TLS configuration comprehensively
./fix-vault-tls-configuration.sh

# Check Vault logs for TLS errors
oc logs vault-0 -n $VAULT_NAMESPACE
```

**3. Vault Initialization Fails**
```bash
# Check if Vault is already initialized (with proper TLS)
oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status"

# Manual initialization if needed
oc exec vault-0 -n $VAULT_NAMESPACE -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault operator init"

# Ensure all pods are unsealed after initialization
./ensure-all-pods-unsealed.sh
```

**4. ClusterRoleBinding Conflicts**
```bash
# Clean up existing bindings
oc delete clusterrolebinding vault-server-binding

# Re-run deployment
./deploy_vault_ha_tls_complete.sh
```

**5. Pods Not Starting**
```bash
# Check pod status and events
oc get pods -n $VAULT_NAMESPACE
oc describe pod vault-0 -n $VAULT_NAMESPACE

# Check SCC permissions
oc get scc vault-scc

# Check TLS certificate availability
oc get secret vault-tls -n $VAULT_NAMESPACE
```

### 📚 Additional Documentation

**Deployment Guides:**
- **[Complete Vault Deployment Guide](docs/guides/vault-deployment-complete.md)** - **COMPREHENSIVE**: Full deployment process
- **[Phase 1 AWS Implementation](docs/guides/phase1-aws-implementation.md)** - AWS integration guide
- **[Quick Start](docs/guides/quick-start.md)** - Basic deployment steps

**Troubleshooting:**
- **[Troubleshooting Guide](docs/troubleshooting/)** - General issue resolution
- **[cert-manager Issues](docs/troubleshooting/cert-manager-issues.md)** - Certificate problems
- **[Architecture Details](docs/adrs/)** - Technical decisions and methodology

---

**Author**: Tosin Akinosho
**Based on**: "Automating OpenShift 4.18 Installations Across Multiple Cloud Platforms"
