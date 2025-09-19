# 🚀 Jira Local Setup với MongoDB cho Ubuntu

Script tự động build và setup Jira local environment sử dụng Docker với MongoDB, PostgreSQL và Mongo Express trên Ubuntu.

## 📋 Yêu cầu hệ thống

- Ubuntu 20.04+ (hoặc các distro Linux tương thích)
- Docker (version 20.10+)
- Docker Compose (version 2.0+)
- ít nhất 4GB RAM
- 10GB dung lượng ổ cứng trống
- Quyền sudo

## 🏗️ Cấu trúc dự án

```
jira/
├── docker-compose.yml      # Cấu hình Docker services
├── docker-compose.prod.yml # Cấu hình production
├── build.sh               # Script build chính
├── install-ubuntu.sh      # Script cài đặt dependencies
├── deploy-ubuntu.sh       # Script deploy production
├── mongo-init/            # Script khởi tạo MongoDB
├── jira-config/           # Cấu hình Jira
├── nginx.conf             # Cấu hình Nginx
├── backup.sh              # Script backup
├── monitor.sh             # Script monitoring
└── README.md             # Hướng dẫn này
```

## 🚀 Cách sử dụng

### 1. Cài đặt dependencies (lần đầu)

```bash
# Cài đặt Docker và dependencies
sudo ./install-ubuntu.sh

# Logout và login lại để áp dụng docker group
```

### 2. Build và chạy Jira local

```bash
# Build và start containers
./build.sh
```

### 3. Các lệnh quản lý

```bash
# Dừng containers
./build.sh stop

# Restart containers
./build.sh restart

# Xem logs
./build.sh logs

# Kiểm tra trạng thái
./build.sh status

# Xóa sạch dữ liệu
./build.sh clean
```

### 4. Deploy production (tùy chọn)

```bash
# Deploy lên production server
./deploy-ubuntu.sh
```

## 🌐 Truy cập các dịch vụ

Sau khi build thành công, bạn có thể truy cập:

| Dịch vụ | URL | Thông tin đăng nhập |
|---------|-----|-------------------|
| **Jira** | http://localhost:8080 | admin/admin (sau setup) |
| **Mongo Express** | http://localhost:8081 | admin/admin123 |
| **MongoDB** | localhost:27017 | admin/password123 |
| **PostgreSQL** | localhost:5432 | jira/jira123 |

## 🔧 Cấu hình

### MongoDB
- Database: `jira`
- User: `jira_user` / `jira_password`
- Collections: issues, projects, users, workflows

### PostgreSQL
- Database: `jiradb`
- User: `jira` / `jira123`

### Jira
- Port: 8080
- Context path: `/`
- Proxy: localhost:8080

## 📊 Dữ liệu mẫu

Script tự động tạo:
- Project demo: `DEMO`
- User admin: `admin@example.com`
- Collections MongoDB cơ bản

## 🛠️ Troubleshooting

### Lỗi thường gặp trên Ubuntu

1. **Port đã được sử dụng**
   ```bash
   # Kiểm tra port đang sử dụng
   sudo netstat -tulpn | grep :8080
   sudo netstat -tulpn | grep :27017
   sudo netstat -tulpn | grep :5432
   sudo netstat -tulpn | grep :8081
   ```

2. **Docker không chạy**
   ```bash
   # Start Docker service
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

3. **Permission denied khi chạy Docker**
   ```bash
   # Thêm user vào docker group
   sudo usermod -aG docker $USER
   # Logout và login lại
   ```

4. **Không đủ RAM**
   - Tăng swap space
   - Hoặc giảm số lượng containers
   ```bash
   # Tạo swap file
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

5. **Lỗi firewall**
   ```bash
   # Mở ports cần thiết
   sudo ufw allow 8080
   sudo ufw allow 27017
   sudo ufw allow 5432
   sudo ufw allow 8081
   ```

### Xem logs chi tiết

```bash
# Logs tất cả services
docker-compose logs -f

# Logs service cụ thể
docker-compose logs -f jira
docker-compose logs -f mongodb
docker-compose logs -f postgres
```

### Reset hoàn toàn

```bash
# Xóa tất cả containers và volumes
./build.sh clean

# Build lại
./build.sh
```

## 🔒 Bảo mật

⚠️ **Lưu ý**: 
- Setup local chỉ dành cho môi trường development
- Sử dụng `deploy-ubuntu.sh` cho production với SSL và bảo mật đầy đủ

### Development (Local)
- Đổi tất cả passwords mặc định
- Cấu hình firewall
- Không expose ra internet

### Production
- Sử dụng HTTPS với Let's Encrypt
- Cấu hình Nginx reverse proxy
- Backup tự động hàng ngày
- Monitoring và logging
- Rate limiting
- Security headers

## 📝 Ghi chú

- Lần đầu chạy Jira sẽ mất 5-10 phút để khởi tạo
- Dữ liệu được lưu trong Docker volumes
- Có thể customize cấu hình trong `docker-compose.yml`

## 🤝 Hỗ trợ

Nếu gặp vấn đề, hãy:
1. Kiểm tra logs: `./build.sh logs`
2. Restart: `./build.sh restart`
3. Reset: `./build.sh clean && ./build.sh`
4. Kiểm tra system: `./monitor.sh`

## 📚 Tài liệu tham khảo

- [Docker Documentation](https://docs.docker.com/)
- [Jira Documentation](https://confluence.atlassian.com/jira)
- [MongoDB Documentation](https://docs.mongodb.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

**Chúc bạn sử dụng Jira local trên Ubuntu thành công! 🎉**
