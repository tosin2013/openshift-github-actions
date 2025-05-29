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
- HashiCorp Vault instance or HCP Vault
- Cloud provider accounts (AWS, Azure, GCP) with appropriate permissions
- OpenShift Pull Secret from Red Hat
- Domain name with DNS management capabilities

## Quick Start

1. **Clone this repository**
   ```bash
   git clone https://github.com/your-org/openshift-github-actions.git
   cd openshift-github-actions
   ```

2. **Configure HashiCorp Vault**
   - Follow the [Vault Setup Guide](docs/common/vault-setup.md)
   - Store your cloud provider credentials and OpenShift secrets

3. **Configure GitHub repository secrets**
   - Add your Vault URL and authentication details
   - See [GitHub Actions Setup](docs/common/github-actions-setup.md)

4. **Run a deployment workflow**
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


**Diagrammatic Representation (Mermaid):**
```mermaid
graph TD
    subgraph OpenShift Cluster (4.18)
        I[Cert-Manager] -- Manages --> J[TLS Certificate for Vault]
        subgraph "vault Namespace"
            K[Helm Release: vault] --> B[Vault StatefulSet]
            B -- Manages --> C1[Vault Pod 1 (Active)]
            B -- Manages --> C2[Vault Pod 2 (Standby)]
            B -- Manages --> C3[Vault Pod 3 (Standby)]
            C1 --> D[Persistent Volume via PVC]
            C2 --> D
            C3 --> D
            C1 --> E[ConfigMap: vault-config]
            C2 --> E
            C3 --> E
            F[Service Account: vault] -- Bound to --> vaultSCC[SCC: vault-scc]
            C1 -- Uses --> F
            C2 -- Uses --> F
            C3 -- Uses --> F
            J -- Mounted into --> C1
            J -- Mounted into --> C2
            J -- Mounted into --> C3
            SVC[Service: vault (ClusterIP)] --> C1
            SVC --> C2
            SVC --> C3
        end
    end
    G[OpenShift Route: vault (HTTPS - Passthrough)] --> SVC
    User[User/Application] -- HTTPS --> G
    C1 --> H[Vault UI/API over HTTPS]
````



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

**Author**: Tosin Akinosho  
**Based on**: "Automating OpenShift 4.18 Installations Across Multiple Cloud Platforms"
