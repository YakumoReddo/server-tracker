#!/bin/bash

# 服务器探针项目 - 开发环境一键启动脚本
# Author: Server Tracker Team
# Description: 启动开发环境容器，支持热重载

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查Docker和Docker Compose
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

# 检查环境变量文件
check_env_file() {
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            log_warning ".env 文件不存在，复制 .env.example"
            cp .env.example .env
            log_info "请根据需要修改 .env 文件中的配置"
        else
            log_warning ".env 文件不存在，使用默认配置"
        fi
    fi
}

# 停止现有容器（如果存在）
stop_existing_containers() {
    log_info "检查并停止现有容器..."
    docker-compose down --remove-orphans 2>/dev/null || true
    log_success "容器清理完成"
}

# 启动开发环境
start_dev_environment() {
    log_info "启动开发环境..."
    
    # 启动服务
    docker-compose up -d --build
    
    if [ $? -eq 0 ]; then
        log_success "开发环境启动成功!"
        
        echo ""
        log_info "服务访问地址:"
        echo "  - 前端开发服务器: http://localhost:3000"
        echo "  - 后端API: http://localhost:8000"
        echo "  - 后端API文档: http://localhost:8000/docs"
        echo ""
        
        # 显示日志
        log_info "显示容器日志 (按 Ctrl+C 退出日志模式):"
        docker-compose logs -f
        
    else
        log_error "开发环境启动失败"
        exit 1
    fi
}

# 主函数
main() {
    echo "================================================"
    echo "          服务器探针项目 - 开发环境启动"
    echo "================================================"
    echo ""
    
    check_dependencies
    check_env_file
    stop_existing_containers
    start_dev_environment
}

# 捕获中断信号
trap 'log_info "脚本被中断" && exit 1' INT

# 执行主函数
main "$@"