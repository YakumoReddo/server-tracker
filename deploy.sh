#!/bin/bash

# 服务器监测工具部署脚本
# 用于快速部署后端服务、前端界面和探针

set -e

echo "🚀 服务器监测工具部署脚本"
echo "================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查Python环境
check_python() {
    echo -e "${YELLOW}检查Python环境...${NC}"
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}错误: 未找到Python3${NC}"
        exit 1
    fi
    python_version=$(python3 --version | cut -d' ' -f2)
    echo -e "${GREEN}✓ Python版本: $python_version${NC}"
}

# 检查Node.js环境
check_nodejs() {
    echo -e "${YELLOW}检查Node.js环境...${NC}"
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}警告: 未找到Node.js (前端需要)${NC}"
        return 1
    fi
    node_version=$(node --version)
    echo -e "${GREEN}✓ Node.js版本: $node_version${NC}"
    return 0
}

# 安装后端依赖
install_backend() {
    echo -e "${YELLOW}安装后端依赖...${NC}"
    cd backend
    pip3 install -r requirements.txt
    echo -e "${GREEN}✓ 后端依赖安装完成${NC}"
    cd ..
}

# 安装前端依赖
install_frontend() {
    echo -e "${YELLOW}安装前端依赖...${NC}"
    cd frontend
    npm install
    echo -e "${GREEN}✓ 前端依赖安装完成${NC}"
    cd ..
}

# 启动后端服务
start_backend() {
    echo -e "${YELLOW}启动后端服务...${NC}"
    cd backend
    
    # 创建后台进程
    nohup uvicorn main:app --host 0.0.0.0 --port 8000 > backend.log 2>&1 &
    BACKEND_PID=$!
    
    echo $BACKEND_PID > ../backend.pid
    echo -e "${GREEN}✓ 后端服务启动 (PID: $BACKEND_PID)${NC}"
    echo -e "${GREEN}✓ API地址: http://localhost:8000${NC}"
    
    cd ..
}

# 启动前端服务
start_frontend() {
    echo -e "${YELLOW}启动前端服务...${NC}"
    cd frontend
    
    # 创建后台进程
    nohup npm run dev > ../frontend.log 2>&1 &
    FRONTEND_PID=$!
    
    echo $FRONTEND_PID > ../frontend.pid
    echo -e "${GREEN}✓ 前端服务启动 (PID: $FRONTEND_PID)${NC}"
    echo -e "${GREEN}✓ 前端地址: http://localhost:5173${NC}"
    
    cd ..
}

# 检查服务状态
check_services() {
    echo -e "${YELLOW}检查服务状态...${NC}"
    
    # 检查后端
    if curl -s http://localhost:8000/api/health > /dev/null; then
        echo -e "${GREEN}✓ 后端服务运行正常${NC}"
    else
        echo -e "${RED}✗ 后端服务未响应${NC}"
    fi
    
    # 检查前端
    if curl -s http://localhost:5173 > /dev/null; then
        echo -e "${GREEN}✓ 前端服务运行正常${NC}"
    else
        echo -e "${RED}✗ 前端服务未响应${NC}"
    fi
}

# 创建示例服务器
create_sample_server() {
    echo -e "${YELLOW}创建示例服务器配置...${NC}"
    
    # 等待后端服务启动
    sleep 3
    
    curl -X POST "http://localhost:8000/api/servers" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "本地服务器",
        "host": "localhost",
        "port": 22,
        "description": "当前服务器"
      }' 2>/dev/null
    
    echo -e "${GREEN}✓ 示例服务器创建完成${NC}"
}

# 显示使用指南
show_usage() {
    echo ""
    echo -e "${GREEN}🎉 部署完成！${NC}"
    echo "================================"
    echo -e "${GREEN}前端界面: http://localhost:5173${NC}"
    echo -e "${GREEN}API文档: http://localhost:8000/docs${NC}"
    echo ""
    echo -e "${YELLOW}下一步操作:${NC}"
    echo "1. 访问前端界面查看监控面板"
    echo "2. 获取服务器探针密钥"
    echo "3. 在其他服务器上部署探针"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  停止服务: ./deploy.sh stop"
    echo "  重启服务: ./deploy.sh restart"
    echo "  查看日志: tail -f *.log"
    echo ""
}

# 停止服务
stop_services() {
    echo -e "${YELLOW}停止所有服务...${NC}"
    
    if [ -f backend.pid ]; then
        kill $(cat backend.pid) 2>/dev/null || true
        rm backend.pid
        echo -e "${GREEN}✓ 后端服务已停止${NC}"
    fi
    
    if [ -f frontend.pid ]; then
        kill $(cat frontend.pid) 2>/dev/null || true
        rm frontend.pid
        echo -e "${GREEN}✓ 前端服务已停止${NC}"
    fi
}

# 主函数
main() {
    case "${1:-start}" in
        "start")
            check_python
            if check_nodejs; then
                install_backend
                install_frontend
                start_backend
                start_frontend
                sleep 5
                check_services
                create_sample_server
                show_usage
            else
                echo -e "${YELLOW}由于未找到Node.js，跳过前端部署${NC}"
                install_backend
                start_backend
                sleep 3
                check_services
                show_usage
            fi
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            stop_services
            sleep 2
            main start
            ;;
        *)
            echo "使用方法: $0 {start|stop|restart}"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"