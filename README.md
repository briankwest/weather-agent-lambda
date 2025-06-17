# 🌤️ SignalWire Weather Agent

> **Professional AI-powered weather assistant for AWS Lambda**

A production-ready SignalWire AI agent that provides comprehensive weather information through voice, SMS, or API calls. Built with the SignalWire Agents SDK and optimized for serverless deployment.

[![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-orange?logo=amazon-aws)](https://aws.amazon.com/lambda/)
[![SignalWire](https://img.shields.io/badge/SignalWire-Agents-blue?logo=signalwire)](https://signalwire.com/)
[![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python)](https://python.org/)
[![Docker](https://img.shields.io/badge/Docker-Enabled-blue?logo=docker)](https://docker.com/)

## ✨ Features

- **🎯 AI-Powered Conversations**: Natural language weather queries
- **🌍 Global Coverage**: Weather data for any location worldwide
- **📅 Multi-Day Forecasts**: Up to 10-day weather forecasts
- **⚠️ Weather Alerts**: Real-time weather warnings and alerts
- **🌬️ Air Quality**: Air quality index information
- **🔐 Secure Authentication**: HTTP Basic Auth protection
- **📊 Production Ready**: Comprehensive logging and monitoring
- **🚀 One-Command Deployment**: Automated build and deploy process

## 🏗️ Architecture

The weather agent uses **Mangum** to seamlessly integrate SignalWire agents with AWS Lambda:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   SignalWire    │    │   AWS Lambda     │    │  WeatherAPI.com │
│   Voice/SMS     │───▶│  Weather Agent   │───▶│   Weather Data  │
│   Applications  │    │  (Mangum+FastAPI)│    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │     Mangum       │
                    │ • API Gateway    │
                    │ • FastAPI Bridge │
                    │ • HTTP Routing   │
                    │ • Error Handling │
                    └──────────────────┘
```

### 🎯 **Mangum Integration Benefits**

- **🔗 Seamless Integration**: Mangum bridges API Gateway and FastAPI automatically
- **🛡️ Full Feature Support**: All FastAPI features work including health endpoints
- **🔄 Standard Routing**: Normal HTTP routing with `/health`, `/ready`, `/swaig` endpoints
- **📊 Proper Responses**: Native FastAPI response handling
- **⚡ Performance**: Optimized ASGI to Lambda translation

### 📍 **Available Endpoints**

**All Modes (Lambda & Local):**
- `/` - Returns SWML configuration
- `/swaig` - SWAIG function execution
- `/post_prompt` - Post-prompt callbacks
- `/check_for_input` - Input validation callbacks
- `/health` - Health check endpoint
- `/ready` - Readiness check endpoint
- `/debug` - Debug information

**Key Improvement:** With Mangum, all FastAPI endpoints work in Lambda mode!

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Docker installed and running
- Python 3.8+ installed
- WeatherAPI.com API key ([Get one free](https://www.weatherapi.com/))

### 1. Environment Setup

```bash
# Clone and enter the project
git clone <repository-url>
cd weather-agent-lambda

# Validate your environment
make validate-env

# Set your WeatherAPI key
export WEATHERAPI_KEY="your-api-key-here"
```

### 2. Deploy in One Command

```bash
# Build and deploy everything
make deploy
```

### 3. Run Interactive Demo

```bash
# Experience the agent in action
make demo
```

## 📋 Available Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make validate-env` | Validate system requirements |
| `make build` | Build deployment package |
| `make deploy` | Deploy to AWS Lambda |
| `make demo` | Run interactive demo |
| `make status` | Check deployment health |
| `make logs` | View Lambda logs |
| `make clean` | Clean build artifacts |

## 🎬 Demo Experience

The interactive demo showcases:

- **Health Check**: Validates deployment status
- **SWML Generation**: Shows agent configuration
- **Weather Functions**: Live weather data retrieval
- **Integration Examples**: Ready-to-use code snippets
- **Custom Queries**: Test with your own locations

```bash
make demo
```

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WEATHERAPI_KEY` | ✅ | - | WeatherAPI.com API key |
| `SWML_BASIC_AUTH_USER` | ❌ | `dev` | Basic auth username |
| `SWML_BASIC_AUTH_PASSWORD` | ❌ | `w00t` | Basic auth password |
| `LOCAL_TZ` | ❌ | `America/Los_Angeles` | Local timezone |

### Customization

The agent can be customized by modifying `src/hybrid_lambda_handler.py`:

- **Personality**: Adjust the agent's conversational style
- **Functions**: Add new weather-related capabilities
- **Languages**: Configure multi-language support
- **Voice Settings**: Customize speech patterns and fillers

## 🌐 Integration

### SignalWire Voice Application

```json
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
            "url": "https://your-function-url.lambda-url.us-east-1.on.aws/",
            "auth_user": "dev",
            "auth_password": "w00t"
          }
        }
      }
    ]
  }
}
```

### Direct API Usage

```bash
# Get current weather
curl -X POST "https://your-function-url/swaig" \
  -u "dev:w00t" \
  -H "Content-Type: application/json" \
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
```

## 📊 Monitoring

### View Logs

```bash
# Recent logs
make logs

