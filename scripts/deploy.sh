#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Deployment Script
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FUNCTION_NAME="weather-agent"
REGION="us-east-1"
PACKAGE_NAME="signalwire-deployment.zip"

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

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set defaults
    export SWML_BASIC_AUTH_USER="${SWML_BASIC_AUTH_USER:-dev}"
    export SWML_BASIC_AUTH_PASSWORD="${SWML_BASIC_AUTH_PASSWORD:-w00t}"
    export LOCAL_TZ="${LOCAL_TZ:-America/Los_Angeles}"
    
    echo "  🔧 SWML_BASIC_AUTH_USER: $SWML_BASIC_AUTH_USER"
    echo "  🔧 SWML_BASIC_AUTH_PASSWORD: (length: ${#SWML_BASIC_AUTH_PASSWORD})"
    echo "  🔧 LOCAL_TZ: $LOCAL_TZ"
    
    if [ -n "${WEATHERAPI_KEY:-}" ]; then
        echo "  🔧 WEATHERAPI_KEY: (length: ${#WEATHERAPI_KEY})"
    else
        log_warning "WEATHERAPI_KEY not set - weather functions will not work"
    fi
    
    log_success "Environment configured"
}

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure'."
        exit 1
    fi
    
    # Check deployment package
    if [ ! -f "$PROJECT_ROOT/$PACKAGE_NAME" ]; then
        log_error "Deployment package not found: $PACKAGE_NAME"
        log_info "Run 'make build' first to create the package."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

