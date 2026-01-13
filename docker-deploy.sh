#!/bin/bash

# Docker部署脚本
# 用于快速构建和部署服务器监测工具

set -e

echo "🐳 服务器监测工具 Docker 部署脚本"
echo "=================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查Docker是否安装
check_docker() {
    echo -e "${YELLOW}检查Docker环境...${NC}"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: 未找到Docker${NC}"
        echo "请先安装Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}错误: 未找到docker-compose${NC}"
        echo "请先安装docker-compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker环境检查通过${NC}"
}

# 检查端口占用
check_ports() {
    echo -e "${YELLOW}检查端口占用...${NC}"
    
    # 检查80端口
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${RED}警告: 端口80已被占用${NC}"
        echo "请停止占用80端口的服务或修改docker-compose.yml中的端口映射"
        read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # 检查8000端口
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 端口8000已被占用${NC}"
        echo "将在内部网络中使用，外部访问不受影响"
    fi
    
    echo -e "${GREEN}✓ 端口检查完成${NC}"
}

# 创建必要目录
create_directories() {
    echo -e "${YELLOW}创建必要目录...${NC}"
    mkdir -p data
    echo -e "${GREEN}✓ 目录创建完成${NC}"
}

# 构建镜像
build_images() {
    echo -e "${YELLOW}构建Docker镜像...${NC}"
    
    # 构建后端镜像
    echo -e "${BLUE}构建后端镜像...${NC}"
    docker-compose build backend
    echo -e "${GREEN}✓ 后端镜像构建完成${NC}"
    
    # 构建前端镜像
    echo -e "${BLUE}构建前端镜像...${NC}"
    docker-compose build frontend
    echo -e "${GREEN}✓ 前端镜像构建完成${NC}"
}

# 启动服务
start_services() {
    echo -e "${YELLOW}启动服务...${NC}"
    
    # 启动所有服务
    docker-compose up -d
    
    # 等待服务启动
    echo -e "${YELLOW}等待服务启动...${NC}"
    sleep 10
    
    # 检查服务状态
    check_services
}

# 检查服务状态
check_services() {
    echo -e "${YELLOW}检查服务状态...${NC}"
    
    # 检查后端服务
    if curl -s http://localhost:8000/api/health > /dev/null; then
        echo -e "${GREEN}✓ 后端服务运行正常${NC}"
    else
        echo -e "${RED}✗ 后端服务未响应${NC}"
        echo "查看后端日志: docker-compose logs backend"
    fi
    
    # 检查前端服务
    if curl -s http://localhost/ > /dev/null; then
        echo -e "${GREEN}✓ 前端服务运行正常${NC}"
    else
        echo -e "${RED}✗ 前端服务未响应${NC}"
        echo "查看前端日志: docker-compose logs frontend"
    fi
    
    # 显示容器状态
    echo -e "${BLUE}容器状态:${NC}"
    docker-compose ps
}

# 显示访问信息
show_info() {
    echo ""
    echo -e "${GREEN}🎉 部署完成！${NC}"
    echo "================================"
    echo -e "${GREEN}前端界面: http://localhost${NC}"
    echo -e "${GREEN}API文档: http://localhost/api/docs${NC}"
    echo -e "${GREEN}后端API: http://localhost:8000${NC}"
    echo ""
    echo -e "${YELLOW}Docker管理命令:${NC}"
    echo "  查看服务状态: docker-compose ps"
    echo "  查看服务日志: docker-compose logs -f [service_name]"
    echo "  重启服务: docker-compose restart [service_name]"
    echo "  停止服务: docker-compose down"
    echo "  重建服务: docker-compose up -d --build"
    echo ""
    echo -e "${YELLOW}探针配置:${NC}"
    echo "  服务器地址: http://localhost:8000"
    echo "  配置文件: ./probe/probe_config.json"
    echo "  运行探针: cd probe && python server_probe.py"
}

# 停止服务
stop_services() {
    echo -e "${YELLOW}停止所有服务...${NC}"
    docker-compose down
    echo -e "${GREEN}✓ 所有服务已停止${NC}"
}

# 清理资源
cleanup() {
    echo -e "${YELLOW}清理Docker资源...${NC}"
    docker-compose down -v --remove-orphans
    docker system prune -f
    echo -e "${GREEN}✓ 资源清理完成${NC}"
}

# 查看日志
show_logs() {
    echo -e "${YELLOW}显示服务日志...${NC}"
    echo "按 Ctrl+C 退出日志查看"
    docker-compose logs -f
}

# 备份数据库
backup_db() {
    echo -e "${YELLOW}备份数据库...${NC}"
    backup_file="backup_$(date +%Y%m%d_%H%M%S).db"
    if [ -f "data/monitor.db" ]; then
        cp data/monitor.db "data/$backup_file"
        echo -e "${GREEN}✓ 数据库已备份到: data/$backup_file${NC}"
    else
        echo -e "${YELLOW}未找到数据库文件${NC}"
    fi
}

# 主函数
main() {
    case "${1:-start}" in
        "start")
            check_docker
            check_ports
            create_directories
            build_images
            start_services
            show_info
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            stop_services
            sleep 2
            start_services
            ;;
        "logs")
            show_logs
            ;;
        "status")
            check_services
            ;;
        "build")
            check_docker
            build_images
            ;;
        "cleanup")
            read -p "确定要清理所有Docker资源吗? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup
            fi
            ;;
        "backup")
            backup_db
            ;;
        *)
            echo "使用方法: $0 {start|stop|restart|logs|status|build|cleanup|backup}"
            echo ""
            echo "命令说明:"
            echo "  start    - 启动所有服务 (默认)"
            echo "  stop     - 停止所有服务"
            echo "  restart  - 重启所有服务"
            echo "  logs     - 显示服务日志"
            echo "  status   - 检查服务状态"
            echo "  build    - 仅构建镜像"
            echo "  cleanup  - 清理Docker资源"
            echo "  backup   - 备份数据库"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"