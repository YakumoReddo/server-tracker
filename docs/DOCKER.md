# Docker部署指南

本文档介绍如何使用Docker和Docker Compose完整部署服务器监测工具。

## 🚀 快速开始

### 1. 一键启动

**Linux/Mac用户:**
```bash
./docker-deploy.sh start
```

**Windows用户:**
```cmd
docker-deploy.bat start
```

### 2. 手动启动

```bash
# 1. 创建环境配置文件
cp .env.example .env

# 2. 构建并启动所有服务
docker-compose up -d --build

# 3. 查看服务状态
docker-compose ps
```

## 📁 Docker部署架构

```
┌─────────────────────────────────────┐
│              Nginx                  │
│           (前端界面)                │
│     端口: 80 → http://localhost    │
└─────────────┬───────────────────────┘
              │
              │ 代理
              ▼
┌─────────────────────────────────────┐
│           FastAPI                   │
│           (后端API)                 │
│         端口: 8000                  │
└─────────────┬───────────────────────┘
              │
              │ 数据存储
              ▼
┌─────────────────────────────────────┐
│          SQLite数据库               │
│         (./data/monitor.db)         │
└─────────────────────────────────────┘
```

## 🐳 服务组件详解

### 1. 后端服务 (backend)

- **框架**: FastAPI + Python 3.11
- **端口**: 8000
- **功能**: API接口、数据存储、实时通信
- **健康检查**: `/api/health`
- **数据卷**: `./data` → `/app/data`

```yaml
backend:
  build: ./backend
  ports: ["8000:8000"]
  volumes: ["./data:/app/data"]
  environment:
    - DATABASE_URL=sqlite:///app/data/monitor.db
```

### 2. 前端服务 (frontend)

- **框架**: Vue 3 + Vite → Nginx
- **端口**: 80
- **功能**: 静态文件服务、反向代理
- **健康检查**: `/health`
- **架构**: 多阶段构建 (Builder + Nginx)

```yaml
frontend:
  build: ./frontend
  ports: ["80:80"]
  depends_on:
    backend:
      condition: service_healthy
```

## 📦 镜像构建过程

### 后端镜像构建

```dockerfile
# 1. 使用Python 3.11基础镜像
FROM python:3.11-slim

# 2. 安装系统依赖
RUN apt-get update && apt-get install -y gcc

# 3. 安装Python依赖
COPY requirements.txt .
RUN pip install -r requirements.txt

# 4. 复制应用代码
COPY . .

# 5. 启动服务
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 前端镜像构建 (多阶段构建)

```dockerfile
# 第一阶段: 构建前端
FROM node:18-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# 第二阶段: 生产环境 (Nginx)
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## 🌐 Nginx配置解析

`frontend/nginx.conf` 配置说明:

### 1. 静态文件服务
```nginx
location / {
    root /usr/share/nginx/html;
    try_files $uri $uri/ /index.html;
}
```

### 2. API代理
```nginx
location /api/ {
    proxy_pass http://backend:8000/api/;
    proxy_set_header Host $host;
    # 其他代理配置...
}
```

### 3. WebSocket代理
```nginx
location /ws {
    proxy_pass http://backend:8000/ws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

## 🔧 环境变量配置

创建 `.env` 文件来自定义配置:

```bash
# 端口配置
BACKEND_PORT=8000
FRONTEND_PORT=80

# 数据库配置
DATABASE_URL=sqlite:///app/data/monitor.db
# 生产环境可以使用PostgreSQL:
# DATABASE_URL=postgresql://admin:password@postgres:5432/servertracker

# 安全配置
SECRET_KEY=your-secret-key-here
CORS_ORIGINS=http://localhost,http://localhost:80

# 日志级别
LOG_LEVEL=INFO
```

## 📋 管理命令

### 服务管理
```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看服务日志
docker-compose logs -f [service_name]

# 重启服务
docker-compose restart [service_name]

# 停止所有服务
docker-compose down

# 重新构建并启动
docker-compose up -d --build
```

### 数据管理
```bash
# 备份数据库
cp data/monitor.db backup_$(date +%Y%m%d).db

# 清理Docker资源
docker system prune -f

# 完全清理(包括数据卷)
docker-compose down -v
```

## 🔍 故障排除

### 1. 端口占用问题
```bash
# 检查端口占用
lsof -i :80
lsof -i :8000

# 修改端口映射
# 编辑 docker-compose.yml 中的 ports 配置
```

### 2. 服务启动失败
```bash
# 查看详细日志
docker-compose logs backend
docker-compose logs frontend

# 检查容器状态
docker-compose ps -a
```

### 3. 数据库问题
```bash
# 检查数据目录权限
ls -la data/

# 重新初始化数据库
docker-compose down
rm -rf data/*
docker-compose up -d
```

### 4. 构建失败
```bash
# 清理Docker缓存
docker system prune -a

# 强制重新构建
docker-compose build --no-cache
```

## 🚀 生产环境部署

### 1. 使用生产环境配置

```bash
# 创建生产环境配置
cp .env.example .env.production

# 编辑生产环境变量
vim .env.production

# 使用生产环境配置启动
docker-compose --env-file .env.production up -d
```

### 2. 启用PostgreSQL (可选)

取消 `docker-compose.yml` 中 PostgreSQL 服务的注释:

```yaml
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: servertracker
    POSTGRES_USER: admin
    POSTGRES_PASSWORD: your-secure-password
  volumes:
    - postgres_data:/var/lib/postgresql/data
```

### 3. SSL/HTTPS配置

创建自定义nginx配置:

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    
    # 其他配置...
}
```

## 🔐 安全建议

1. **修改默认密码**: 更新 `.env` 文件中的所有默认密码
2. **限制CORS**: 在生产环境中限制允许的域名
3. **网络安全**: 配置防火墙规则，只开放必要端口
4. **定期备份**: 设置定期数据库备份任务
5. **监控日志**: 配置日志监控和告警

## 📊 性能优化

1. **数据库优化**: 生产环境使用PostgreSQL替代SQLite
2. **缓存**: 启用Redis缓存提高响应速度
3. **负载均衡**: 多实例部署使用负载均衡器
4. **CDN**: 使用CDN加速静态资源访问

## 🎯 总结

这个Docker部署方案提供了:

✅ **完整的容器化部署** - 包含后端API和前端界面  
✅ **自动化构建** - 前端自动构建后交由Nginx服务  
✅ **反向代理** - Nginx统一入口，处理API和WebSocket代理  
✅ **生产就绪** - 健康检查、数据持久化、环境配置  
✅ **易于管理** - 一键部署脚本和管理命令  
✅ **跨平台支持** - Linux、Mac、Windows全覆盖  

通过这个方案，您可以获得一个完整的、生产就绪的服务器监测工具部署环境。