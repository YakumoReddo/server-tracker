#!/bin/bash

# 服务器探针项目 - 生产镜像构建脚本
# Author: Server Tracker Team
# Description: 构建所有服务的生产镜像

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
PUSH_REGISTRY=false
REGISTRY_URL=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -p|--push)
            PUSH_REGISTRY=true
            shift
            ;;
        -r|--registry)
            REGISTRY_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -t, --tag TAG     指定镜像标签 (默认: latest)"
            echo "  -p, --push        构建后推送到仓库"
            echo "  -r, --registry URL 指定仓库地址"
            echo "  -h, --help        显示帮助信息"
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

# 构建镜像
build_images() {
    log_info "开始构建生产镜像..."
    
    # 设置镜像标签
    BACKEND_IMAGE="servertracker-backend:${IMAGE_TAG}"
    FRONTEND_IMAGE="servertracker-frontend:${IMAGE_TAG}"
    
    if [ -n "$REGISTRY_URL" ]; then
        BACKEND_IMAGE="${REGISTRY_URL}/${BACKEND_IMAGE}"
        FRONTEND_IMAGE="${REGISTRY_URL}/${FRONTEND_IMAGE}"
    fi
    
    # 构建后端镜像
    log_info "构建后端镜像: $BACKEND_IMAGE"
    docker build -t "$BACKEND_IMAGE" -f backend/Dockerfile backend/
    
    if [ $? -eq 0 ]; then
        log_success "后端镜像构建成功"
    else
        log_error "后端镜像构建失败"
        exit 1
    fi
    
    # 构建前端镜像
    log_info "构建前端镜像: $FRONTEND_IMAGE"
    docker build -t "$FRONTEND_IMAGE" -f frontend/Dockerfile frontend/
    
    if [ $? -eq 0 ]; then
        log_success "前端镜像构建成功"
    else
        log_error "前端镜像构建失败"
        exit 1
    fi
    
    # 标记本地镜像 (如果指定了仓库)
    if [ -n "$REGISTRY_URL" ] && [ "$PUSH_REGISTRY" = false ]; then
        log_info "标记镜像用于推送..."
        docker tag "$BACKEND_IMAGE" "${REGISTRY_URL}/servertracker-backend:${IMAGE_TAG}"
        docker tag "$FRONTEND_IMAGE" "${REGISTRY_URL}/servertracker-frontend:${IMAGE_TAG}"
    fi
}

# 推送镜像到仓库
push_images() {
    if [ "$PUSH_REGISTRY" = false ]; then
        return 0
    fi
    
    if [ -z "$REGISTRY_URL" ]; then
        log_error "推送镜像需要指定仓库地址"
        exit 1
    fi
    
    log_info "推送镜像到仓库: $REGISTRY_URL"
    
    # 推送后端镜像
    docker push "${REGISTRY_URL}/servertracker-backend:${IMAGE_TAG}"
    if [ $? -eq 0 ]; then
        log_success "后端镜像推送成功"
    else
        log_error "后端镜像推送失败"
        exit 1
    fi
    
    # 推送前端镜像
    docker push "${REGISTRY_URL}/servertracker-frontend:${IMAGE_TAG}"
    if [ $? -eq 0 ]; then
        log_success "前端镜像推送成功"
    else
        log_error "前端镜像推送失败"
        exit 1
    fi
}

# 显示构建结果
show_results() {
    echo ""
    log_success "镜像构建完成!"
    echo ""
    log_info "构建的镜像:"
    docker images | grep servertracker
    
    if [ -n "$REGISTRY_URL" ]; then
        echo ""
        log_info "仓库地址:"
        echo "  后端: ${REGISTRY_URL}/servertracker-backend:${IMAGE_TAG}"
        echo "  前端: ${REGISTRY_URL}/servertracker-frontend:${IMAGE_TAG}"
    fi
    
    echo ""
    log_info "部署命令:"
    echo "  docker-compose -f docker-compose.production.yml up -d"
}

# 主函数
main() {
    echo "================================================"
    echo "      服务器探针项目 - 生产镜像构建"
    echo "================================================"
    echo ""
    
    check_dependencies
    build_images
    push_images
    show_results
}

# 捕获中断信号
trap 'log_info "脚本被中断" && exit 1' INT

# 执行主函数
main "$@"