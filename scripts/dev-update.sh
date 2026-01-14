#!/bin/bash

# 服务器探针项目 - Git更新并重启开发容器脚本
# Author: Server Tracker Team
# Description: 一键从git pull最新版本并重启开发容器

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

# 检查Git状态
check_git_status() {
    log_info "检查Git状态..."
    
    if [ ! -d ".git" ]; then
        log_error "当前目录不是Git仓库"
        exit 1
    fi
    
    # 检查是否有未提交的更改
    if ! git diff-index --quiet HEAD --; then
        log_warning "检测到未提交的更改:"
        git status --short
        read -p "是否继续更新? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "更新已取消"
            exit 0
        fi
    fi
    
    log_success "Git状态检查完成"
}

# 获取最新代码
pull_latest_code() {
    log_info "获取最新代码..."
    
    # 获取最新分支信息
    git fetch origin
    
    # 获取当前分支名
    CURRENT_BRANCH=$(git branch --show-current)
    log_info "当前分支: $CURRENT_BRANCH"
    
    # 拉取最新代码
    git pull origin "$CURRENT_BRANCH"
    
    if [ $? -eq 0 ]; then
        log_success "代码更新成功"
    else
        log_error "代码更新失败"
        exit 1
    fi
}

# 检查依赖变更
check_dependency_changes() {
    log_info "检查依赖变更..."
    
    BACKEND_CHANGED=false
    FRONTEND_CHANGED=false
    
    # 检查后端依赖变更
    if git diff --name-only HEAD~1 HEAD | grep -q "^backend/requirements.txt$"; then
        BACKEND_CHANGED=true
        log_warning "后端依赖发生变化，需要重新构建后端镜像"
    fi
    
    # 检查前端依赖变更
    if git diff --name-only HEAD~1 HEAD | grep -q "^frontend/package.json$"; then
        FRONTEND_CHANGED=true
        log_warning "前端依赖发生变化，需要重新构建前端镜像"
    fi
    
    if [ "$BACKEND_CHANGED" = false ] && [ "$FRONTEND_CHANGED" = false ]; then
        log_info "依赖文件无变更，可以直接重启容器"
    fi
}

# 重启开发环境
restart_dev_environment() {
    log_info "重启开发环境..."
    
    # 停止现有容器
    docker-compose down --remove-orphans
    
    # 根据依赖变更决定是否重新构建
    if [ "$BACKEND_CHANGED" = true ] || [ "$FRONTEND_CHANGED" = true ]; then
        log_info "检测到依赖变更，重新构建镜像..."
        docker-compose up -d --build
    else
        log_info "无依赖变更，直接启动容器..."
        docker-compose up -d
    fi
    
    if [ $? -eq 0 ]; then
        log_success "开发环境重启成功!"
        
        echo ""
        log_info "服务访问地址:"
        echo "  - 前端开发服务器: http://localhost:3000"
        echo "  - 后端API: http://localhost:8000"
        echo "  - 后端API文档: http://localhost:8000/docs"
        echo ""
        
    else
        log_error "开发环境重启失败"
        exit 1
    fi
}

# 主函数
main() {
    echo "================================================"
    echo "      服务器探针项目 - Git更新开发环境"
    echo "================================================"
    echo ""
    
    check_git_status
    pull_latest_code
    check_dependency_changes
    restart_dev_environment
}

# 捕获中断信号
trap 'log_info "脚本被中断" && exit 1' INT

# 执行主函数
main "$@"