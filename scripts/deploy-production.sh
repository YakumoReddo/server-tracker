#!/bin/bash

# 服务器探针项目 - 生产环境部署脚本
# Author: Server Tracker Team
# Description: 部署生产环境服务

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 默认参数
IMAGE_TAG="latest"
ENVIRONMENT="production"
BACKUP_DATA=true

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --no-backup)
            BACKUP_DATA=false
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -t, --tag TAG      指定镜像标签 (默认: latest)"
            echo "  -e, --env ENV      指定环境 (默认: production)"
            echo "  --no-backup        跳过数据备份"
            echo "  -h, --help         显示帮助信息"
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            exit 1
            ;;
    esac
done

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装或不可用"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装或不可用"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 备份数据
backup_data() {
    if [ "$BACKUP_DATA" = false ]; then
        log_info "跳过数据备份 (--no-backup)"
        return 0
    fi
    
    log_info "备份现有数据..."
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份数据库
    if docker volume ls | grep -q servertracker_data; then
        log_info "备份数据库卷..."
        docker run --rm -v servertracker_data:/data -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/database.tar.gz -C /data .
        log_success "数据库备份完成: $BACKUP_DIR/database.tar.gz"
    fi
    
    # 备份环境配置
    if [ -f ".env" ]; then
        log_info "备份环境配置..."
        cp .env "$BACKUP_DIR/.env.backup"
        log_success "环境配置备份完成: $BACKUP_DIR/.env.backup"
    fi
    
    log_success "数据备份完成"
}

# 停止现有服务
stop_existing_services() {
    log_info "停止现有服务..."
    
    # 检查生产配置文件是否存在
    if [ ! -f "docker-compose.production.yml" ]; then
        log_error "生产配置文件不存在: docker-compose.production.yml"
        exit 1
    fi
    
    # 停止现有容器
    docker-compose -f docker-compose.production.yml down --remove-orphans
    
    log_success "现有服务已停止"
}

# 部署新版本
deploy_services() {
    log_info "部署服务 (镜像标签: $IMAGE_TAG)..."
    
    # 设置镜像标签环境变量
    export BACKEND_IMAGE_TAG="$IMAGE_TAG"
    export FRONTEND_IMAGE_TAG="$IMAGE_TAG"
    
    # 启动服务
    docker-compose -f docker-compose.production.yml up -d
    
    if [ $? -eq 0 ]; then
        log_success "服务部署成功!"
    else
        log_error "服务部署失败"
        exit 1
    fi
}

# 等待服务就绪
wait_for_services() {
    log_info "等待服务就绪..."
    
    # 等待后端服务
    log_info "等待后端服务启动..."
    timeout=60
    count=0
    while [ $count -lt $timeout ]; do
        if curl -f http://localhost:8000/api/health >/dev/null 2>&1; then
            log_success "后端服务就绪"
            break
        fi
        sleep 2
        count=$((count + 2))
        if [ $count -eq $timeout ]; then
            log_error "后端服务启动超时"
            exit 1
        fi
    done
    
    # 等待前端服务
    log_info "等待前端服务启动..."
    count=0
    while [ $count -lt $timeout ]; do
        if curl -f http://localhost/health >/dev/null 2>&1; then
            log_success "前端服务就绪"
            break
        fi
        sleep 2
        count=$((count + 2))
        if [ $count -eq $timeout ]; then
            log_error "前端服务启动超时"
            exit 1
        fi
    done
}

# 显示部署结果
show_deployment_info() {
    echo ""
    log_success "生产环境部署完成!"
    echo ""
    log_info "服务访问地址:"
    echo "  - 前端服务: http://localhost:80"
    echo "  - 后端API: http://localhost:8000 (内部网络)"
    echo "  - 后端API文档: http://localhost:8000/docs"
    echo ""
    
    log_info "容器状态:"
    docker-compose -f docker-compose.production.yml ps
    
    echo ""
    log_info "查看日志:"
    echo "  docker-compose -f docker-compose.production.yml logs -f"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 检查容器状态
    if ! docker-compose -f docker-compose.production.yml ps | grep -q "Up"; then
        log_error "部分容器未正常运行"
        return 1
    fi
    
    # 检查API响应
    if ! curl -f http://localhost:8000/api/health >/dev/null 2>&1; then
        log_error "后端API健康检查失败"
        return 1
    fi
    
    if ! curl -f http://localhost/health >/dev/null 2>&1; then
        log_error "前端服务健康检查失败"
        return 1
    fi
    
    log_success "健康检查通过"
}

# 主函数
main() {
    echo "================================================"
    echo "      服务器探针项目 - 生产环境部署"
    echo "================================================"
    echo ""
    
    check_dependencies
    backup_data
    stop_existing_services
    deploy_services
    wait_for_services
    health_check
    show_deployment_info
}

# 捕获中断信号
trap 'log_info "脚本被中断" && exit 1' INT

# 执行主函数
main "$@"