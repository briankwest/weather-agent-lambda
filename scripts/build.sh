#!/bin/bash
set -euo pipefail

# SignalWire Weather Agent - Build Script
# ======================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
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

cleanup() {
    log_info "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
    rm -f "$PROJECT_ROOT/$PACKAGE_NAME"
}

validate_source() {
    log_info "Validating source files..."
    
    if [ ! -f "$PROJECT_ROOT/src/hybrid_lambda_handler.py" ]; then
        log_error "Source file not found: src/hybrid_lambda_handler.py"
        exit 1
    fi
    
    # Validate Python syntax
    python -m py_compile "$PROJECT_ROOT/src/hybrid_lambda_handler.py"
    log_success "Source validation complete"
}

create_build_structure() {
    log_info "Creating build structure..."
    mkdir -p "$BUILD_DIR"
    
    # Copy source as lambda_function.py
    cp "$PROJECT_ROOT/src/hybrid_lambda_handler.py" "$BUILD_DIR/lambda_function.py"
    
    # Create requirements.txt for build
    cat > "$BUILD_DIR/requirements.txt" << 'EOF'
signalwire-agents>=0.1.0
fastapi>=0.115.0
uvicorn>=0.34.0
pydantic>=2.0.0
pydantic-core
starlette>=0.40.0
anyio>=4.0.0
sniffio>=1.3.0
h11>=0.16.0
click>=8.0.0
typing-extensions>=4.8.0
annotated-types>=0.7.0
structlog>=24.0.0
PyYAML>=6.0.0
requests>=2.32.3
urllib3>=1.26.0
certifi>=2021.5.25
charset-normalizer>=2.0.0
idna>=2.10
EOF
    
    log_success "Build structure created"
}

create_docker_assets() {
    log_info "Creating Docker build assets..."
    
    # Create Dockerfile
    cat > "$BUILD_DIR/Dockerfile" << 'EOF'
# AWS Lambda Python 3.11 base image
FROM --platform=linux/amd64 public.ecr.aws/lambda/python:3.11

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install -r requirements.txt -t /var/task/

# Copy lambda function
COPY lambda_function.py /var/task/

# Create zip creation script
COPY create_zip.py /var/task/

# Set working directory and create package
WORKDIR /var/task
RUN python3 create_zip.py
EOF

    # Create zip creation script
    cat > "$BUILD_DIR/create_zip.py" << 'EOF'
import zipfile
import os
import fnmatch

def should_exclude(path):
    """Determine if a file should be excluded from the package"""
    excludes = [
        '*.pyc', '*/__pycache__/*', '*.dist-info/*', 
        'create_zip.py', 'Dockerfile', 'requirements.txt'
    ]
    for pattern in excludes:
        if fnmatch.fnmatch(path, pattern) or '/__pycache__/' in path or '.dist-info/' in path:
            return True
    return False

print("📦 Creating deployment package...")

with zipfile.ZipFile('/tmp/deployment.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
    file_count = 0
    for root, dirs, files in os.walk('.'):
        for file in files:
            file_path = os.path.join(root, file)
            arc_path = os.path.relpath(file_path, '.')
            if not should_exclude(arc_path):
                zf.write(file_path, arc_path)
                file_count += 1

print(f"✅ Package created with {file_count} files")
EOF

    log_success "Docker assets created"
}

build_with_docker() {
    log_info "Building with Docker (Linux x86_64 compatibility)..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    cd "$BUILD_DIR"
    
    # Build the package
    log_info "Building Docker image..."
    docker build --platform=linux/amd64 -t weather-agent-builder . --quiet
    
    # Create a temporary container and extract the zip file
    log_info "Extracting deployment package..."
    container_id=$(docker create --platform=linux/amd64 weather-agent-builder)
    
    # Copy the zip file from the container
    if docker cp "$container_id:/tmp/deployment.zip" ./deployment.zip; then
        log_success "Package extracted successfully"
    else
        log_error "Failed to extract package from container"
        docker rm "$container_id" 2>/dev/null || true
        exit 1
    fi
    
    # Clean up the container
    docker rm "$container_id" >/dev/null 2>&1 || true
    
    # Move to project root
    mv deployment.zip "$PROJECT_ROOT/$PACKAGE_NAME"
    
    log_success "Docker build complete"
}

show_package_info() {
    if [ -f "$PROJECT_ROOT/$PACKAGE_NAME" ]; then
        local size=$(du -h "$PROJECT_ROOT/$PACKAGE_NAME" | cut -f1)
        local file_count=$(unzip -l "$PROJECT_ROOT/$PACKAGE_NAME" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
        
        echo ""
        log_success "Package Information:"
        echo "  📦 Package: $PACKAGE_NAME"
        echo "  📏 Size: $size"
        echo "  📁 Files: $file_count"
        echo "  🎯 Target: AWS Lambda (Linux x86_64)"
        echo ""
    fi
}

main() {
    echo "🌤️  SignalWire Weather Agent - Build"
    echo "===================================="
    echo ""
    
    cleanup
    validate_source
    create_build_structure
    create_docker_assets
    build_with_docker
    
    # Cleanup build directory
    rm -rf "$BUILD_DIR"
    
    show_package_info
    
    log_success "Build complete! Ready for deployment."
    echo "💡 Next step: make deploy"
}

# Run main function
main "$@" 