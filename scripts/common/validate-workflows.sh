#!/bin/bash
# AI-Powered Workflow Validator Wrapper Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source environment if available
if [ -f "$SCRIPT_DIR/ai-validator.env" ]; then
    set -a
    source "$SCRIPT_DIR/ai-validator.env"
    set +a
fi

# Default values
API_KEY="${REDHAT_AI_API_KEY:-}"
API_URL="${REDHAT_AI_ENDPOINT:-https://granite-8b-code-instruct-maas-apicast-production.apps.prod.rhoai.rh-aiservices-bu.com:443}"
AUTO_FIX="${AUTO_FIX_ENABLED:-false}"

usage() {
    cat << EOF
AI-Powered GitHub Actions Workflow Validator

USAGE:
    $0 [OPTIONS] <path>

OPTIONS:
    --fix           Automatically fix issues using AI
    --api-key KEY   Red Hat AI API key (or set REDHAT_AI_API_KEY)
    --help          Show this help

EXAMPLES:
    # Validate all workflows
    $0 .github/workflows/

    # Validate and auto-fix specific workflow
    $0 --fix .github/workflows/deploy-aws.yml

    # Validate with custom API key
    $0 --api-key "your-key" .github/workflows/

ENVIRONMENT:
    REDHAT_AI_API_KEY    API key for Red Hat Granite AI
    REDHAT_AI_ENDPOINT   API endpoint (default: production)
    AUTO_FIX_ENABLED     Enable auto-fix by default (true/false)

EOF
}

# Parse arguments
AUTO_FIX_FLAG=""
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            AUTO_FIX_FLAG="--auto-fix"
            shift
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            TARGET_PATH="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$TARGET_PATH" ]; then
    echo "❌ Error: Path required"
    usage
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo "❌ Error: API key required. Set REDHAT_AI_API_KEY environment variable or use --api-key"
    exit 1
fi

# Check if target path exists
if [ ! -e "$TARGET_PATH" ]; then
    echo "❌ Error: Path not found: $TARGET_PATH"
    exit 1
fi

# Install dependencies if needed
echo "🔧 Checking dependencies..."
if ! python3 -c "import yaml, requests" 2>/dev/null; then
    echo "📦 Installing required Python packages..."
    pip3 install --user pyyaml requests urllib3 numpy
fi

# Run the validator
echo "🚀 Running AI-powered workflow validation..."
echo "📍 Target: $TARGET_PATH"
echo "🤖 AI: $API_URL"

if [ "$AUTO_FIX" = "true" ] || [ -n "$AUTO_FIX_FLAG" ]; then
    echo "🔧 Auto-fix: Enabled"
else
    echo "🔍 Mode: Validation only"
fi

python3 "$SCRIPT_DIR/ai-workflow-validator.py" \
    $AUTO_FIX_FLAG \
    --api-key "$API_KEY" \
    --api-url "$API_URL" \
    --output "$PROJECT_ROOT/validation-report.json" \
    "$TARGET_PATH"

echo "✅ Validation complete!"
