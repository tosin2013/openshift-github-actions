#!/bin/bash

# Smart Pipelines Setup Script
# Sets up and validates the Smart Pipelines system for OpenShift multi-cloud automation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_SERVER_PATH="$REPO_ROOT/openshift-github-actions-repo-helper-mcp-server"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Node.js
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node --version)
        log_success "Node.js found: $NODE_VERSION"
        
        # Check if version is 18+
        NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
        if [[ $NODE_MAJOR -lt 18 ]]; then
            log_warning "Node.js version $NODE_VERSION detected. Recommend Node.js 18+ for optimal performance"
        fi
    else
        log_error "Node.js not found. Please install Node.js 18+ from https://nodejs.org/"
        return 1
    fi
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 --version)
        log_success "Python found: $PYTHON_VERSION"
    else
        log_error "Python 3 not found. Please install Python 3.11+ from https://python.org/"
        return 1
    fi
    
    # Check GitHub CLI (optional)
    if command -v gh >/dev/null 2>&1; then
        GH_VERSION=$(gh --version | head -1)
        log_success "GitHub CLI found: $GH_VERSION"
    else
        log_warning "GitHub CLI not found. Install from https://cli.github.com/ for manual workflow triggering"
    fi
    
    # Check if we're in a git repository
    if git rev-parse --git-dir >/dev/null 2>&1; then
        REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
        log_success "Git repository detected: $REPO_NAME"
    else
        log_error "Not in a git repository. Please run this script from the repository root"
        return 1
    fi
    
    log_success "Prerequisites check completed"
}

setup_mcp_server() {
    log_info "Setting up MCP server..."
    
    if [[ ! -d "$MCP_SERVER_PATH" ]]; then
        log_error "MCP server directory not found: $MCP_SERVER_PATH"
        log_info "Please ensure the openshift-github-actions-repo-helper-mcp-server is present"
        return 1
    fi
    
    cd "$MCP_SERVER_PATH"
    
    # Install dependencies
    log_info "Installing MCP server dependencies..."
    if npm ci; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies"
        return 1
    fi
    
    # Build the server
    log_info "Building MCP server..."
    if npm run build; then
        log_success "MCP server built successfully"
    else
        log_error "Failed to build MCP server"
        return 1
    fi
    
    # Test the server
    log_info "Testing MCP server..."
    if [[ -f "./start-server.sh" ]]; then
        chmod +x ./start-server.sh
        if ./start-server.sh --status; then
            log_success "MCP server is ready"
        else
            log_warning "MCP server status check failed - may need manual configuration"
        fi
    else
        log_warning "start-server.sh not found - MCP server may need manual setup"
    fi
    
    cd "$REPO_ROOT"
}

validate_workflows() {
    log_info "Validating Smart Pipeline workflows..."
    
    WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
    SMART_WORKFLOWS=(
        "smart-development-assistant.yml"
        "smart-pipeline-optimizer.yml"
        "smart-testing-validation.yml"
        "smart-deployment-assistant.yml"
    )
    
    for workflow in "${SMART_WORKFLOWS[@]}"; do
        WORKFLOW_PATH="$WORKFLOW_DIR/$workflow"
        if [[ -f "$WORKFLOW_PATH" ]]; then
            log_info "Validating $workflow..."
            
            # Basic YAML syntax check
            if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW_PATH'))" 2>/dev/null; then
                log_success "$workflow syntax is valid"
            else
                log_error "$workflow has YAML syntax errors"
                return 1
            fi
        else
            log_error "Smart Pipeline workflow not found: $workflow"
            return 1
        fi
    done
    
    log_success "All Smart Pipeline workflows validated"
}

check_secrets_configuration() {
    log_info "Checking secrets configuration..."
    
    # Check if we can access GitHub API (indicates GITHUB_TOKEN is available)
    if command -v gh >/dev/null 2>&1; then
        if gh api user >/dev/null 2>&1; then
            log_success "GitHub authentication is working"
        else
            log_warning "GitHub CLI not authenticated. Run 'gh auth login' for full functionality"
        fi
    fi
    
    log_info "Required secrets for Smart Pipelines:"
    echo "  Core (automatically provided):"
    echo "    - GITHUB_TOKEN ✅"
    echo ""
    echo "  Red Hat AI Services (optional - for AI enhancement):"
    echo "    - REDHAT_AI_API_KEY"
    echo "    - REDHAT_AI_ENDPOINT (optional - has default)"
    echo "    - REDHAT_AI_MODEL (optional - has default)"
    echo ""
    echo "  Deployment (for deployment assistance):"
    echo "    - VAULT_URL"
    echo "    - VAULT_ROOT_TOKEN"
    echo "    - OPENSHIFT_SERVER"
    echo "    - OPENSHIFT_TOKEN"
    echo ""
    log_info "Configure these secrets in GitHub repository settings > Secrets and variables > Actions"
}

