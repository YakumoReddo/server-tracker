#!/bin/bash
# 前端部署脚本 - 自动配置后端API地址

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助信息
show_help() {
    echo -e "${BLUE}前端部署脚本${NC}"
    echo ""
    echo "用法: $0 [OPTIONS] [ENVIRONMENT] [API_URL]"
    echo ""
    echo "参数:"
    echo "  ENVIRONMENT    部署环境 (development|staging|production)"
    echo "  API_URL        后端API地址"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -d, --dev      使用开发环境配置"
    echo "  -p, --prod     使用生产环境配置"
    echo "  -s, --staging  使用预发布环境配置"
    echo ""
    echo "示例:"
    echo "  $0 production https://api.example.com:8000"
    echo "  $0 development http://localhost:8000"
    echo "  $0 -p https://prod.domain.com:8000"
    echo ""
}

# 检查参数
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 解析参数
ENV=""
API_URL=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dev)
            ENV="development"
            API_URL=${2:-"http://localhost:8000"}
            shift 2
            ;;
        -p|--prod)
            ENV="production"
            API_URL=${2:-"https://api.example.com:8000"}
            shift 2
            ;;
        -s|--staging)
            ENV="staging"
            API_URL=${2:-"https://staging.example.com:8000"}
            shift 2
            ;;
        development|staging|production)
            ENV="$1"
            API_URL=${2:-""}
            if [[ -z "$API_URL" ]]; then
                case $ENV in
                    development) API_URL="http://localhost:8000" ;;
                    staging) API_URL="https://staging.example.com:8000" ;;
                    production) API_URL="https://api.example.com:8000" ;;
                esac
            fi
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# 验证API_URL
if [[ -z "$API_URL" ]]; then
    echo -e "${RED}错误: 必须提供API地址${NC}"
    show_help
    exit 1
fi

# 验证URL格式
if [[ ! "$API_URL" =~ ^https?:// ]]; then
    echo -e "${RED}错误: API地址必须是有效的HTTP或HTTPS URL${NC}"
    exit 1
fi

# 检查是否在正确的目录
if [[ ! -f "frontend/package.json" ]]; then
    echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 开始前端部署 (环境: $ENV)${NC}"
echo -e "${BLUE}📍 API地址: $API_URL${NC}"

# 进入前端目录
cd frontend

# 检查Node.js和npm
if ! command -v node &> /dev/null; then
    echo -e "${RED}错误: Node.js未安装${NC}"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo -e "${RED}错误: npm未安装${NC}"
    exit 1
fi

# 检查依赖
if [[ ! -d "node_modules" ]]; then
    echo -e "${YELLOW}📦 安装依赖...${NC}"
    npm install
fi

# 创建环境配置文件
ENV_FILE=".env"
ENV_CONTENT="# 自动生成的环境配置
# 环境: $ENV
# 生成时间: $(date)
# API地址: $API_URL

VITE_PUBLISH_URL=$API_URL
"

echo -e "${YELLOW}📝 创建环境配置文件...${NC}"
echo "$ENV_CONTENT" > "$ENV_FILE"

# 显示配置信息
echo -e "${GREEN}✅ 环境配置:${NC}"
echo "  环境: $ENV"
echo "  API地址: $API_URL"
echo "  配置文件: $ENV_FILE"

# 构建前端
echo -e "${YELLOW}🔨 开始构建前端...${NC}"
if [[ "$VERBOSE" == true ]]; then
    npm run build
else
    npm run build > /dev/null 2>&1
fi

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ 前端构建成功!${NC}"
else
    echo -e "${RED}❌ 前端构建失败!${NC}"
    exit 1
fi

# 显示构建结果
if [[ -d "dist" ]]; then
    echo -e "${GREEN}📦 构建产物:${NC}"
    echo "  目录: frontend/dist"
    echo "  文件:"
    find dist -type f -name "*.html" -o -name "*.js" -o -name "*.css" | head -10 | while read file; do
        echo "    $(ls -lh "$file" | awk '{print $5}')  $file"
    done
    
    if [[ $(find dist -type f | wc -l) -gt 10 ]]; then
        echo "    ... 和其他文件"
    fi
fi

# 提供下一步指导
echo ""
echo -e "${GREEN}🎉 部署完成!${NC}"
echo -e "${BLUE}下一步:${NC}"
echo "  1. 将 frontend/dist 目录上传到Web服务器"
echo "  2. 确保后端服务运行在: $API_URL"
echo "  3. 测试前端是否能正常连接到后端"

echo ""
echo -e "${YELLOW}💡 提示:${NC}"
if [[ "$ENV" == "development" ]]; then
    echo "  开发环境: 可以使用 npm run dev 启动开发服务器"
elif [[ "$ENV" == "production" ]]; then
    echo "  生产环境: 建议配置CDN和HTTPS"
fi

cd ..  # 回到项目根目录

echo ""
echo -e "${GREEN}✨ 部署脚本执行完成!${NC}"