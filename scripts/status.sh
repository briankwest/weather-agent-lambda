#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Status Script
# ========================================

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

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found"
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        return 1
    fi
    
    log_success "AWS CLI configured"
    return 0
}

check_function_exists() {
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_success "Lambda function exists"
        return 0
    else
        log_error "Lambda function not found"
        return 1
    fi
}

get_function_info() {
    local config=$(aws lambda get-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local state=$(echo "$config" | jq -r '.State')
        local update_status=$(echo "$config" | jq -r '.LastUpdateStatus')
        local runtime=$(echo "$config" | jq -r '.Runtime')
        local memory=$(echo "$config" | jq -r '.MemorySize')
        local timeout=$(echo "$config" | jq -r '.Timeout')
        local last_modified=$(echo "$config" | jq -r '.LastModified')
        
        echo "  📦 Function: $FUNCTION_NAME"
        echo "  🌍 Region: $REGION"
        echo "  🔄 State: $state"
        echo "  📊 Update Status: $update_status"
        echo "  🐍 Runtime: $runtime"
        echo "  💾 Memory: ${memory}MB"
        echo "  ⏱️  Timeout: ${timeout}s"
        echo "  📅 Last Modified: $last_modified"
        
        if [ "$state" = "Active" ] && [ "$update_status" = "Successful" ]; then
            log_success "Function is healthy"
            return 0
        else
            log_warning "Function may have issues"
            return 1
        fi
    else
        log_error "Could not get function configuration"
        return 1
    fi
}

check_function_url() {
    local url_config=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local function_url=$(echo "$url_config" | jq -r '.FunctionUrl')
        local auth_type=$(echo "$url_config" | jq -r '.AuthType')
        local creation_time=$(echo "$url_config" | jq -r '.CreationTime')
        
        echo "  🌐 Function URL: $function_url"
        echo "  🔐 Auth Type: $auth_type"
        echo "  📅 Created: $creation_time"
        
        log_success "Function URL configured"
        return 0
    else
        log_error "Function URL not configured"
        return 1
    fi
}

check_environment_variables() {
    local config=$(aws lambda get-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local env_vars=$(echo "$config" | jq -r '.Environment.Variables // {}')
        
        echo "  Environment Variables:"
        
        # Check required variables
        local auth_user=$(echo "$env_vars" | jq -r '.SWML_BASIC_AUTH_USER // "not set"')
        local auth_pass=$(echo "$env_vars" | jq -r '.SWML_BASIC_AUTH_PASSWORD // "not set"')
        local local_tz=$(echo "$env_vars" | jq -r '.LOCAL_TZ // "not set"')
        local weather_key=$(echo "$env_vars" | jq -r '.WEATHERAPI_KEY // "not set"')
        local lambda_url=$(echo "$env_vars" | jq -r '.AWS_LAMBDA_FUNCTION_URL // "not set"')
        
        echo "    🔑 SWML_BASIC_AUTH_USER: $auth_user"
        echo "    🔑 SWML_BASIC_AUTH_PASSWORD: $([ "$auth_pass" != "not set" ] && echo "***set***" || echo "not set")"
        echo "    🌍 LOCAL_TZ: $local_tz"
        echo "    🌤️  WEATHERAPI_KEY: $([ "$weather_key" != "not set" ] && echo "***set***" || echo "not set")"
        echo "    🔗 AWS_LAMBDA_FUNCTION_URL: $([ "$lambda_url" != "not set" ] && echo "***set***" || echo "not set")"
        
        # Check if critical variables are set
        local issues=0
        if [ "$auth_user" = "not set" ]; then
            log_warning "SWML_BASIC_AUTH_USER not set"
            ((issues++))
        fi
        if [ "$auth_pass" = "not set" ]; then
            log_warning "SWML_BASIC_AUTH_PASSWORD not set"
            ((issues++))
        fi
        if [ "$weather_key" = "not set" ]; then
            log_warning "WEATHERAPI_KEY not set - weather functions will not work"
            ((issues++))
        fi
        
        if [ $issues -eq 0 ]; then
            log_success "Environment variables configured"
            return 0
        else
            log_warning "$issues environment variable issues found"
            return 1
        fi
    else
        log_error "Could not get environment variables"
        return 1
    fi
}

test_endpoints() {
    local function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text 2>/dev/null)
    
    if [ -z "$function_url" ]; then
        log_error "Could not get function URL for testing"
        return 1
    fi
    
    echo "  Testing Endpoints:"
    
    # Test health endpoint
    local health_status=$(curl -s -w "%{http_code}" -o /dev/null "${function_url}health" 2>/dev/null || echo "000")
    if [ "$health_status" = "200" ]; then
        echo "    ✅ Health endpoint: OK (HTTP $health_status)"
    else
        echo "    ❌ Health endpoint: Failed (HTTP $health_status)"
    fi
    
    # Test SWML endpoint (requires auth)
    local config=$(aws lambda get-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local env_vars=$(echo "$config" | jq -r '.Environment.Variables // {}')
        local auth_user=$(echo "$env_vars" | jq -r '.SWML_BASIC_AUTH_USER // ""')
        local auth_pass=$(echo "$env_vars" | jq -r '.SWML_BASIC_AUTH_PASSWORD // ""')
        
        if [ -n "$auth_user" ] && [ -n "$auth_pass" ]; then
            local swml_status=$(curl -s -w "%{http_code}" -o /dev/null \
                -u "$auth_user:$auth_pass" \
                "$function_url" 2>/dev/null || echo "000")
            
            if [ "$swml_status" = "200" ]; then
                echo "    ✅ SWML endpoint: OK (HTTP $swml_status)"
            else
                echo "    ❌ SWML endpoint: Failed (HTTP $swml_status)"
            fi
        else
            echo "    ⚠️  SWML endpoint: Cannot test (auth credentials not set)"
        fi
    fi
    
    log_success "Endpoint testing complete"
}

get_recent_metrics() {
    log_info "Recent metrics (last 24 hours):"
    
    # Get invocation count
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%S")
    local start_time
    if command -v gdate &> /dev/null; then
        start_time=$(gdate -u -d "24 hours ago" +"%Y-%m-%dT%H:%M:%S")
    else
        start_time=$(date -u -v-24H +"%Y-%m-%dT%H:%M:%S")
    fi
    
    local invocations=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 86400 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    local errors=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Errors \
        --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period 86400 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    echo "  📊 Invocations: ${invocations:-0}"
    echo "  ❌ Errors: ${errors:-0}"
    
    if [ "${errors:-0}" = "0" ]; then
        log_success "No errors in last 24 hours"
    else
        log_warning "${errors} errors in last 24 hours"
    fi
}

main() {
    echo "🌤️  SignalWire Weather Agent - Status"
    echo "====================================="
    echo ""
    
    local overall_status=0
    
    # Check AWS CLI
    if ! check_aws_cli; then
        ((overall_status++))
    fi
    echo ""
    
    # Check if function exists
    if ! check_function_exists; then
        log_error "Function not deployed. Run 'make deploy' to deploy."
        exit 1
    fi
    echo ""
    
    # Get function information
    log_info "Function Configuration:"
    if ! get_function_info; then
        ((overall_status++))
    fi
    echo ""
    
    # Check function URL
    log_info "Function URL:"
    if ! check_function_url; then
        ((overall_status++))
    fi
    echo ""
    
    # Check environment variables
    log_info "Environment Variables:"
    if ! check_environment_variables; then
        ((overall_status++))
    fi
    echo ""
    
    # Test endpoints
    log_info "Endpoint Health:"
    test_endpoints
    echo ""
    
    # Get metrics
    get_recent_metrics
    echo ""
    
    # Overall status
    if [ $overall_status -eq 0 ]; then
        log_success "Overall Status: Healthy ✨"
        echo "💡 Your SignalWire Weather Agent is ready to use!"
    else
        log_warning "Overall Status: Issues Found ($overall_status)"
        echo "💡 Run 'make deploy' to fix configuration issues."
    fi
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ jq not found. Please install jq to use this script."
    echo "   macOS: brew install jq"
    echo "   Ubuntu: sudo apt-get install jq"
    exit 1
fi

# Run main function
main "$@" 