create_sample_configuration() {
    log_info "Creating sample configuration files..."
    
    # Create sample environment file for Red Hat AI Services
    cat > "$REPO_ROOT/smart-pipelines.env.example" << 'EOF'
# Smart Pipelines Configuration Example
# Copy to smart-pipelines.env and configure for local testing

# Red Hat AI Services Configuration (Optional)
REDHAT_AI_API_KEY=your-api-key-here
REDHAT_AI_ENDPOINT=https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443
REDHAT_AI_MODEL=granite-8b-code-instruct-128k

# Development Configuration
PRIMARY_CLOUD=aws
DEVELOPMENT_PHASE=active
TARGET_ENVIRONMENT=dev

# MCP Server Configuration
MCP_SERVER_PATH=openshift-github-actions-repo-helper-mcp-server
EOF
    
    log_success "Sample configuration created: smart-pipelines.env.example"
    
    # Add to .gitignore if not already present
    if [[ -f "$REPO_ROOT/.gitignore" ]]; then
        if ! grep -q "smart-pipelines.env" "$REPO_ROOT/.gitignore"; then
            echo "smart-pipelines.env" >> "$REPO_ROOT/.gitignore"
            log_success "Added smart-pipelines.env to .gitignore"
        fi
    fi
}

test_smart_pipelines() {
    log_info "Testing Smart Pipelines functionality..."
    
    # Test MCP server if available
    if [[ -f "$MCP_SERVER_PATH/start-server.sh" ]]; then
        cd "$MCP_SERVER_PATH"
        if ./start-server.sh --status >/dev/null 2>&1; then
            log_success "MCP server is operational"
        else
            log_warning "MCP server test failed - may need manual configuration"
        fi
        cd "$REPO_ROOT"
    fi
    
    # Test Python dependencies
    log_info "Testing Python dependencies..."
    python3 -c "
import sys
required_modules = ['yaml', 'json', 'requests']
missing_modules = []

for module in required_modules:
    try:
        __import__(module)
    except ImportError:
        missing_modules.append(module)

if missing_modules:
    print(f'Missing Python modules: {missing_modules}')
    print('Install with: pip install pyyaml requests')
    sys.exit(1)
else:
    print('All required Python modules available')
"
    
    if [[ $? -eq 0 ]]; then
        log_success "Python dependencies are available"
    else
        log_warning "Some Python dependencies are missing - install with: pip install pyyaml requests"
    fi
}

show_usage_examples() {
    log_info "Smart Pipelines Usage Examples:"
    echo ""
    echo "1. Trigger development analysis:"
    echo "   gh workflow run smart-development-assistant.yml -f analysis_type=comprehensive"
    echo ""
    echo "2. Run AWS-focused optimization:"
    echo "   gh workflow run smart-pipeline-optimizer.yml -f optimization_focus=aws-specific"
    echo ""
    echo "3. Comprehensive testing:"
    echo "   gh workflow run smart-testing-validation.yml -f test_scope=comprehensive"
    echo ""
    echo "4. Pre-deployment check:"
    echo "   gh workflow run smart-deployment-assistant.yml -f deployment_type=pre-deployment-check -f target_cloud=aws"
    echo ""
    echo "5. View workflow status:"
    echo "   gh run list --workflow=smart-development-assistant.yml"
    echo ""
    log_info "For more information, see: docs/smart-pipelines-guide.md"
}

main() {
    echo "🤖 Smart Pipelines Setup for OpenShift Multi-Cloud Automation"
    echo "=============================================================="
    echo ""
    
    # Run setup steps
    check_prerequisites || exit 1
    echo ""
    
    setup_mcp_server || exit 1
    echo ""
    
    validate_workflows || exit 1
    echo ""
    
    check_secrets_configuration
    echo ""
    
    create_sample_configuration
    echo ""
    
    test_smart_pipelines
    echo ""
    
    show_usage_examples
    echo ""
    
    log_success "🎉 Smart Pipelines setup completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "1. Configure required secrets in GitHub repository settings"
    echo "2. Review docs/smart-pipelines-guide.md for detailed usage"
    echo "3. Run your first smart pipeline workflow"
    echo "4. Monitor AWS deployment development with AI assistance"
    echo ""
    log_info "Focus: AWS deployment stabilization with multi-cloud expansion planning"
}

# Run main function
main "$@"