ensure_lambda_function() {
    log_info "Ensuring Lambda function exists..."
    
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_info "Function doesn't exist, creating..."
        
        # Create execution role if it doesn't exist
        local role_name="${FUNCTION_NAME}-execution-role"
        local role_arn
        
        if ! aws iam get-role --role-name "$role_name" &>/dev/null; then
            log_info "Creating IAM role..."
            
            # Create trust policy
            local trust_policy=$(cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
            
            aws iam create-role \
                --role-name "$role_name" \
                --assume-role-policy-document "$trust_policy" \
                --description "Execution role for SignalWire Weather Agent"
            
            # Attach basic execution policy
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            
            log_success "IAM role created"
            
            # Wait for role to be available
            log_info "Waiting for role to be available..."
            sleep 10
        fi
        
        role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
        
        # Create Lambda function
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.11 \
            --role "$role_arn" \
            --handler hybrid_lambda_handler.lambda_handler \
            --zip-file "fileb://$PROJECT_ROOT/$PACKAGE_NAME" \
            --timeout 30 \
            --memory-size 512 \
            --description "SignalWire AI Weather Agent" \
            --region "$REGION"
        
        # Create function URL
        aws lambda create-function-url-config \
            --function-name "$FUNCTION_NAME" \
            --auth-type NONE \
            --region "$REGION"
        
        log_success "Lambda function created"
    else
        log_success "Lambda function exists"
    fi
}

update_function() {
    log_info "Updating function code..."
    
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$PROJECT_ROOT/$PACKAGE_NAME" \
        --region "$REGION"
    
    log_success "Function code updated"
}

update_environment_variables() {
    log_info "Updating environment variables..."
    
    # Create environment variables JSON
    local env_vars=$(cat << EOF
{
  "Variables": {
    "SWML_BASIC_AUTH_USER": "$SWML_BASIC_AUTH_USER",
    "SWML_BASIC_AUTH_PASSWORD": "$SWML_BASIC_AUTH_PASSWORD",
    "LOCAL_TZ": "$LOCAL_TZ",
    "WEATHERAPI_KEY": "${WEATHERAPI_KEY:-}"
  }
}
EOF
)
    
    # Update function configuration
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "$env_vars" \
        --region "$REGION" \
        --timeout 30 \
        --memory-size 512
    
    log_success "Environment variables updated"
}

wait_for_function_ready() {
    log_info "Waiting for function to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local state=$(aws lambda get-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --region "$REGION" \
            --query 'State' \
            --output text)
        
        local update_status=$(aws lambda get-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --region "$REGION" \
            --query 'LastUpdateStatus' \
            --output text)
        
        if [ "$state" = "Active" ] && [ "$update_status" = "Successful" ]; then
            log_success "Function is ready"
            return 0
        fi
        
        echo "  Attempt $attempt/$max_attempts: State=$state, UpdateStatus=$update_status"
        sleep 3
        ((attempt++))
    done
    
    log_error "Timeout waiting for function to be ready"
    exit 1
}

setup_function_url() {
    log_info "Setting up function URL with authentication..."
    
    # Get function URL
    local function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$function_url" ]; then
        log_error "Could not get function URL"
        exit 1
    fi
    
    # Create authenticated URL
    local url_without_protocol=$(echo "$function_url" | sed 's|https://||')
    local auth_url="https://${url_without_protocol}"
    
    # Export for current session
    export AWS_LAMBDA_FUNCTION_URL="$auth_url"
    
    # Save to file for future use
    echo "export AWS_LAMBDA_FUNCTION_URL=\"$auth_url\"" > "$PROJECT_ROOT/.env.lambda"
    
    # Update Lambda environment with the authenticated URL
    local env_vars=$(cat << EOF
{
  "Variables": {
    "SWML_BASIC_AUTH_USER": "$SWML_BASIC_AUTH_USER",
    "SWML_BASIC_AUTH_PASSWORD": "$SWML_BASIC_AUTH_PASSWORD",
    "LOCAL_TZ": "$LOCAL_TZ",
    "WEATHERAPI_KEY": "${WEATHERAPI_KEY:-}",
    "AWS_LAMBDA_FUNCTION_URL": "$auth_url"
  }
}
EOF
)
    
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "$env_vars" \
        --region "$REGION"
    
    echo "  🌐 Function URL: $function_url"
    echo "  🔐 Authenticated URL: $auth_url"
    
    log_success "Function URL configured"
}

test_deployment() {
    log_info "Testing deployment..."
    
    local function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text)
    
    # Test health endpoint
    echo "  🧪 Testing health endpoint..."
    local health_status=$(curl -s -w "%{http_code}" -o /dev/null "${function_url}health" || echo "000")
    
    if [ "$health_status" = "200" ]; then
        echo "    ✅ Health check: OK"
    else
        echo "    ❌ Health check: Failed (HTTP $health_status)"
    fi
    
    # Test SWML endpoint
    echo "  🧪 Testing SWML endpoint..."
    local swml_status=$(curl -s -w "%{http_code}" -o /dev/null \
        -u "$SWML_BASIC_AUTH_USER:$SWML_BASIC_AUTH_PASSWORD" \
        "$function_url" || echo "000")
    
    if [ "$swml_status" = "200" ]; then
        echo "    ✅ SWML endpoint: OK"
    else
        echo "    ❌ SWML endpoint: Failed (HTTP $swml_status)"
    fi
    
    log_success "Deployment testing complete"
}

show_deployment_summary() {
    local function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text)
    
    echo ""
    log_success "Deployment Summary"
    echo "=================="
    echo "  📦 Function: $FUNCTION_NAME"
    echo "  🌍 Region: $REGION"
    echo "  🌐 URL: $function_url"
    echo "  🔐 Auth URL: $AWS_LAMBDA_FUNCTION_URL"
    echo ""
    echo "🔗 Available Endpoints:"
    echo "  Health: ${function_url}health"
    echo "  SWML: $function_url"
    echo "  SWAIG: ${function_url}swaig"
    echo ""
    echo "🔐 Authentication: Basic Auth ($SWML_BASIC_AUTH_USER:$SWML_BASIC_AUTH_PASSWORD)"
    echo "📁 Environment saved to: .env.lambda"
    echo ""
    echo "💡 Next steps:"
    echo "  • Test: make demo"
    echo "  • Logs: make logs"
    echo "  • Status: make status"
}

main() {
    echo "🌤️  SignalWire Weather Agent - Deploy"
    echo "====================================="
    echo ""
    
    setup_environment
    validate_prerequisites
    ensure_lambda_function
    update_function
    update_environment_variables
    wait_for_function_ready
    setup_function_url
    wait_for_function_ready  # Wait again after env update
    test_deployment
    show_deployment_summary
    
    log_success "Deployment complete!"
}

# Run main function
main "$@" 