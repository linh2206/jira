#!/bin/bash

# Script cài đặt dependencies cho Ubuntu
# Chạy script này trước khi chạy build.sh

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Kiểm tra quyền sudo
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        error "Script này cần quyền sudo. Vui lòng chạy với sudo hoặc đảm bảo user có quyền sudo."
        exit 1
    fi
}

# Cập nhật hệ thống
update_system() {
    log "Cập nhật hệ thống Ubuntu..."
    sudo apt-get update
    sudo apt-get upgrade -y
    success "Hệ thống đã được cập nhật"
}

# Cài đặt các package cần thiết
install_prerequisites() {
    log "Cài đặt các package cần thiết..."
    
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        wget \
        unzip \
        git \
        htop \
        vim \
        net-tools \
        ufw
    
    success "Các package cần thiết đã được cài đặt"
}

# Cài đặt Docker
install_docker() {
    log "Cài đặt Docker..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    success "Docker đã được cài đặt"
}

# Cài đặt Docker Compose
install_docker_compose() {
    log "Cài đặt Docker Compose..."
    
    # Download latest version
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make executable
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symlink
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    success "Docker Compose đã được cài đặt"
}

# Cấu hình Docker
configure_docker() {
    log "Cấu hình Docker..."
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Configure Docker daemon
    sudo mkdir -p /etc/docker
    cat << EOF | sudo tee /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF
    
    # Restart Docker
    sudo systemctl restart docker
    
    success "Docker đã được cấu hình"
}

# Cấu hình firewall
configure_firewall() {
    log "Cấu hình firewall..."
    
    # Enable UFW
    sudo ufw --force enable
    
    # Allow SSH
    sudo ufw allow ssh
    
    # Allow Jira ports
    sudo ufw allow 8080/tcp comment 'Jira'
    sudo ufw allow 27017/tcp comment 'MongoDB'
    sudo ufw allow 5432/tcp comment 'PostgreSQL'
    sudo ufw allow 8081/tcp comment 'Mongo Express'
    
    success "Firewall đã được cấu hình"
}

# Tối ưu hệ thống
optimize_system() {
    log "Tối ưu hệ thống..."
    
    # Increase file limits
    cat << EOF | sudo tee -a /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF
    
    # Configure kernel parameters
    cat << EOF | sudo tee -a /etc/sysctl.conf
# Docker optimizations
vm.max_map_count=262144
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
EOF
    
    # Apply sysctl changes
    sudo sysctl -p
    
    success "Hệ thống đã được tối ưu"
}

# Kiểm tra cài đặt
verify_installation() {
    log "Kiểm tra cài đặt..."
    
    # Check Docker
    if docker --version &> /dev/null; then
        success "Docker: $(docker --version)"
    else
        error "Docker chưa được cài đặt đúng"
    fi
    
    # Check Docker Compose
    if docker-compose --version &> /dev/null; then
        success "Docker Compose: $(docker-compose --version)"
    else
        error "Docker Compose chưa được cài đặt đúng"
    fi
    
    # Check Docker service
    if systemctl is-active --quiet docker; then
        success "Docker service đang chạy"
    else
        error "Docker service không chạy"
    fi
}

# Function chính
main() {
    echo "=========================================="
    echo "🐧 CÀI ĐẶT DEPENDENCIES CHO UBUNTU"
    echo "=========================================="
    echo ""
    
    check_sudo
    update_system
    install_prerequisites
    install_docker
    install_docker_compose
    configure_docker
    configure_firewall
    optimize_system
    verify_installation
    
    echo ""
    echo "=========================================="
    echo "✅ CÀI ĐẶT HOÀN THÀNH!"
    echo "=========================================="
    echo ""
    echo "📋 Bước tiếp theo:"
    echo "   1. Logout và login lại để áp dụng docker group"
    echo "   2. Chạy: ./build.sh để build Jira"
    echo ""
    echo "🔧 Hoặc chạy trực tiếp:"
    echo "   sudo -u $USER ./build.sh"
    echo ""
}

# Chạy script
main "$@"
