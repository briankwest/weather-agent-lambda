#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Lambda Setup Script
# ==============================================

FUNCTION_NAME="weather-agent"
REGION="us-east-1"
ROLE_NAME="${FUNCTION_NAME}-execution-role"

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
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure'."
        exit 1
    fi
    
    log_success "AWS CLI configured"
}

create_execution_role() {
    log_info "Creating Lambda execution role..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_success "Execution role already exists"
        return 0
    fi
    
    # Create trust policy for Lambda
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
    
    # Create the role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$trust_policy" \
        --description "Execution role for SignalWire Weather Agent Lambda function"
    
    log_success "Execution role created"
}

attach_basic_policies() {
    log_info "Attaching basic execution policies..."
    
    # Attach AWS managed policy for basic Lambda execution
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    log_success "Basic execution policy attached"
}

create_function_url_policy() {
    log_info "Creating function URL policy..."
    
    local policy_name="${FUNCTION_NAME}-url-policy"
    
    # Check if policy already exists
    if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$policy_name" &>/dev/null; then
        log_success "Function URL policy already exists"
        return 0
    fi
    
    # Create policy for function URL access
    local url_policy=$(cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunctionUrl"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)
    
    # Attach inline policy to role
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$policy_name" \
        --policy-document "$url_policy"
    
    log_success "Function URL policy created"
}

setup_function_url_permissions() {
    log_info "Setting up function URL permissions..."
    
    # Get account ID
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local function_arn="arn:aws:lambda:${REGION}:${account_id}:function:${FUNCTION_NAME}"
    
    # Add permission for function URL to invoke the function
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id "FunctionURLAllowPublicAccess" \
        --action "lambda:InvokeFunctionUrl" \
        --principal "*" \
        --function-url-auth-type "NONE" \
        --region "$REGION" 2>/dev/null || {
        log_warning "Permission may already exist (this is normal)"
    }
    
    log_success "Function URL permissions configured"
}

create_resource_policy() {
    log_info "Creating resource-based policy..."
    
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    
    # Create resource-based policy to allow public access via function URL
    local resource_policy=$(cat << EOF
{
  "Version": "2012-10-17",
  "Id": "default",
  "Statement": [
    {
      "Sid": "FunctionURLAllowPublicAccess",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "lambda:InvokeFunctionUrl",
      "Resource": "arn:aws:lambda:${REGION}:${account_id}:function:${FUNCTION_NAME}",
      "Condition": {
        "StringEquals": {
          "lambda:FunctionUrlAuthType": "NONE"
        }
      }
    }
  ]
}
EOF
)
    
    # Apply the resource policy
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id "FunctionURLPublicAccess" \
        --action "lambda:InvokeFunctionUrl" \
        --principal "*" \
        --region "$REGION" 2>/dev/null || {
        log_warning "Resource policy may already exist"
    }
    
    log_success "Resource-based policy created"
}

wait_for_propagation() {
    log_info "Waiting for IAM changes to propagate..."
    sleep 10
    log_success "IAM propagation complete"
}

verify_setup() {
    log_info "Verifying setup..."
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo "  ✅ Execution role exists"
    else
        echo "  ❌ Execution role missing"
        return 1
    fi
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        echo "  ✅ Lambda function exists"
    else
        echo "  ❌ Lambda function missing"
        return 1
    fi
    
    # Check if function URL exists
    if aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        echo "  ✅ Function URL configured"
    else
        echo "  ❌ Function URL missing"
        return 1
    fi
    
    log_success "Setup verification complete"
}

show_summary() {
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    local function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text 2>/dev/null || echo "Not configured")
    
    echo ""
    log_success "Lambda Setup Summary"
    echo "===================="
    echo "  📦 Function: $FUNCTION_NAME"
    echo "  🌍 Region: $REGION"
    echo "  👤 Account: $account_id"
    echo "  🔑 Role: $ROLE_NAME"
    echo "  🌐 Function URL: $function_url"
    echo ""
    echo "🔗 Test endpoints:"
    if [ "$function_url" != "Not configured" ]; then
        echo "  Health: ${function_url}health"
        echo "  SWML: $function_url"
    fi
    echo ""
}

main() {
    echo "🌤️  SignalWire Weather Agent - Lambda Setup"
    echo "==========================================="
    echo ""
    
    check_aws_cli
    create_execution_role
    attach_basic_policies
    create_function_url_policy
    wait_for_propagation
    
    # Only set up function-specific permissions if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        setup_function_url_permissions
        create_resource_policy
        wait_for_propagation
        verify_setup
    else
        log_warning "Lambda function not found. Deploy the function first, then run this script again."
    fi
    
    show_summary
    
    log_success "Lambda setup complete!"
    echo "💡 Next step: Deploy your function with 'make deploy'"
}

# Run main function
main "$@" 