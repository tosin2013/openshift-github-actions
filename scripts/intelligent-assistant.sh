#!/bin/bash

# Intelligent Pipeline Assistant - Manual Trigger Script
# This script provides an easy way to trigger the intelligent assistant for pipeline analysis

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Function to print colored output
print_header() {
    echo -e "${BLUE}🤖 OpenShift GitHub Actions Intelligent Assistant${NC}"
    echo -e "${BLUE}=================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${PURPLE}ℹ️${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Trigger the Intelligent Pipeline Assistant for analysis and optimization.

OPTIONS:
    -t, --type TYPE         Analysis type (failure-analysis, optimization-suggestions, 
                           documentation-generation, test-plan-creation, architecture-review)
    -r, --run-id ID        Specific workflow run ID to analyze
    -a, --ai-enhanced      Enable AI enhancement using Red Hat AI Services (Granite)
    -p, --period DAYS      Analysis period in days (for optimization analysis)
    -f, --focus AREA       Optimization focus (performance, reliability, security, cost, all)
    -l, --list-runs        List recent workflow runs
    -s, --status           Show MCP server status
    -h, --help             Show this help message

EXAMPLES:
    # Analyze the last failed workflow
    $0 --type failure-analysis

    # Generate optimization suggestions for the last 7 days
    $0 --type optimization-suggestions --period 7 --focus performance

    # Analyze a specific workflow run with AI enhancement
    $0 --type failure-analysis --run-id 1234567890 --ai-enhanced

    # List recent workflow runs to find run ID
    $0 --list-runs

    # Check MCP server status
    $0 --status

ANALYSIS TYPES:
    failure-analysis           Analyze failed workflows and provide troubleshooting guidance
    optimization-suggestions   Suggest performance and reliability improvements
    documentation-generation   Generate comprehensive workflow documentation
    test-plan-creation         Create test plans for workflow validation
    architecture-review        Review and suggest architectural improvements

OPTIMIZATION FOCUS AREAS:
    performance               Execution time, resource usage, caching
    reliability               Error handling, retry mechanisms, monitoring
    security                  Secret management, access controls, compliance
    cost                      Resource optimization, efficiency improvements
    all                       Comprehensive analysis across all areas

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi
    
    # Check if GitHub CLI is available
    if ! command -v gh &> /dev/null; then
        print_warning "GitHub CLI (gh) not found. Some features may not work."
        print_info "Install with: https://cli.github.com/"
    fi
    
    # Check if we're in the correct repository
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
    if [[ "$REPO_NAME" != "openshift-github-actions" ]]; then
        print_warning "This script is designed for the openshift-github-actions repository"
        print_info "Current repository: $REPO_NAME"
    fi
    
    print_success "Prerequisites checked"
}

# Function to list recent workflow runs
list_workflow_runs() {
    print_info "Fetching recent workflow runs..."
    
    if command -v gh &> /dev/null; then
        echo ""
        echo "Recent Workflow Runs:"
        echo "===================="
        gh run list --limit 10 --json databaseId,name,status,conclusion,createdAt,url \
            --template '{{range .}}{{.databaseId}} | {{.name}} | {{.status}} | {{.conclusion}} | {{timeago .createdAt}} | {{.url}}
{{end}}' | column -t -s '|'
    else
        print_error "GitHub CLI required to list workflow runs"
        print_info "Install GitHub CLI: https://cli.github.com/"
        exit 1
    fi
}

# Function to check MCP server status
check_mcp_status() {
    print_info "Checking MCP server status..."
    
    MCP_DIR="$REPO_ROOT/openshift-github-actions-repo-helper-mcp-server"
    
    if [[ ! -d "$MCP_DIR" ]]; then
        print_error "MCP server directory not found: $MCP_DIR"
        exit 1
    fi
    
    cd "$MCP_DIR"
    
    # Check if server is running
    if [[ -f "server.pid" ]]; then
        PID=$(cat server.pid)
        if ps -p "$PID" > /dev/null 2>&1; then
            print_success "MCP server is running (PID: $PID)"
            
            # Check server logs
            if [[ -f "server.log" ]]; then
                echo ""
                echo "Recent server activity:"
                echo "======================"
                tail -5 server.log
            fi
        else
            print_warning "PID file exists but process not running"
            rm -f server.pid
        fi
    else
        print_info "MCP server is not running"
    fi
    
    # Check if dependencies are installed
    if [[ -d "node_modules" ]]; then
        print_success "Dependencies installed"
    else
        print_warning "Dependencies not installed. Run: npm install"
    fi
    
    # Check if built
    if [[ -f "dist/index.js" ]]; then
        print_success "Server built successfully"
    else
        print_warning "Server not built. Run: npm run build"
    fi
}

