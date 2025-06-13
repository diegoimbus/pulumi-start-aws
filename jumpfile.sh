#!/bin/bash

# jumpfile.sh - Complete automated deployment for AWS Todo App
# Usage: ./jumpfile.sh [command]
# Commands: deploy, test, status, logs, destroy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"; }

# Configuration
SSH_KEY="$HOME/.ssh/demo-ed25519"
DB_PASSWORD="testpassword123"

# Functions
get_server_ip() {
    pulumi stack output serverPublicIp 2>/dev/null || echo ""
}

get_db_endpoint() {
    pulumi stack output databaseEndpoint 2>/dev/null | sed 's/:5432//' || echo ""
}

get_database_url() {
    local db_endpoint=$(get_db_endpoint)
    if [ -n "$db_endpoint" ]; then
        echo "postgresql://postgres:${DB_PASSWORD}@${db_endpoint}:5432/todo"
    else
        echo ""
    fi
}

sync_files() {
    local server_ip="$1"
    log "Syncing local files to server..."
    
    # Create app directory
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$server_ip" 'mkdir -p /home/ubuntu/app'
    
    # Sync files
    rsync -avz --delete \
        -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.env' \
        --exclude='*.pyc' \
        --exclude='jumpfile.sh' \
        ./ ubuntu@"$server_ip":/home/ubuntu/app/
    
    log "Files synced successfully"
}

setup_server() {
    local server_ip="$1"
    local database_url="$2"
    
    log "Setting up server and deploying applications..."
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$server_ip" << EOF
set -e

echo "=== Application Deployment Started ==="

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker ubuntu
else
    echo "Docker already installed"
fi

# Install Docker Compose manually
if ! docker compose version &> /dev/null 2>&1; then
    echo "Installing Docker Compose..."
    DOCKER_CONFIG=\${DOCKER_CONFIG:-\$HOME/.docker}
    mkdir -p \$DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.37.0/docker-compose-linux-x86_64 -o \$DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x \$DOCKER_CONFIG/cli-plugins/docker-compose
    echo "Docker Compose installed"
else
    echo "Docker Compose already installed"
fi

# Verify Docker Compose works
if docker compose version &> /dev/null 2>&1; then
    echo "✅ Docker Compose ready: \$(docker compose version)"
else
    echo "❌ Docker Compose installation failed"
    exit 1
fi

# Go to app directory
cd /home/ubuntu/app

# Stop existing containers
echo "Stopping existing containers..."
sudo docker compose down 2>/dev/null || true

# Set environment and start containers
export DATABASE_URL="${database_url}"
echo "Starting containers with DATABASE_URL: \$DATABASE_URL"

# Create .env file
cat > .env << ENV_EOF
DATABASE_URL=${database_url}
ENVIRONMENT=production
ENV_EOF

# Start containers (production mode - no local database)
echo "Building and starting containers..."
sudo -E docker compose up -d --build api web

# Wait for containers to start
echo "Waiting for containers to start..."
sleep 15

# Check container status
echo "=== Container Status ==="
sudo docker ps

echo "=== Deployment Complete ==="
EOF

    log "Server setup completed"
}

test_deployment() {
    local server_ip="$1"
    
    log "Testing deployment..."
    
    # Wait a bit for services to be ready
    sleep 10
    
    # Test API
    if curl -s --connect-timeout 10 "http://$server_ip:8000/todos/" >/dev/null 2>&1; then
        log "✅ API is responding at http://$server_ip:8000"
    else
        warn "❌ API not responding yet"
    fi
    
    # Test Frontend
    if curl -s --connect-timeout 10 "http://$server_ip:3000" >/dev/null 2>&1; then
        log "✅ Frontend is responding at http://$server_ip:3000"
    else
        warn "❌ Frontend not responding yet"
    fi
    
    echo ""
    info "🚀 Application URLs:"
    info "   Frontend: http://$server_ip:3000"
    info "   API: http://$server_ip:8000"
    info "   API Docs: http://$server_ip:8000/docs"
}

