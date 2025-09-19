#!/bin/bash

# Script deploy Jira lên Ubuntu server
# Sử dụng cho production hoặc staging environment

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

# Cấu hình mặc định
JIRA_DOMAIN=${JIRA_DOMAIN:-"jira.yourdomain.com"}
JIRA_EMAIL=${JIRA_EMAIL:-"admin@yourdomain.com"}
JIRA_PASSWORD=${JIRA_PASSWORD:-"SecurePassword123!"}
MONGO_PASSWORD=${MONGO_PASSWORD:-"SecureMongoPass123!"}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"SecurePostgresPass123!"}

# Tạo file .env cho production
create_env_file() {
    log "Tạo file cấu hình production..."
    
    cat > .env << EOF
# Production Environment Configuration
COMPOSE_PROJECT_NAME=jira-prod

# Domain Configuration
JIRA_DOMAIN=${JIRA_DOMAIN}
JIRA_EMAIL=${JIRA_EMAIL}

# Security Configuration
JIRA_PASSWORD=${JIRA_PASSWORD}
MONGO_ROOT_PASSWORD=${MONGO_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Network Configuration
JIRA_PORT=8080
MONGO_PORT=27017
POSTGRES_PORT=5432
MONGO_EXPRESS_PORT=8081

# SSL Configuration
SSL_EMAIL=${JIRA_EMAIL}
SSL_DOMAIN=${JIRA_DOMAIN}
EOF

    success "File .env đã được tạo"
}

# Tạo docker-compose.prod.yml
create_production_compose() {
    log "Tạo Docker Compose cho production..."
    
    cat > docker-compose.prod.yml << 'EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:7.0
    container_name: jira-mongodb-prod
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_ROOT_PASSWORD}
      MONGO_INITDB_DATABASE: jira
    volumes:
      - mongodb_data:/data/db
      - ./mongo-init:/docker-entrypoint-initdb.d
      - ./backups:/backups
    networks:
      - jira-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  postgres:
    image: postgres:15
    container_name: jira-postgres-prod
    restart: unless-stopped
    environment:
      POSTGRES_DB: jiradb
      POSTGRES_USER: jira
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    networks:
      - jira-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  jira:
    image: atlassian/jira-software:9.12.0
    container_name: jira-app-prod
    restart: unless-stopped
    environment:
      - ATL_PROXY_NAME=${JIRA_DOMAIN}
      - ATL_PROXY_PORT=443
      - ATL_TOMCAT_SCHEME=https
      - ATL_TOMCAT_SECURE=true
      - ATL_TOMCAT_SERVERNAME=${JIRA_DOMAIN}
      - ATL_TOMCAT_PORT=443
      - ATL_TOMCAT_CONTEXTPATH=
      - ATL_JDBC_URL=jdbc:postgresql://postgres:5432/jiradb
      - ATL_JDBC_USER=jira
      - ATL_JDBC_PASSWORD=${POSTGRES_PASSWORD}
      - ATL_DB_DRIVER=org.postgresql.Driver
      - ATL_DB_TYPE=postgres72
    volumes:
      - jira_data:/var/atlassian/application-data/jira
      - ./jira-config:/opt/atlassian/jira/conf
      - ./backups:/backups
    depends_on:
      - postgres
    networks:
      - jira-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:alpine
    container_name: jira-nginx-prod
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - jira
    networks:
      - jira-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  certbot:
    image: certbot/certbot
    container_name: jira-certbot
    volumes:
      - ./ssl:/etc/letsencrypt
      - ./webroot:/var/www/certbot
    command: certonly --webroot --webroot-path=/var/www/certbot --email ${SSL_EMAIL} --agree-tos --no-eff-email -d ${SSL_DOMAIN}
    networks:
      - jira-network

volumes:
  mongodb_data:
  jira_data:
  postgres_data:

networks:
  jira-network:
    driver: bridge
EOF

    success "Docker Compose production đã được tạo"
}

