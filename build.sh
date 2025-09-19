#!/bin/bash

# Script build Jira local với MongoDB cho Ubuntu
# Tác giả: AI Assistant
# Ngày tạo: $(date)

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function để in log
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

# Kiểm tra và cài đặt dependencies cho Ubuntu
check_dependencies() {
    log "Kiểm tra dependencies..."
    
    # Kiểm tra OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log "Phát hiện Ubuntu/Linux system"
    else
        warning "Script này được tối ưu cho Ubuntu/Linux"
    fi
    
    # Kiểm tra Docker
    if ! command -v docker &> /dev/null; then
        error "Docker chưa được cài đặt."
        log "Đang cài đặt Docker..."
        install_docker
    fi
    
    # Kiểm tra Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose chưa được cài đặt."
        log "Đang cài đặt Docker Compose..."
        install_docker_compose
    fi
    
    # Kiểm tra Docker service
    if ! systemctl is-active --quiet docker; then
        log "Đang start Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    # Thêm user vào docker group nếu cần
    if ! groups $USER | grep -q docker; then
        log "Thêm user $USER vào docker group..."
        sudo usermod -aG docker $USER
        warning "Vui lòng logout và login lại để áp dụng thay đổi group"
    fi
    
    success "Dependencies đã sẵn sàng"
}

# Cài đặt Docker cho Ubuntu
install_docker() {
    log "Cài đặt Docker..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    success "Docker đã được cài đặt"
}

# Cài đặt Docker Compose cho Ubuntu
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

# Tạo thư mục cần thiết
create_directories() {
    log "Tạo thư mục cần thiết..."
    
    mkdir -p mongo-init
    mkdir -p jira-config
    mkdir -p logs
    
    success "Đã tạo thư mục cần thiết"
}

# Tạo file init cho MongoDB
create_mongo_init() {
    log "Tạo file khởi tạo MongoDB..."
    
    cat > mongo-init/init.js << 'EOF'
// Khởi tạo database và user cho Jira
db = db.getSiblingDB('jira');

// Tạo user cho Jira
db.createUser({
  user: 'jira_user',
  pwd: 'jira_password',
  roles: [
    {
      role: 'readWrite',
      db: 'jira'
    }
  ]
});

// Tạo collections cơ bản
db.createCollection('issues');
db.createCollection('projects');
db.createCollection('users');
db.createCollection('workflows');

// Insert dữ liệu mẫu
db.projects.insertOne({
  key: 'DEMO',
  name: 'Demo Project',
  description: 'Dự án demo cho Jira local',
  created: new Date(),
  lead: 'admin'
});

db.users.insertOne({
  username: 'admin',
  email: 'admin@example.com',
  displayName: 'Administrator',
  active: true,
  created: new Date()
});

print('MongoDB initialization completed successfully!');
EOF

    success "Đã tạo file khởi tạo MongoDB"
}

# Tạo file cấu hình Jira
create_jira_config() {
    log "Tạo file cấu hình Jira..."
    
    cat > jira-config/server.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Server port="8005" shutdown="SHUTDOWN">
    <Service name="Catalina">
        <Connector port="8080"
                   maxThreads="200"
                   minSpareThreads="10"
                   connectionTimeout="20000"
                   enableLookups="false"
                   maxHttpHeaderSize="8192"
                   protocol="HTTP/1.1"
                   useBodyEncodingForURI="true"
                   redirectPort="8443"
                   acceptCount="100"
                   disableUploadTimeout="true"
                   bindOnInit="false" />

        <Engine name="Catalina" defaultHost="localhost">
            <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true">
                <Context path="" docBase="${catalina.home}/atlassian-jira" reloadable="false" useHttpOnly="true">
                    <Resource name="UserTransaction" auth="Container" type="javax.transaction.UserTransaction"
                              factory="org.objectweb.jotm.UserTransactionFactory" jotm.timeout="60"/>
                    <Manager pathname=""/>
                </Context>
            </Host>
        </Engine>
    </Service>
</Server>
EOF

    success "Đã tạo file cấu hình Jira"
}

# Build và start containers
build_and_start() {
    log "Build và start containers..."
    
    # Pull images
    log "Đang pull Docker images..."
    docker-compose pull
    
    # Build và start
    log "Đang start containers..."
    docker-compose up -d
    
    success "Containers đã được start"
}

# Kiểm tra trạng thái containers
check_status() {
    log "Kiểm tra trạng thái containers..."
    
    sleep 10
    
    if docker-compose ps | grep -q "Up"; then
        success "Containers đang chạy"
        
        echo ""
        echo "=========================================="
        echo "🚀 JIRA LOCAL SETUP HOÀN THÀNH!"
        echo "=========================================="
        echo ""
        echo "📋 Thông tin truy cập:"
        echo "   • Jira: http://localhost:3000"
        echo "   • MongoDB: localhost:27018"
        echo "   • Mongo Express: http://localhost:27109"
        echo "   • PostgreSQL: localhost:5432"
        echo ""
        echo "🔑 Thông tin đăng nhập:"
        echo "   • Jira: admin/admin (sau khi setup lần đầu)"
        echo "   • Mongo Express: admin/admin123"
        echo "   • MongoDB: admin/password123"
        echo "   • PostgreSQL: jira/jira123"
        echo ""
        echo "📁 Dữ liệu được lưu trong Docker volumes:"
        echo "   • mongodb_data"
        echo "   • jira_data"
        echo "   • postgres_data"
        echo ""
        echo "🛠️  Các lệnh hữu ích:"
        echo "   • Xem logs: docker-compose logs -f"
        echo "   • Stop: docker-compose down"
        echo "   • Restart: docker-compose restart"
        echo "   • Xóa dữ liệu: docker-compose down -v"
        echo ""
        
    else
        error "Có lỗi khi start containers"
        docker-compose logs
        exit 1
    fi
}

# Function chính
main() {
    echo "=========================================="
    echo "🏗️  BUILD JIRA LOCAL VỚI MONGODB"
    echo "=========================================="
    echo ""
    
    check_dependencies
    create_directories
    create_mongo_init
    create_jira_config
    build_and_start
    check_status
}

# Xử lý tham số dòng lệnh
case "${1:-}" in
    "stop")
        log "Dừng containers..."
        docker-compose down
        success "Containers đã được dừng"
        ;;
    "restart")
        log "Restart containers..."
        docker-compose restart
        success "Containers đã được restart"
        ;;
    "logs")
        docker-compose logs -f
        ;;
    "clean")
        warning "Xóa tất cả dữ liệu và containers..."
        docker-compose down -v
        docker system prune -f
        success "Đã xóa sạch"
        ;;
    "status")
        docker-compose ps
        ;;
    *)
        main
        ;;
esac