show_status() {
    local server_ip=$(get_server_ip)
    local db_endpoint=$(get_db_endpoint)
    
    echo ""
    info "=== Deployment Status ==="
    
    if [ -n "$server_ip" ]; then
        log "✅ Infrastructure deployed"
        echo "   Server IP: $server_ip"
        echo "   Database: $db_endpoint"
        echo ""
        echo "   URLs:"
        echo "     Frontend: http://$server_ip:3000"
        echo "     API: http://$server_ip:8000"
        echo "     API Docs: http://$server_ip:8000/docs"
    else
        error "❌ Infrastructure not deployed"
        echo "   Run: ./jumpfile.sh deploy"
    fi
    echo ""
}

show_logs() {
    local server_ip=$(get_server_ip)
    if [ -z "$server_ip" ]; then
        error "No server found. Deploy first."
        exit 1
    fi
    
    create_ssh_key
    log "Fetching application logs..."
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$server_ip" '
        echo "=== CONTAINER STATUS ===";
        sudo docker ps -a;
        echo "";
        echo "=== API LOGS ===";
        if sudo docker ps | grep -q "api"; then
            sudo docker logs api --tail 50 2>/dev/null;
        else
            echo "❌ API container not running";
            echo "Checking if API container exists...";
            if sudo docker ps -a | grep -q "api"; then
                echo "API container exists but stopped. Last logs:";
                sudo docker logs api --tail 20 2>/dev/null;
            else
                echo "API container does not exist";
            fi
        fi
        echo "";
        echo "=== WEB LOGS ===";
        if sudo docker ps | grep -q "web"; then
            sudo docker logs web --tail 50 2>/dev/null;
        else
            echo "❌ Web container not running";
        fi
    '
}

deploy_infra() {
    log "Deploying infrastructure with Pulumi..."
    pulumi up
}

deploy_apps() {
    local server_ip=$(get_server_ip)
    local database_url=$(get_database_url)
    
    if [ -z "$server_ip" ]; then
        error "No server IP found. Deploy infrastructure first."
        exit 1
    fi
    
    if [ -z "$database_url" ]; then
        error "No database URL found."
        exit 1
    fi
    
    sync_files "$server_ip"
    setup_server "$server_ip" "$database_url"
    test_deployment "$server_ip"
}

destroy_all() {
    warn "⚠️  This will DELETE ALL infrastructure and data permanently!"
    warn "   - RDS Database (all todos will be lost)"
    warn "   - EC2 Instance"
    warn "   - Security Groups"
    warn "   - SSH Keys"
    warn "   - Secrets Manager entries"
    echo ""
    warn "Are you absolutely sure? Type 'DELETE' to confirm:"
    read -r confirmation
    if [ "$confirmation" = "DELETE" ]; then
        log "Deleting all infrastructure..."
        pulumi destroy --yes
        rm -f "$SSH_KEY"
        log "🗑️  All infrastructure deleted successfully"
        log "💡 You can redeploy anytime with: ./jumpfile.sh deploy-infra"
    else
        log "❌ Deletion cancelled - infrastructure preserved"
    fi
}

show_help() {
    echo "AWS Todo Application Jumpfile"
    echo "============================="
    echo ""
    echo "Usage: ./jumpfile.sh [command]"
    echo ""
    echo "Commands:"
    echo "  deploy-infra  Deploy infrastructure only"
    echo "  deploy-apps   Deploy applications only"
    echo "  test          Test deployed applications"
    echo "  status        Show deployment status and URLs"
    echo "  logs          Show application logs"
    echo "  destroy       Destroy all infrastructure permanently"
    echo "  help          Show this help"
    echo ""
    echo "Typical workflow:"
    echo "  ./jumpfile.sh deploy-infra  # Create AWS resources"
    echo "  ./jumpfile.sh deploy-apps   # Deploy applications"
    echo "  ./jumpfile.sh status        # Check status"
    echo "  ./jumpfile.sh logs          # View logs"
    echo ""
    echo "⚠️  Warning: destroy requires typing 'DELETE' to confirm!"
}

# Main script logic
case "${1:-help}" in
    "deploy-infra")
        deploy_infra
        ;;
    "deploy-apps")
        deploy_apps
        ;;
    "test")
        server_ip=$(get_server_ip)
        test_deployment "$server_ip"
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    "destroy")
        destroy_all
        ;;
    "help"|*)
        show_help
        ;;
esac
