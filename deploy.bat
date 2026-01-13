@echo off
chcp 65001 >nul
echo 🚀 服务器监测工具部署脚本 (Windows)
echo ================================

set "ERROR_COLOR=[91m"
set "SUCCESS_COLOR=[92m"
set "WARNING_COLOR=[93m"
set "NC=[0m"

:check_python
echo %WARNING_COLOR%检查Python环境...%NC%
python --version >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%错误: 未找到Python%NC%
    pause
    exit /b 1
)
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set "PYTHON_VERSION=%%i"
echo %SUCCESS_COLOR%✓ Python版本: %PYTHON_VERSION%%NC%
goto :check_nodejs

:check_nodejs
echo %WARNING_COLOR%检查Node.js环境...%NC%
node --version >nul 2>&1
if errorlevel 1 (
    echo %WARNING_COLOR%警告: 未找到Node.js (前端需要)%NC%
    goto :install_backend
)
for /f %%i in ('node --version 2^>^&1') do set "NODE_VERSION=%%i"
echo %SUCCESS_COLOR%✓ Node.js版本: %NODE_VERSION%%NC%
goto :install_frontend

:install_backend
echo %WARNING_COLOR%安装后端依赖...%NC%
cd backend
pip install -r requirements.txt
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 后端依赖安装失败%NC%
    pause
    exit /b 1
)
echo %SUCCESS_COLOR%✓ 后端依赖安装完成%NC%
cd ..
goto :start_backend

:install_frontend
echo %WARNING_COLOR%安装前端依赖...%NC%
cd frontend
npm install
if errorlevel 1 (
    echo %WARNING_COLOR%✗ 前端依赖安装失败，跳过前端%NC%
    cd ..
    goto :start_backend
)
echo %SUCCESS_COLOR%✓ 前端依赖安装完成%NC%
cd ..
goto :start_frontend

:start_backend
echo %WARNING_COLOR%启动后端服务...%NC%
cd backend
start "ServerTracker Backend" /min cmd /c "uvicorn main:app --reload --host 0.0.0.0 --port 8000"
cd ..
timeout /t 3 >nul
echo %SUCCESS_COLOR%✓ 后端服务启动%NC%
echo %SUCCESS_COLOR%✓ API地址: http://localhost:8000%NC%
goto :check_services

:start_frontend
echo %WARNING_COLOR%启动前端服务...%NC%
cd frontend
start "ServerTracker Frontend" /min cmd /c "npm run dev"
cd ..
timeout /t 5 >nul
echo %SUCCESS_COLOR%✓ 前端服务启动%NC%
echo %SUCCESS_COLOR%✓ 前端地址: http://localhost:5173%NC%
goto :check_services

:check_services
echo %WARNING_COLOR%检查服务状态...%NC%
timeout /t 2 >nul

curl -s http://localhost:8000/api/health >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 后端服务未响应%NC%
) else (
    echo %SUCCESS_COLOR%✓ 后端服务运行正常%NC%
)

curl -s http://localhost:5173 >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 前端服务未响应%NC%
) else (
    echo %SUCCESS_COLOR%✓ 前端服务运行正常%NC%
)

goto :show_usage

:show_usage
echo.
echo %SUCCESS_COLOR%🎉 部署完成！%NC%
echo ================================
echo %SUCCESS_COLOR%前端界面: http://localhost:5173%NC%
echo %SUCCESS_COLOR%API文档: http://localhost:8000/docs%NC%
echo.
echo %WARNING_COLOR%下一步操作:%NC%
echo 1. 访问前端界面查看监控面板
echo 2. 获取服务器探针密钥
echo 3. 在其他服务器上部署探针
echo.
echo %WARNING_COLOR%停止服务: 直接关闭窗口%NC%
echo.
pause
exit /b 0

:stop_services
echo %WARNING_COLOR%停止所有服务...%NC%
taskkill /f /im python.exe >nul 2>&1
taskkill /f /im node.exe >nul 2>&1
echo %SUCCESS_COLOR%✓ 服务已停止%NC%
pause
exit /b 0

:main
if "%1"=="stop" goto :stop_services
if "%1"=="start" goto :check_python
if "%1"=="" goto :check_python
echo 使用方法: %0 {start^|stop}
pause
exit /b 1

rem 执行主函数
goto :main