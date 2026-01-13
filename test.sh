#!/bin/bash

# 服务器监测工具快速测试脚本
# 用于验证各个组件是否正常工作

echo "🚀 服务器监测工具测试"
echo "====================="

# 测试后端API
echo "测试后端API..."
cd backend
python -c "
from main import app
from database import create_tables
try:
    create_tables()
    print('✓ 数据库表创建成功')
    
    from services import ServerManager, MetricCollector
    from models import Server, ServerMetric
    print('✓ 服务模块导入成功')
    
    print('✓ 后端API测试通过')
except Exception as e:
    print('✗ 后端API测试失败:', e)
    exit(1)
"
cd ..

# 测试探针程序
echo "测试探针程序..."
cd probe
python -c "
from server_probe import ServerProbe
try:
    probe = ServerProbe('probe_config.json')
    print('✓ 探针程序初始化成功')
    
    # 测试数据收集
    import json
    with open('probe_config.json', 'r') as f:
        config = json.load(f)
    print('✓ 配置文件读取成功')
    
    print('✓ 探针程序测试通过')
except Exception as e:
    print('✗ 探针程序测试失败:', e)
    exit(1)
"
cd ..

# 测试前端文件
echo "测试前端文件..."
if [ -f "frontend/src/App.vue" ] && [ -f "frontend/src/main.js" ]; then
    echo "✓ 前端文件存在"
else
    echo "✗ 前端文件缺失"
    exit 1
fi

# 检查配置文件
echo "检查配置文件..."
if [ -f "backend/requirements.txt" ] && [ -f "probe/probe_config.json" ]; then
    echo "✓ 配置文件完整"
else
    echo "✗ 配置文件缺失"
    exit 1
fi

echo ""
echo "🎉 所有组件测试通过！"
echo ""
echo "使用指南："
echo "1. 启动后端: cd backend && uvicorn main:app --reload"
echo "2. 启动前端: cd frontend && npm run dev"
echo "3. 运行探针: cd probe && python server_probe.py"
echo ""
echo "或者使用部署脚本:"
echo "  Linux/Mac: ./deploy.sh start"
echo "  Windows: deploy.bat"