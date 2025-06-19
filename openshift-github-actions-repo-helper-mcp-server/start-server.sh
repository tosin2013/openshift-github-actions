#!/bin/bash

# OpenShift GitHub Actions Repository Helper MCP Server Startup Script
# This script provides an easy way to start the MCP server with proper checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}🚀 OpenShift GitHub Actions Repository Helper MCP Server${NC}"
echo -e "${BLUE}================================================================${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Check Node.js version
check_nodejs() {
    print_info "Checking Node.js version..."
    
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18.0.0 or higher."
        exit 1
    fi
    
    NODE_VERSION=$(node --version | sed 's/v//')
    REQUIRED_VERSION="18.0.0"
    
    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$NODE_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
        print_status "Node.js version $NODE_VERSION is compatible"
    else
        print_error "Node.js version $NODE_VERSION is too old. Please upgrade to 18.0.0 or higher."
        exit 1
    fi
}

# Check if dependencies are installed
check_dependencies() {
    print_info "Checking dependencies..."
    
    if [ ! -d "node_modules" ]; then
        print_warning "Dependencies not found. Installing..."
        npm install
    else
        print_status "Dependencies are installed"
    fi
}

# Check if project is built
check_build() {
    print_info "Checking build status..."
    
    if [ ! -f "dist/index.js" ]; then
        print_warning "Build not found. Building project..."
        npm run build
    else
        # Check if source files are newer than build
        if [ "$(find src -name '*.ts' -newer dist/index.js 2>/dev/null | wc -l)" -gt 0 ]; then
            print_warning "Source files are newer than build. Rebuilding..."
            npm run build
        else
            print_status "Build is up to date"
        fi
    fi
}

# Parse command line arguments
MODE="production"
LOG_LEVEL="1"
BACKGROUND=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dev)
            MODE="development"
            shift
            ;;
        -b|--background)
            BACKGROUND=true
            shift
            ;;
        -v|--verbose)
            LOG_LEVEL="0"
            shift
            ;;
        -q|--quiet)
            LOG_LEVEL="2"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --dev         Run in development mode with hot reload"
            echo "  -b, --background  Run in background"
            echo "  -v, --verbose     Enable verbose logging (LOG_LEVEL=0)"
            echo "  -q, --quiet       Quiet mode - warnings and errors only (LOG_LEVEL=2)"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                Start server in production mode"
            echo "  $0 --dev          Start server in development mode"
            echo "  $0 --background   Start server in background"
            echo "  $0 --verbose      Start server with verbose logging"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Perform checks
check_nodejs
check_dependencies
check_build

# Set environment variables
export LOG_LEVEL="$LOG_LEVEL"
export NODE_ENV="$MODE"

# Start the server
print_info "Starting MCP server in $MODE mode..."
print_info "Log level: $LOG_LEVEL"

if [ "$MODE" = "development" ]; then
    print_info "Development mode: Hot reload enabled"
    if [ "$BACKGROUND" = true ]; then
        nohup npm run dev > server.log 2>&1 &
        SERVER_PID=$!
        echo $SERVER_PID > server.pid
        print_status "Server started in background (PID: $SERVER_PID)"
        print_info "Logs: tail -f server.log"
        print_info "Stop: kill $SERVER_PID or kill \$(cat server.pid)"
    else
        npm run dev
    fi
else
    if [ "$BACKGROUND" = true ]; then
        nohup npm start > server.log 2>&1 &
        SERVER_PID=$!
        echo $SERVER_PID > server.pid
        print_status "Server started in background (PID: $SERVER_PID)"
        print_info "Logs: tail -f server.log"
        print_info "Stop: kill $SERVER_PID or kill \$(cat server.pid)"
    else
        print_status "Starting server... (Press Ctrl+C to stop)"
        npm start
    fi
fi
