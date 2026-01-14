#!/bin/bash
# 安全版ServerTracker部署脚本

set -e

echo "============================================"
echo "ServerTracker 安全版部署脚本"
echo "============================================"

# 检查Python版本
echo "检查Python版本..."
python3 --version || {
    echo "错误: 需要Python 3.7+"
    exit 1
}

# 检查Node.js版本
echo "检查Node.js版本..."
node --version || {
    echo "错误: 需要Node.js 14+"
    exit 1
}

# 创建虚拟环境
echo "创建Python虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 安装后端依赖
echo "安装后端依赖..."
cd backend
pip install -r requirements.txt
cd ..

# 安装前端依赖
echo "安装前端依赖..."
cd frontend
npm install
npm run build
cd ..

# 初始化数据库
echo "初始化数据库..."
cd backend
python -c "
import sys
sys.path.append('.')
from database import create_tables
from models import AdminUser
from auth import AuthManager

# 创建表
create_tables()

# 创建默认管理员
auth_manager = AuthManager()
hashed_password = auth_manager.get_password_hash('admin123456')

admin = AdminUser(
    username='admin',
    password_hash=hashed_password,
    email='admin@example.com',
    is_active=True,
    is_superuser=True
)

from database import SessionLocal
db = SessionLocal()
db.add(admin)
db.commit()
print('默认管理员账户已创建: admin / admin123456')
"

cd ..

echo "============================================"
echo "部署完成!"
echo "============================================"
echo ""
echo "启动命令:"
echo "后端: cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000"
echo "前端: cd frontend && npm run dev"
echo ""
echo "默认登录: admin / admin123456"
echo "首次登录后请立即修改密码!"