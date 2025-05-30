#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Logs Script
# ======================================

FUNCTION_NAME="weather-agent"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

show_help() {
    echo "🌤️  SignalWire Weather Agent - Logs"
    echo "==================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --follow   Follow logs in real-time"
    echo "  -e, --errors   Show only error logs"
    echo "  -t, --tail N   Show last N minutes (default: 10)"
    echo "  -s, --since    Show logs since timestamp (e.g., '2024-01-01 12:00')"
    echo ""
    echo "Examples:"
    echo "  $0                    # Show last 10 minutes"
    echo "  $0 -t 30             # Show last 30 minutes"
    echo "  $0 -f                # Follow logs in real-time"
    echo "  $0 -e                # Show only errors"
    echo "  $0 -s '1 hour ago'   # Show logs from 1 hour ago"
}

get_log_group() {
    echo "/aws/lambda/$FUNCTION_NAME"
}

validate_function() {
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_error "Lambda function '$FUNCTION_NAME' not found in region '$REGION'"
        log_info "Make sure the function is deployed: make deploy"
        exit 1
    fi
}

show_recent_logs() {
    local minutes=${1:-10}
    local log_group=$(get_log_group)
    
    log_info "Showing logs from last $minutes minutes..."
    
    # Calculate start time
    local start_time
    if command -v gdate &> /dev/null; then
        # GNU date (installed via brew on macOS)
        start_time=$(gdate -d "$minutes minutes ago" --iso-8601=seconds)
    else
        # BSD date (default on macOS)
        start_time=$(date -v-${minutes}M +"%Y-%m-%dT%H:%M:%S")
    fi
    
    aws logs tail "$log_group" \
        --region "$REGION" \
        --since "$start_time" \
        --format short
}

follow_logs() {
    local log_group=$(get_log_group)
    
    log_info "Following logs in real-time (Ctrl+C to stop)..."
    echo ""
    
    aws logs tail "$log_group" \
        --region "$REGION" \
        --follow \
        --format short
}

show_error_logs() {
    local minutes=${1:-60}
    local log_group=$(get_log_group)
    
    log_info "Showing error logs from last $minutes minutes..."
    
    # Calculate start time
    local start_time
    if command -v gdate &> /dev/null; then
        start_time=$(gdate -d "$minutes minutes ago" --iso-8601=seconds)
    else
        start_time=$(date -v-${minutes}M +"%Y-%m-%dT%H:%M:%S")
    fi
    
    aws logs tail "$log_group" \
        --region "$REGION" \
        --since "$start_time" \
        --format short \
        --filter-pattern "ERROR"
}

show_logs_since() {
    local since_time="$1"
    local log_group=$(get_log_group)
    
    log_info "Showing logs since: $since_time"
    
    aws logs tail "$log_group" \
        --region "$REGION" \
        --since "$since_time" \
        --format short
}

main() {
    local follow=false
    local errors_only=false
    local tail_minutes=10
    local since_time=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--follow)
                follow=true
                shift
                ;;
            -e|--errors)
                errors_only=true
                shift
                ;;
            -t|--tail)
                tail_minutes="$2"
                shift 2
                ;;
            -s|--since)
                since_time="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate AWS CLI and function
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    validate_function
    
    # Execute based on options
    if [ "$follow" = true ]; then
        follow_logs
    elif [ "$errors_only" = true ]; then
        show_error_logs "$tail_minutes"
    elif [ -n "$since_time" ]; then
        show_logs_since "$since_time"
    else
        show_recent_logs "$tail_minutes"
    fi
}

# Run main function
main "$@" 