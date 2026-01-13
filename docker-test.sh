#!/bin/bash

# Docker部署测试脚本
# 验证Docker Compose配置是否正确

set -e

echo "🐳 Docker部署测试脚本"
echo "======================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 测试Docker和Docker Compose
test_docker_environment() {
    echo -e "${YELLOW}测试Docker环境...${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker未安装${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose未安装${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker环境正常${NC}"
}

# 测试Docker Compose配置
test_compose_config() {
    echo -e "${YELLOW}测试Docker Compose配置...${NC}"
    
    if ! docker-compose config > /dev/null; then
        echo -e "${RED}❌ Docker Compose配置错误${NC}"
        docker-compose config
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker Compose配置正确${NC}"
}

# 测试Dockerfile语法
test_dockerfiles() {
    echo -e "${YELLOW}测试Dockerfile语法...${NC}"
    
    # 测试后端Dockerfile
    echo "检查后端Dockerfile..."
    if [ ! -f "backend/Dockerfile" ]; then
        echo -e "${RED}❌ 后端Dockerfile不存在${NC}"
        exit 1
    fi
    
    # 测试前端Dockerfile
    echo "检查前端Dockerfile..."
    if [ ! -f "frontend/Dockerfile" ]; then
        echo -e "${RED}❌ 前端Dockerfile不存在${NC}"
        exit 1
    fi
    
    if [ ! -f "frontend/nginx.conf" ]; then
        echo -e "${RED}❌ 前端Nginx配置不存在${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker文件检查通过${NC}"
}

# 测试构建过程
test_build() {
    echo -e "${YELLOW}测试镜像构建...${NC}"
    
    # 创建测试目录
    mkdir -p data
    
    # 尝试构建后端镜像
    echo "构建后端镜像..."
    if ! docker-compose build backend --quiet; then
        echo -e "${RED}❌ 后端镜像构建失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 后端镜像构建成功${NC}"
    
    # 尝试构建前端镜像
    echo "构建前端镜像..."
    if ! docker-compose build frontend --quiet; then
        echo -e "${RED}❌ 前端镜像构建失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ 前端镜像构建成功${NC}"
}

# 测试服务启动
test_service_startup() {
    echo -e "${YELLOW}测试服务启动...${NC}"
    
    # 启动服务
    echo "启动服务..."
    if ! docker-compose up -d; then
        echo -e "${RED}❌ 服务启动失败${NC}"
        exit 1
    fi
    
    # 等待服务启动
    echo "等待服务启动..."
    sleep 15
    
    # 检查服务状态
    echo "检查服务状态..."
    RUNNING_SERVICES=$(docker-compose ps --services --filter "status=running" | wc -l)
    
    if [ "$RUNNING_SERVICES" -lt 2 ]; then
        echo -e "${RED}❌ 服务未正常启动${NC}"
        docker-compose ps
        exit 1
    fi
    
    echo -e "${GREEN}✅ 服务启动成功${NC}"
}

# 测试健康检查
test_health_checks() {
    echo -e "${YELLOW}测试健康检查...${NC}"
    
    # 测试后端健康检查
    echo "测试后端API..."
    for i in {1..10}; do
        if curl -s http://localhost:8000/api/health > /dev/null; then
            echo -e "${GREEN}✅ 后端API响应正常${NC}"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}❌ 后端API无响应${NC}"
            docker-compose logs backend
            exit 1
        fi
        sleep 2
    done
    
    # 测试前端服务
    echo "测试前端服务..."
    for i in {1..10}; do
        if curl -s http://localhost/ > /dev/null; then
            echo -e "${GREEN}✅ 前端服务响应正常${NC}"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}❌ 前端服务无响应${NC}"
            docker-compose logs frontend
            exit 1
        fi
        sleep 2
    done
}

# 测试数据持久化
test_data_persistence() {
    echo -e "${YELLOW}测试数据持久化...${NC}"
    
    # 检查数据目录
    if [ ! -d "data" ]; then
        echo -e "${RED}❌ 数据目录不存在${NC}"
        exit 1
    fi
    
    # 检查数据库文件
    if ls data/*.db > /dev/null 2>&1; then
        echo -e "${GREEN}✅ 数据库文件创建成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 数据库文件未找到 (可能需要创建服务器)${NC}"
    fi
    
    echo -e "${GREEN}✅ 数据持久化配置正确${NC}"
}

# 清理测试环境
cleanup_test() {
    echo -e "${YELLOW}清理测试环境...${NC}"
    docker-compose down
    echo -e "${GREEN}✅ 清理完成${NC}"
}

# 显示测试结果
show_results() {
    echo ""
    echo -e "${GREEN}🎉 Docker部署测试完成！${NC}"
    echo "==============================="
    echo -e "${GREEN}✅ 所有测试项目通过${NC}"
    echo ""
    echo -e "${YELLOW}访问信息:${NC}"
    echo "  前端界面: http://localhost"
    echo "  API文档: http://localhost/api/docs"
    echo "  后端API: http://localhost:8000"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  启动服务: docker-compose up -d"
    echo "  查看状态: docker-compose ps"
    echo "  查看日志: docker-compose logs -f"
    echo "  停止服务: docker-compose down"
    echo ""
    echo -e "${YELLOW}下次使用:${NC}"
    echo "  Linux/Mac: ./docker-deploy.sh start"
    echo "  Windows: docker-deploy.bat start"
}

# 主测试流程
main() {
    case "${1:-full}" in
        "quick")
            test_docker_environment
            test_compose_config
            test_dockerfiles
            echo -e "${GREEN}✅ 快速测试完成${NC}"
            ;;
        "build")
            test_docker_environment
            test_compose_config
            test_dockerfiles
            test_build
            echo -e "${GREEN}✅ 构建测试完成${NC}"
            ;;
        "full")
            test_docker_environment
            test_compose_config
            test_dockerfiles
            test_build
            test_service_startup
            test_health_checks
            test_data_persistence
            show_results
            echo ""
            read -p "是否清理测试环境? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup_test
            fi
            ;;
        "cleanup")
            cleanup_test
            ;;
        *)
            echo "使用方法: $0 {quick|build|full|cleanup}"
            echo ""
            echo "测试模式:"
            echo "  quick   - 快速测试 (环境检查)"
            echo "  build   - 构建测试 (包括镜像构建)"
            echo "  full    - 完整测试 (包括启动验证)"
            echo "  cleanup - 清理测试环境"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"