# Function to trigger workflow analysis
trigger_analysis() {
    local analysis_type="$1"
    local run_id="${2:-}"
    local ai_enhanced="${3:-false}"
    
    print_info "Triggering intelligent analysis..."
    print_info "Type: $analysis_type"
    
    if [[ -n "$run_id" ]]; then
        print_info "Run ID: $run_id"
    fi
    
    if [[ "$ai_enhanced" == "true" ]]; then
        print_info "AI Enhancement: Enabled (Granite model)"
    fi
    
    if command -v gh &> /dev/null; then
        # Build workflow dispatch command
        local dispatch_cmd="gh workflow run intelligent-pipeline-assistant.yml"
        dispatch_cmd="$dispatch_cmd -f analysis_type=$analysis_type"
        dispatch_cmd="$dispatch_cmd -f ai_enhanced=$ai_enhanced"
        
        if [[ -n "$run_id" ]]; then
            dispatch_cmd="$dispatch_cmd -f workflow_run_id=$run_id"
        fi
        
        echo ""
        print_info "Executing: $dispatch_cmd"
        
        if eval "$dispatch_cmd"; then
            print_success "Analysis workflow triggered successfully!"
            echo ""
            print_info "Monitor progress with: gh run list"
            print_info "View results in GitHub Issues after completion"
        else
            print_error "Failed to trigger analysis workflow"
            exit 1
        fi
    else
        print_error "GitHub CLI required to trigger workflows"
        print_info "Install GitHub CLI: https://cli.github.com/"
        print_info "Or trigger manually via GitHub Actions web interface"
        exit 1
    fi
}

# Function to trigger optimization analysis
trigger_optimization() {
    local period="$1"
    local focus="$2"
    
    print_info "Triggering optimization analysis..."
    print_info "Period: $period days"
    print_info "Focus: $focus"
    
    if command -v gh &> /dev/null; then
        local dispatch_cmd="gh workflow run proactive-pipeline-optimizer.yml"
        dispatch_cmd="$dispatch_cmd -f analysis_period=$period"
        dispatch_cmd="$dispatch_cmd -f optimization_focus=$focus"
        
        echo ""
        print_info "Executing: $dispatch_cmd"
        
        if eval "$dispatch_cmd"; then
            print_success "Optimization analysis triggered successfully!"
            echo ""
            print_info "Monitor progress with: gh run list"
            print_info "View results in GitHub Issues after completion"
        else
            print_error "Failed to trigger optimization analysis"
            exit 1
        fi
    else
        print_error "GitHub CLI required to trigger workflows"
        exit 1
    fi
}

# Main function
main() {
    local analysis_type=""
    local run_id=""
    local ai_enhanced="false"
    local period="7"
    local focus="performance"
    local list_runs=false
    local show_status=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                analysis_type="$2"
                shift 2
                ;;
            -r|--run-id)
                run_id="$2"
                shift 2
                ;;
            -a|--ai-enhanced)
                ai_enhanced="true"
                shift
                ;;
            -p|--period)
                period="$2"
                shift 2
                ;;
            -f|--focus)
                focus="$2"
                shift 2
                ;;
            -l|--list-runs)
                list_runs=true
                shift
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_header
    check_prerequisites
    
    # Handle different modes
    if [[ "$list_runs" == "true" ]]; then
        list_workflow_runs
        exit 0
    fi
    
    if [[ "$show_status" == "true" ]]; then
        check_mcp_status
        exit 0
    fi
    
    # Validate analysis type
    if [[ -z "$analysis_type" ]]; then
        print_error "Analysis type is required"
        echo ""
        show_usage
        exit 1
    fi
    
    case "$analysis_type" in
        failure-analysis|documentation-generation|test-plan-creation|architecture-review)
            trigger_analysis "$analysis_type" "$run_id" "$ai_enhanced"
            ;;
        optimization-suggestions)
            trigger_optimization "$period" "$focus"
            ;;
        *)
            print_error "Invalid analysis type: $analysis_type"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
