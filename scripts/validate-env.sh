#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Environment Validation
# =================================================

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

check_required_tools() {
    log_info "Checking required tools..."
    
    local missing_tools=()
    
    # Check essential tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        missing_tools+=("pip")
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All required tools are installed"
        return 0
    else
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Installation instructions:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "aws-cli")
                    echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    ;;
                "docker")
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                "jq")
                    echo "  jq: brew install jq (macOS) or sudo apt-get install jq (Ubuntu)"
                    ;;
                "curl")
                    echo "  curl: Usually pre-installed, check your package manager"
                    ;;
                "python3")
                    echo "  Python 3: https://www.python.org/downloads/"
                    ;;
                "pip")
                    echo "  pip: python3 -m ensurepip --upgrade"
                    ;;
            esac
        done
        return 1
    fi
}

check_aws_configuration() {
    log_info "Checking AWS configuration..."
    
    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not installed"
        return 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        echo "  Run: aws configure"
        echo "  Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
        return 1
    fi
    
    # Get AWS account info
    local account_id=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
    local user_arn=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    local region=$(aws configure get region 2>/dev/null || echo "not set")
    
    echo "  🔑 Account ID: $account_id"
    echo "  👤 User/Role: $user_arn"
    echo "  🌍 Default Region: $region"
    
    if [ "$region" = "not set" ]; then
        log_warning "Default region not set, will use us-east-1"
    fi
    
    log_success "AWS configuration valid"
    return 0
}

check_docker_status() {
    log_info "Checking Docker status..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running"
        echo "  Start Docker Desktop or run: sudo systemctl start docker"
        return 1
    fi
    
    # Check Docker version
    local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    echo "  🐳 Docker Version: $docker_version"
    
    # Test Docker functionality
    if docker run --rm hello-world &> /dev/null; then
        log_success "Docker is working correctly"
        return 0
    else
        log_error "Docker test failed"
        return 1
    fi
}

check_python_environment() {
    log_info "Checking Python environment..."
    
    # Check Python version
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version | cut -d' ' -f2)
        echo "  🐍 Python Version: $python_version"
        
        # Check if version is 3.8+
        local major=$(echo "$python_version" | cut -d'.' -f1)
        local minor=$(echo "$python_version" | cut -d'.' -f2)
        
        if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -lt 8 ]); then
            log_warning "Python 3.8+ recommended (current: $python_version)"
        fi
    else
        log_error "Python 3 not found"
        return 1
    fi
    
    # Check pip
    if command -v pip3 &> /dev/null; then
        local pip_version=$(pip3 --version | cut -d' ' -f2)
        echo "  📦 pip Version: $pip_version"
    elif command -v pip &> /dev/null; then
        local pip_version=$(pip --version | cut -d' ' -f2)
        echo "  📦 pip Version: $pip_version"
    else
        log_error "pip not found"
        return 1
    fi
    
    # Check if signalwire-agents can be imported
    if python3 -c "import signalwire_agents" 2>/dev/null; then
        local sw_version=$(python3 -c "import signalwire_agents; print(signalwire_agents.__version__)" 2>/dev/null || echo "unknown")
        echo "  🎯 SignalWire Agents: $sw_version"
    else
        log_warning "SignalWire Agents not installed (will be installed during build)"
    fi
    
    log_success "Python environment ready"
    return 0
}

check_environment_variables() {
    log_info "Checking environment variables..."
    
    local issues=0
    
    # Check required variables
    echo "  Required variables:"
    
    if [ -n "${WEATHERAPI_KEY:-}" ]; then
        echo "    ✅ WEATHERAPI_KEY: ***set*** (length: ${#WEATHERAPI_KEY})"
    else
        echo "    ❌ WEATHERAPI_KEY: not set"
        ((issues++))
    fi
    
    # Check optional variables with defaults
    echo "  Optional variables (with defaults):"
    
    local auth_user="${SWML_BASIC_AUTH_USER:-dev}"
    local auth_pass="${SWML_BASIC_AUTH_PASSWORD:-w00t}"
    local local_tz="${LOCAL_TZ:-America/Los_Angeles}"
    
    echo "    🔧 SWML_BASIC_AUTH_USER: $auth_user"
    echo "    🔧 SWML_BASIC_AUTH_PASSWORD: ***set*** (length: ${#auth_pass})"
    echo "    🔧 LOCAL_TZ: $local_tz"
    
    if [ $issues -eq 0 ]; then
        log_success "Environment variables configured"
        return 0
    else
        log_error "$issues required environment variables missing"
        echo ""
        echo "Set missing variables:"
        if [ -z "${WEATHERAPI_KEY:-}" ]; then
            echo "  export WEATHERAPI_KEY='your-api-key-here'"
            echo "  Get your key at: https://www.weatherapi.com/"
        fi
        return 1
    fi
}

check_project_structure() {
    log_info "Checking project structure..."
    
    local missing_files=()
    
    # Check essential files
    if [ ! -f "src/hybrid_lambda_handler.py" ]; then
        missing_files+=("src/hybrid_lambda_handler.py")
    fi
    
    if [ ! -f "Makefile" ]; then
        missing_files+=("Makefile")
    fi
    
    if [ ! -f "requirements.txt" ]; then
        missing_files+=("requirements.txt")
    fi
    
    # Check scripts directory
    if [ ! -d "scripts" ]; then
        missing_files+=("scripts/")
    else
        for script in build.sh deploy.sh logs.sh status.sh demo.sh validate-env.sh; do
            if [ ! -f "scripts/$script" ]; then
                missing_files+=("scripts/$script")
            fi
        done
    fi
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        log_success "Project structure is complete"
        return 0
    else
        log_error "Missing files: ${missing_files[*]}"
        return 1
    fi
}

show_next_steps() {
    echo ""
    log_info "🚀 Next Steps"
    echo "============="
    echo ""
    echo "1. Set your WeatherAPI key:"
    echo "   export WEATHERAPI_KEY='your-api-key-here'"
    echo ""
    echo "2. Build the deployment package:"
    echo "   make build"
    echo ""
    echo "3. Deploy to AWS Lambda:"
    echo "   make deploy"
    echo ""
    echo "4. Run the interactive demo:"
    echo "   make demo"
    echo ""
    echo "5. Monitor your deployment:"
    echo "   make status"
    echo "   make logs"
    echo ""
}

main() {
    echo "🌤️  SignalWire Weather Agent - Environment Validation"
    echo "====================================================="
    echo ""
    
    local overall_status=0
    
    # Run all checks
    if ! check_required_tools; then
        ((overall_status++))
    fi
    echo ""
    
    if ! check_aws_configuration; then
        ((overall_status++))
    fi
    echo ""
    
    if ! check_docker_status; then
        ((overall_status++))
    fi
    echo ""
    
    if ! check_python_environment; then
        ((overall_status++))
    fi
    echo ""
    
    if ! check_environment_variables; then
        ((overall_status++))
    fi
    echo ""
    
    if ! check_project_structure; then
        ((overall_status++))
    fi
    echo ""
    
    # Overall result
    if [ $overall_status -eq 0 ]; then
        log_success "🎉 Environment validation passed!"
        echo "Your system is ready for SignalWire Weather Agent deployment."
        show_next_steps
    else
        log_error "❌ Environment validation failed ($overall_status issues)"
        echo "Please fix the issues above before proceeding."
        exit 1
    fi
}

# Run main function
main "$@" 