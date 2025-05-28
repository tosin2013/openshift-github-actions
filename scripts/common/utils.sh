#!/bin/bash

# Common utility functions for OpenShift multi-cloud automation
# Author: Tosin Akinosho

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Default log level
CURRENT_LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log a message with timestamp and level
log() {
  local level=$1
  local message=$2
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case $level in
    DEBUG)
      if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]; then
        echo -e "${BLUE}[$timestamp] [DEBUG]${NC} $message" >&2
      fi
      ;;
    INFO)
      if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]; then
        echo -e "${GREEN}[$timestamp] [INFO]${NC} $message" >&2
      fi
      ;;
    WARN)
      if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARN ]; then
        echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" >&2
      fi
      ;;
    ERROR)
      if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ]; then
        echo -e "${RED}[$timestamp] [ERROR]${NC} $message" >&2
      fi
      ;;
    *)
      echo -e "${NC}[$timestamp] [UNKNOWN]${NC} $message" >&2
      ;;
  esac
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Wait for a condition with timeout
wait_for() {
  local command=$1
  local timeout=$2
  local interval=${3:-5}
  local description=${4:-"condition"}
  
  local end_time=$(($(date +%s) + timeout))
  
  log "INFO" "Waiting for $description (timeout: ${timeout}s, interval: ${interval}s)"
  
  while [ $(date +%s) -lt $end_time ]; do
    if eval "$command"; then
      log "INFO" "$description completed successfully"
      return 0
    fi
    log "DEBUG" "Waiting for $description... ($(($end_time - $(date +%s)))s remaining)"
    sleep $interval
  done
  
  log "ERROR" "Timeout waiting for $description"
  return 1
}

# Validate required environment variables
validate_env_vars() {
  local missing_vars=()
  
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      missing_vars+=("$var")
    fi
  done
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    log "ERROR" "Required environment variables are not set: ${missing_vars[*]}"
    return 1
  fi
  
  log "DEBUG" "All required environment variables are set: $*"
  return 0
}

# Validate required files exist
validate_files() {
  local missing_files=()
  
  for file in "$@"; do
    if [ ! -f "$file" ]; then
      missing_files+=("$file")
    fi
  done
  
  if [ ${#missing_files[@]} -gt 0 ]; then
    log "ERROR" "Required files are missing: ${missing_files[*]}"
    return 1
  fi
  
  log "DEBUG" "All required files exist: $*"
  return 0
}

# Validate required directories exist
validate_directories() {
  local missing_dirs=()
  
  for dir in "$@"; do
    if [ ! -d "$dir" ]; then
      missing_dirs+=("$dir")
    fi
  done
  
  if [ ${#missing_dirs[@]} -gt 0 ]; then
    log "ERROR" "Required directories are missing: ${missing_dirs[*]}"
    return 1
  fi
  
  log "DEBUG" "All required directories exist: $*"
  return 0
}

# Create directory if it doesn't exist
ensure_directory() {
  local dir=$1
  local mode=${2:-755}
  
  if [ ! -d "$dir" ]; then
    log "INFO" "Creating directory: $dir"
    mkdir -p "$dir"
    chmod "$mode" "$dir"
  fi
}

# Backup a file with timestamp
backup_file() {
  local file=$1
  local backup_dir=${2:-"./backups"}
  
  if [ -f "$file" ]; then
    ensure_directory "$backup_dir"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/$(basename "$file").backup.$timestamp"
    
    log "INFO" "Backing up $file to $backup_file"
    cp "$file" "$backup_file"
    return 0
  else
    log "WARN" "File $file does not exist, skipping backup"
    return 1
  fi
}

# Generate a random string
generate_random_string() {
  local length=${1:-16}
  local charset=${2:-'a-zA-Z0-9'}
  
  if command_exists openssl; then
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
  elif [ -f /dev/urandom ]; then
    cat /dev/urandom | tr -dc "$charset" | fold -w ${length} | head -n 1
  else
    log "ERROR" "Cannot generate random string: no suitable random source found"
    return 1
  fi
}

# Validate cluster name format
validate_cluster_name() {
  local cluster_name=$1
  
  # OpenShift cluster names must be lowercase alphanumeric with hyphens
  # Must start and end with alphanumeric character
  # Maximum 63 characters
  if [[ ! "$cluster_name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [ ${#cluster_name} -gt 63 ]; then
    log "ERROR" "Invalid cluster name: $cluster_name"
    log "ERROR" "Cluster name must be lowercase alphanumeric with hyphens, start/end with alphanumeric, max 63 chars"
    return 1
  fi
  
  log "DEBUG" "Cluster name validation passed: $cluster_name"
  return 0
}

# Validate base domain format
validate_base_domain() {
  local base_domain=$1
  
  # Basic domain validation
  if [[ ! "$base_domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
    log "ERROR" "Invalid base domain format: $base_domain"
    return 1
  fi
  
  log "DEBUG" "Base domain validation passed: $base_domain"
  return 0
}

# Check if running in GitHub Actions
is_github_actions() {
  [ "${GITHUB_ACTIONS:-false}" = "true" ]
}

# Get GitHub Actions step summary file
get_github_step_summary() {
  echo "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Add content to GitHub Actions step summary
add_to_step_summary() {
  local content=$1
  if is_github_actions; then
    echo "$content" >> "$(get_github_step_summary)"
  fi
}

# Retry a command with exponential backoff
retry_with_backoff() {
  local max_attempts=$1
  local delay=$2
  local command="${@:3}"
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    log "DEBUG" "Attempt $attempt/$max_attempts: $command"
    
    if eval "$command"; then
      log "INFO" "Command succeeded on attempt $attempt"
      return 0
    fi
    
    if [ $attempt -eq $max_attempts ]; then
      log "ERROR" "Command failed after $max_attempts attempts"
      return 1
    fi
    
    log "WARN" "Command failed, retrying in ${delay}s..."
    sleep $delay
    delay=$((delay * 2))  # Exponential backoff
    attempt=$((attempt + 1))
  done
}

# Clean up function to be called on script exit
cleanup() {
  local exit_code=$?
  
  # Remove temporary files
  if [ -n "${TEMP_FILES:-}" ]; then
    log "DEBUG" "Cleaning up temporary files: $TEMP_FILES"
    rm -f $TEMP_FILES
  fi
  
  # Remove temporary directories
  if [ -n "${TEMP_DIRS:-}" ]; then
    log "DEBUG" "Cleaning up temporary directories: $TEMP_DIRS"
    rm -rf $TEMP_DIRS
  fi
  
  if [ $exit_code -ne 0 ]; then
    log "ERROR" "Script exited with error code $exit_code"
  else
    log "INFO" "Script completed successfully"
  fi
  
  exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT

# Export functions for use in other scripts
export -f log command_exists wait_for validate_env_vars validate_files validate_directories
export -f ensure_directory backup_file generate_random_string validate_cluster_name validate_base_domain
export -f is_github_actions get_github_step_summary add_to_step_summary retry_with_backoff
