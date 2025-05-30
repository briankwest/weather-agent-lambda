#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Interactive Demo
# ===========================================

FUNCTION_NAME="weather-agent"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_demo() {
    echo -e "${CYAN}🎬 $1${NC}"
}

log_result() {
    echo -e "${MAGENTA}📋 $1${NC}"
}

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║           🌤️  SignalWire Weather Agent Demo                  ║
    ║                                                              ║
    ║     Experience AI-powered weather information in action!     ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_error "Lambda function not found. Please deploy first:"
        echo "  make deploy"
        exit 1
    fi
    
    # Get function URL
    FUNCTION_URL=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" \
        --query 'FunctionUrl' \
        --output text 2>/dev/null)
    
    if [ -z "$FUNCTION_URL" ]; then
        log_error "Function URL not configured"
        exit 1
    fi
    
    # Get auth credentials
    local config=$(aws lambda get-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION" 2>/dev/null)
    
    AUTH_USER=$(echo "$config" | jq -r '.Environment.Variables.SWML_BASIC_AUTH_USER // "dev"')
    AUTH_PASS=$(echo "$config" | jq -r '.Environment.Variables.SWML_BASIC_AUTH_PASSWORD // "w00t"')
    
    log_success "Deployment validated"
    echo "  🌐 Function URL: $FUNCTION_URL"
    echo "  🔐 Auth: $AUTH_USER:***"
}

test_health_endpoint() {
    log_demo "Testing health endpoint..."
    
    local response=$(curl -s "${FUNCTION_URL}health" 2>/dev/null || echo "")
    local status=$(curl -s -w "%{http_code}" -o /dev/null "${FUNCTION_URL}health" 2>/dev/null || echo "000")
    
    if [ "$status" = "200" ]; then
        log_success "Health check passed (HTTP $status)"
        echo ""
        log_result "SWML Configuration Preview:"
        echo "$response" | jq -r '.sections.main[1].ai.SWAIG.functions[0] | "  Function: \(.function)\n  Description: \(.purpose)\n  Parameters: \(.argument.properties | keys | join(", "))"' 2>/dev/null || echo "  SWML document received"
    else
        log_error "Health check failed (HTTP $status)"
        return 1
    fi
}

test_swml_generation() {
    log_demo "Testing SWML generation..."
    
    local response=$(curl -s -u "$AUTH_USER:$AUTH_PASS" "$FUNCTION_URL" 2>/dev/null || echo "")
    local status=$(curl -s -w "%{http_code}" -o /dev/null -u "$AUTH_USER:$AUTH_PASS" "$FUNCTION_URL" 2>/dev/null || echo "000")
    
    if [ "$status" = "200" ]; then
        log_success "SWML generation successful (HTTP $status)"
        echo ""
        log_result "Agent Configuration:"
        
        # Extract key information from SWML
        local agent_name=$(echo "$response" | jq -r '.sections.main[1].ai.params.name // "Unknown"' 2>/dev/null)
        local functions_count=$(echo "$response" | jq -r '.sections.main[1].ai.SWAIG.functions | length' 2>/dev/null || echo "0")
        local webhook_url=$(echo "$response" | jq -r '.sections.main[1].ai.SWAIG.functions[0].web_hook_url // "Not set"' 2>/dev/null)
        
        echo "  🤖 Agent Name: $agent_name"
        echo "  🔧 Functions Available: $functions_count"
        echo "  🌐 Webhook URL: $(echo "$webhook_url" | sed 's/:[^@]*@/:***@/')"
        
        # Show function details
        echo ""
        log_result "Available Functions:"
        echo "$response" | jq -r '.sections.main[1].ai.SWAIG.functions[] | "  • \(.function): \(.purpose)"' 2>/dev/null || echo "  • get_weather: Weather information function"
    else
        log_error "SWML generation failed (HTTP $status)"
        return 1
    fi
}

demo_weather_function() {
    local location="$1"
    local days="${2:-1}"
    local include_alerts="${3:-false}"
    
    log_demo "Testing weather function for: $location"
    
    # Prepare SWAIG function call
    local payload=$(cat << EOF
{
  "function": "get_weather",
  "argument": {
    "parsed": [{
      "location": "$location",
      "days": $days,
      "include_alerts": $include_alerts
    }]
  },
  "call_id": "demo-$(date +%s)"
}
EOF
)
    
    echo "  📤 Sending request..."
    local response=$(curl -s -X POST "${FUNCTION_URL}swaig" \
        -u "$AUTH_USER:$AUTH_PASS" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo "")
    
    local status=$(curl -s -w "%{http_code}" -o /dev/null -X POST "${FUNCTION_URL}swaig" \
        -u "$AUTH_USER:$AUTH_PASS" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo "000")
    
    if [ "$status" = "200" ]; then
        log_success "Weather function executed successfully (HTTP $status)"
        echo ""
        log_result "Weather Response:"
        
        # Extract and format the response
        local weather_text=$(echo "$response" | jq -r '.response // .message // "No weather data"' 2>/dev/null)
        echo "$weather_text" | sed 's/^/  /'
        
        # Show any actions
        local actions=$(echo "$response" | jq -r '.action // empty' 2>/dev/null)
        if [ -n "$actions" ]; then
            echo ""
            log_result "Actions Triggered:"
            echo "$actions" | jq -r 'to_entries[] | "  • \(.key): \(.value)"' 2>/dev/null || echo "  • Global data updated"
        fi
    else
        log_error "Weather function failed (HTTP $status)"
        if [ -n "$response" ]; then
            echo "  Response: $response"
        fi
        return 1
    fi
}

