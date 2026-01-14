#!/bin/bash

# 服务器探针项目 - 停止开发环境脚本
# Author: Server Tracker Team
# Description: 停止并清理开发环境容器

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
CLEAN_VOLUMES=false
CLEAN_IMAGES=false
FORCE=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--volumes)
            CLEAN_VOLUMES=true
            shift
            ;;
        -i|--images)
            CLEAN_IMAGES=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -v, --volumes    同时清理数据卷"
            echo "  -i, --images     同时清理相关镜像"
            echo "  -f, --force      强制清理，不询问确认"
            echo "  -h, --help       显示帮助信息"
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
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装或不可用"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装或不可用"
        exit 1
    fi
}

# 显示当前容器状态
show_container_status() {
    log_info "当前开发环境容器状态:"
    
    if docker-compose ps | grep -q "servertracker"; then
        docker-compose ps
    else
        log_info "没有运行中的开发环境容器"
    fi
}

# 停止容器
stop_containers() {
    log_info "停止开发环境容器..."
    
    # 检查是否有容器在运行
    if ! docker-compose ps | grep -q "Up"; then
        log_info "没有需要停止的容器"
        return 0
    fi
    
    # 停止容器
    docker-compose down --remove-orphans
    
    if [ $? -eq 0 ]; then
        log_success "容器已停止"
    else
        log_error "停止容器时发生错误"
        exit 1
    fi
}

# 清理数据卷
clean_volumes() {
    if [ "$CLEAN_VOLUMES" = false ]; then
        return 0
    fi
    
    log_warning "清理数据卷..."
    
    # 检查是否有相关卷
    if docker volume ls | grep -q "servertracker_data"; then
        if [ "$FORCE" = false ]; then
            read -p "确定要删除数据卷吗？这将删除所有数据! (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "跳过数据卷清理"
                return 0
            fi
        fi
        
        docker volume rm servertracker_data 2>/dev/null || true
        log_success "数据卷已清理"
    else
        log_info "没有找到相关数据卷"
    fi
}

# 清理镜像
clean_images() {
    if [ "$CLEAN_IMAGES" = false ]; then
        return 0
    fi
    
    log_warning "清理开发环境镜像..."
    
    # 查找相关镜像
    local images=$(docker images | grep "servertracker.*dev" | awk '{print $1":"$2}' || true)
    
    if [ -n "$images" ]; then
        if [ "$FORCE" = false ]; then
            read -p "确定要删除相关镜像吗? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "跳过镜像清理"
                return 0
            fi
        fi
        
        echo "$images" | xargs -r docker rmi
        log_success "镜像已清理"
    else
        log_info "没有找到相关镜像"
    fi
}

# 清理node_modules (如果存在)
clean_node_modules() {
    if [ -d "frontend/node_modules" ]; then
        log_info "清理前端node_modules..."
        rm -rf frontend/node_modules
        log_success "前端node_modules已清理"
    fi
}

# 显示清理结果
show_cleanup_results() {
    echo ""
    log_success "开发环境已完全停止并清理!"
    echo ""
    
    if [ "$CLEAN_VOLUMES" = true ]; then
        log_info "✓ 数据卷已清理"
    fi
    
    if [ "$CLEAN_IMAGES" = true ]; then
        log_info "✓ 开发环境镜像已清理"
    fi
    
    echo ""
    log_info "要重新启动开发环境，请运行:"
    echo "  ./scripts/dev-start.sh"
}

# 主函数
main() {
    echo "================================================"
    echo "      服务器探针项目 - 停止开发环境"
    echo "================================================"
    echo ""
    
    check_dependencies
    show_container_status
    
    if [ "$FORCE" = false ]; then
        echo ""
        read -p "确定要停止开发环境吗? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    stop_containers
    clean_volumes
    clean_images
    clean_node_modules
    show_cleanup_results
}

# 捕获中断信号
trap 'log_info "脚本被中断" && exit 1' INT

# 执行主函数
main "$@"