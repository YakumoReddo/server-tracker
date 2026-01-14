#!/usr/bin/env python3
"""
系统初始化脚本
用于创建默认管理员用户和初始化数据库
"""
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), 'backend'))

from sqlalchemy.orm import Session
from database import SessionLocal, create_tables
from models import AdminUser
from auth import AuthManager

def create_default_admin():
    """创建默认管理员账户"""
    db = SessionLocal()
    
    try:
        # 检查是否已存在管理员
        existing_admin = db.query(AdminUser).filter(
            AdminUser.username == "admin"
        ).first()
        
        if existing_admin:
            print("默认管理员账户已存在")
            return
        
        # 创建默认管理员
        auth_manager = AuthManager()
        hashed_password = auth_manager.get_password_hash("admin123456")
        
        admin = AdminUser(
            username="admin",
            password_hash=hashed_password,
            email="admin@example.com",
            is_active=True,
            is_superuser=True
        )
        
        db.add(admin)
        db.commit()
        
        print("默认管理员账户创建成功:")
        print("用户名: admin")
        print("密码: admin123456")
        print("请及时修改密码!")
        
    except Exception as e:
        print(f"创建默认管理员失败: {e}")
        db.rollback()
    finally:
        db.close()

def main():
    print("ServerTracker 系统初始化")
    print("=" * 50)
    
    # 创建数据库表
    print("正在创建数据库表...")
    create_tables()
    print("数据库表创建完成")
    
    # 创建默认管理员
    create_default_admin()
    
    print("\n系统初始化完成!")
    print("\n启动命令:")
    print("后端: cd backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000")
    print("前端: cd frontend && npm run dev")

if __name__ == "__main__":
    main()