interactive_demo() {
    echo ""
    log_demo "🎯 Interactive Weather Demo"
    echo "=========================="
    echo ""
    
    while true; do
        echo -e "${CYAN}Choose a demo option:${NC}"
        echo "  1) New York current weather"
        echo "  2) London 3-day forecast"
        echo "  3) Tokyo with weather alerts"
        echo "  4) Custom location"
        echo "  5) Show deployment status"
        echo "  6) View recent logs"
        echo "  7) Exit demo"
        echo ""
        read -p "Enter your choice (1-7): " choice
        
        case $choice in
            1)
                echo ""
                demo_weather_function "New York, NY" 1 false
                ;;
            2)
                echo ""
                demo_weather_function "London, UK" 3 false
                ;;
            3)
                echo ""
                demo_weather_function "Tokyo, Japan" 1 true
                ;;
            4)
                echo ""
                read -p "Enter location: " custom_location
                read -p "Number of days (1-10, default 1): " custom_days
                read -p "Include alerts? (y/n, default n): " custom_alerts
                
                custom_days=${custom_days:-1}
                custom_alerts_bool="false"
                if [[ "$custom_alerts" =~ ^[Yy] ]]; then
                    custom_alerts_bool="true"
                fi
                
                echo ""
                demo_weather_function "$custom_location" "$custom_days" "$custom_alerts_bool"
                ;;
            5)
                echo ""
                log_demo "Running status check..."
                ./scripts/status.sh
                ;;
            6)
                echo ""
                log_demo "Showing recent logs..."
                ./scripts/logs.sh -t 5
                ;;
            7)
                echo ""
                log_demo "Demo completed! 🎉"
                echo ""
                echo "💡 Next steps:"
                echo "  • Integrate with SignalWire Voice/SMS"
                echo "  • Customize the agent personality"
                echo "  • Add more weather functions"
                echo "  • Monitor with: make logs"
                echo ""
                exit 0
                ;;
            *)
                log_warning "Invalid choice. Please enter 1-7."
                ;;
        esac
        
        echo ""
        echo "Press Enter to continue..."
        read
        echo ""
    done
}

show_integration_examples() {
    echo ""
    log_demo "🔗 Integration Examples"
    echo "======================"
    echo ""
    
    echo -e "${CYAN}SignalWire Voice Integration:${NC}"
    cat << EOF
  Use this agent in your SignalWire Voice applications:
  
  SWML Document URL: $FUNCTION_URL
  Authentication: Basic Auth ($AUTH_USER:$AUTH_PASS)
  
  Example Voice App:
  {
    "version": "1.0.0",
    "sections": {
      "main": [
        {
          "answer": {}
        },
        {
          "ai": {
            "SWML": {
              "url": "$FUNCTION_URL",
              "auth_user": "$AUTH_USER",
              "auth_password": "$AUTH_PASS"
            }
          }
        }
      ]
    }
  }
EOF
    
    echo ""
    echo -e "${CYAN}Direct API Usage:${NC}"
    cat << EOF
  Call the weather function directly:
  
  curl -X POST "${FUNCTION_URL}swaig" \\
    -u "$AUTH_USER:$AUTH_PASS" \\
    -H "Content-Type: application/json" \\
    -d '{
      "function": "get_weather",
      "argument": {
        "parsed": [{
          "location": "San Francisco",
          "days": 3,
          "include_alerts": true
        }]
      },
      "call_id": "your-call-id"
    }'
EOF
}

main() {
    show_banner
    
    # Validate deployment
    validate_deployment
    echo ""
    
    # Run basic tests
    test_health_endpoint
    echo ""
    
    test_swml_generation
    echo ""
    
    # Demo weather functions
    log_demo "🌤️ Weather Function Demonstrations"
    echo "=================================="
    echo ""
    
    demo_weather_function "San Francisco, CA" 1 false
    echo ""
    
    demo_weather_function "Miami, FL" 2 true
    echo ""
    
    # Show integration examples
    show_integration_examples
    echo ""
    
    # Interactive demo
    interactive_demo
}

# Check prerequisites
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq not found. Please install jq."
    echo "  macOS: brew install jq"
    echo "  Ubuntu: sudo apt-get install jq"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    log_error "curl not found. Please install curl."
    exit 1
fi

# Run main function
main "$@" 