# Follow live logs
./scripts/logs.sh -f

# Error logs only
./scripts/logs.sh -e

# Last 30 minutes
./scripts/logs.sh -t 30
```

### Check Status

```bash
# Comprehensive health check
make status
```

### Metrics Dashboard

The deployment includes CloudWatch metrics for:
- Function invocations
- Error rates
- Duration
- Memory usage

## 🛠️ Development

### Local Testing

```bash
# Start local development server
make dev

# Test agent configuration
swaig-test src/hybrid_lambda_handler.py --list-agents

# Test weather function
swaig-test src/hybrid_lambda_handler.py --exec get_weather --location "New York"
```

### Project Structure

```
weather-agent-lambda/
├── src/
│   └── hybrid_lambda_handler.py    # Main agent implementation
├── scripts/
│   ├── build.sh                    # Docker-based build
│   ├── deploy.sh                   # AWS deployment
│   ├── logs.sh                     # Log management
│   ├── status.sh                   # Health checking
│   ├── demo.sh                     # Interactive demo
│   └── validate-env.sh             # Environment validation
├── Makefile                        # Command interface
├── requirements.txt                # Python dependencies
└── README.md                       # This file
```

## 🔒 Security

- **Authentication**: HTTP Basic Auth for all endpoints
- **Environment Variables**: Secure credential management
- **IAM Roles**: Minimal required permissions
- **HTTPS Only**: All communications encrypted
- **Input Validation**: Comprehensive parameter validation

## 🚀 Deployment Details

### Build Process

1. **Docker Build**: Uses AWS Lambda Python 3.11 base image
2. **Dependency Installation**: Linux x86_64 compatible packages
3. **Package Creation**: Optimized ZIP file for Lambda
4. **Validation**: Syntax and import checking

### AWS Resources Created

- **Lambda Function**: `weather-agent`
- **IAM Role**: `weather-agent-execution-role`
- **Function URL**: Public HTTPS endpoint
- **CloudWatch Logs**: Automatic log group creation

### Cost Optimization

- **Memory**: 512MB (adjustable)
- **Timeout**: 30 seconds
- **Architecture**: x86_64
- **Provisioned Concurrency**: None (on-demand)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

### Common Issues

**Build fails on Apple Silicon (M1/M2)**
- Solution: The build script uses Docker with `--platform=linux/amd64` to ensure compatibility

**AWS credentials not found**
- Solution: Run `aws configure` or set environment variables

**WeatherAPI key invalid**
- Solution: Verify your key at [WeatherAPI.com](https://www.weatherapi.com/)

### Getting Help

1. Check the [troubleshooting guide](docs/troubleshooting.md)
2. Run `make validate-env` to check your setup
3. View logs with `make logs`
4. Check status with `make status`

## 🎯 What's Next?

- **Multi-Language Support**: Expand to more languages
- **Additional Weather Sources**: Integrate multiple weather APIs
- **Advanced Analytics**: Weather trend analysis
- **Mobile Integration**: SMS and WhatsApp support
- **Voice Customization**: Multiple voice options

---

<div align="center">

**Built with ❤️ using SignalWire Agents SDK**

[SignalWire](https://signalwire.com/) • [AWS Lambda](https://aws.amazon.com/lambda/) • [WeatherAPI](https://www.weatherapi.com/)

</div> 