# Tạo nginx configuration
create_nginx_config() {
    log "Tạo cấu hình Nginx..."
    
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream jira {
        server jira:8080;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name ${JIRA_DOMAIN};

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/live/${JIRA_DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/live/${JIRA_DOMAIN}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # Security
        client_max_body_size 100M;
        client_body_timeout 60s;
        client_header_timeout 60s;

        # Rate limiting
        limit_req zone=login burst=5 nodelay;
        limit_req zone=api burst=20 nodelay;

        # Proxy to Jira
        location / {
            proxy_pass http://jira;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Static files caching
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
            proxy_pass http://jira;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF

    success "Cấu hình Nginx đã được tạo"
}

# Tạo script backup
create_backup_script() {
    log "Tạo script backup..."
    
    cat > backup.sh << 'EOF'
#!/bin/bash

# Script backup cho Jira production
BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Tạo thư mục backup
mkdir -p $BACKUP_DIR

# Backup MongoDB
docker exec jira-mongodb-prod mongodump --out /backups/mongodb_$DATE

# Backup PostgreSQL
docker exec jira-postgres-prod pg_dump -U jira jiradb > $BACKUP_DIR/postgres_$DATE.sql

# Backup Jira data
docker run --rm -v jira_jira_data:/data -v $(pwd)/$BACKUP_DIR:/backup alpine tar czf /backup/jira_data_$DATE.tar.gz -C /data .

# Xóa backup cũ hơn 30 ngày
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
find $BACKUP_DIR -name "mongodb_*" -mtime +30 -exec rm -rf {} \;

echo "Backup completed: $DATE"
EOF

    chmod +x backup.sh
    success "Script backup đã được tạo"
}

# Tạo script monitoring
create_monitoring_script() {
    log "Tạo script monitoring..."
    
    cat > monitor.sh << 'EOF'
#!/bin/bash

# Script monitoring cho Jira production
LOG_FILE="./logs/monitor.log"

# Tạo thư mục logs
mkdir -p logs

# Function log
log() {
    echo "[$(date)] $1" >> $LOG_FILE
}

# Kiểm tra containers
check_containers() {
    if ! docker ps | grep -q "jira-app-prod"; then
        log "ERROR: Jira container is down"
        docker-compose -f docker-compose.prod.yml restart jira
    fi
    
    if ! docker ps | grep -q "jira-mongodb-prod"; then
        log "ERROR: MongoDB container is down"
        docker-compose -f docker-compose.prod.yml restart mongodb
    fi
    
    if ! docker ps | grep -q "jira-postgres-prod"; then
        log "ERROR: PostgreSQL container is down"
        docker-compose -f docker-compose.prod.yml restart postgres
    fi
}

# Kiểm tra disk space
check_disk_space() {
    USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $USAGE -gt 80 ]; then
        log "WARNING: Disk usage is ${USAGE}%"
    fi
}

# Kiểm tra memory
check_memory() {
    MEMORY=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
    if (( $(echo "$MEMORY > 90" | bc -l) )); then
        log "WARNING: Memory usage is ${MEMORY}%"
    fi
}

# Chạy checks
check_containers
check_disk_space
check_memory

log "Monitoring check completed"
EOF

    chmod +x monitor.sh
    success "Script monitoring đã được tạo"
}

# Tạo systemd service
create_systemd_service() {
    log "Tạo systemd service..."
    
    sudo tee /etc/systemd/system/jira.service > /dev/null << EOF
[Unit]
Description=Jira Production Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker-compose -f docker-compose.prod.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable jira.service
    
    success "Systemd service đã được tạo"
}

# Tạo cron jobs
create_cron_jobs() {
    log "Tạo cron jobs..."
    
    # Backup hàng ngày lúc 2:00 AM
    (crontab -l 2>/dev/null; echo "0 2 * * * cd $(pwd) && ./backup.sh") | crontab -
    
    # Monitoring mỗi 5 phút
    (crontab -l 2>/dev/null; echo "*/5 * * * * cd $(pwd) && ./monitor.sh") | crontab -
    
    # Log rotation hàng tuần
    (crontab -l 2>/dev/null; echo "0 0 * * 0 find $(pwd)/logs -name '*.log' -mtime +7 -delete") | crontab -
    
    success "Cron jobs đã được tạo"
}

# Function chính
main() {
    echo "=========================================="
    echo "🚀 DEPLOY JIRA LÊN UBUNTU SERVER"
    echo "=========================================="
    echo ""
    
    # Nhập thông tin cấu hình
    read -p "Nhập domain cho Jira (mặc định: $JIRA_DOMAIN): " input_domain
    JIRA_DOMAIN=${input_domain:-$JIRA_DOMAIN}
    
    read -p "Nhập email admin (mặc định: $JIRA_EMAIL): " input_email
    JIRA_EMAIL=${input_email:-$JIRA_EMAIL}
    
    read -s -p "Nhập password admin (mặc định: $JIRA_PASSWORD): " input_password
    echo
    JIRA_PASSWORD=${input_password:-$JIRA_PASSWORD}
    
    # Tạo các file cấu hình
    create_env_file
    create_production_compose
    create_nginx_config
    create_backup_script
    create_monitoring_script
    create_systemd_service
    create_cron_jobs
    
    # Tạo thư mục cần thiết
    mkdir -p ssl webroot logs backups
    
    echo ""
    echo "=========================================="
    echo "✅ DEPLOY HOÀN THÀNH!"
    echo "=========================================="
    echo ""
    echo "📋 Bước tiếp theo:"
    echo "   1. Cấu hình DNS trỏ domain $JIRA_DOMAIN về server này"
    echo "   2. Chạy: docker-compose -f docker-compose.prod.yml up -d"
    echo "   3. Chạy: docker-compose -f docker-compose.prod.yml exec certbot certbot"
    echo "   4. Restart nginx: docker-compose -f docker-compose.prod.yml restart nginx"
    echo ""
    echo "🔧 Quản lý service:"
    echo "   • Start: sudo systemctl start jira"
    echo "   • Stop: sudo systemctl stop jira"
    echo "   • Status: sudo systemctl status jira"
    echo ""
    echo "📊 Monitoring:"
    echo "   • Logs: tail -f logs/monitor.log"
    echo "   • Backup: ./backup.sh"
    echo ""
}

# Chạy script
main "$@"
