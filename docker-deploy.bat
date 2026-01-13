@echo off
chcp 65001 >nul
echo 🐳 服务器监测工具 Docker 部署脚本 (Windows)
echo ============================================

set "ERROR_COLOR=[91m"
set "SUCCESS_COLOR=[92m"
set "WARNING_COLOR=[93m"
set "INFO_COLOR=[94m"
set "NC=[0m"

:check_docker
echo %WARNING_COLOR%检查Docker环境...%NC%
docker --version >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%错误: 未找到Docker%NC%
    echo 请先安装Docker Desktop: https://docs.docker.com/desktop/windows/install/
    pause
    exit /b 1
)

docker-compose --version >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%错误: 未找到docker-compose%NC%
    echo 通常包含在Docker Desktop中
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('docker --version') do set "DOCKER_VERSION=%%i"
for /f "tokens=*" %%i in ('docker-compose --version') do set "COMPOSE_VERSION=%%i"
echo %SUCCESS_COLOR%✓ Docker版本: %DOCKER_VERSION%%NC%
echo %SUCCESS_COLOR%✓ Compose版本: %COMPOSE_VERSION%%NC%
goto :create_directories

:create_directories
echo %WARNING_COLOR%创建必要目录...%NC%
if not exist "data" mkdir data
echo %SUCCESS_COLOR%✓ 目录创建完成%NC%
goto :build_images

:build_images
echo %WARNING_COLOR%构建Docker镜像...%NC%

echo %INFO_COLOR%构建后端镜像...%NC%
docker-compose build backend
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 后端镜像构建失败%NC%
    pause
    exit /b 1
)
echo %SUCCESS_COLOR%✓ 后端镜像构建完成%NC%

echo %INFO_COLOR%构建前端镜像...%NC%
docker-compose build frontend
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 前端镜像构建失败%NC%
    pause
    exit /b 1
)
echo %SUCCESS_COLOR%✓ 前端镜像构建完成%NC%

goto :start_services

:start_services
echo %WARNING_COLOR%启动服务...%NC%
docker-compose up -d
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 服务启动失败%NC%
    pause
    exit /b 1
)

echo %WARNING_COLOR%等待服务启动...%NC%
timeout /t 10 >nul

goto :check_services

:check_services
echo %WARNING_COLOR%检查服务状态...%NC%
timeout /t 3 >nul

curl -s http://localhost:8000/api/health >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 后端服务未响应%NC%
    echo 查看后端日志: docker-compose logs backend
) else (
    echo %SUCCESS_COLOR%✓ 后端服务运行正常%NC%
)

curl -s http://localhost/ >nul 2>&1
if errorlevel 1 (
    echo %ERROR_COLOR%✗ 前端服务未响应%NC%
    echo 查看前端日志: docker-compose logs frontend
) else (
    echo %SUCCESS_COLOR%✓ 前端服务运行正常%NC%
)

echo %INFO_COLOR%容器状态:%NC%
docker-compose ps
goto :show_info

:show_info
echo.
echo %SUCCESS_COLOR%🎉 部署完成！%NC%
echo ================================
echo %SUCCESS_COLOR%前端界面: http://localhost%NC%
echo %SUCCESS_COLOR%API文档: http://localhost/api/docs%NC%
echo %SUCCESS_COLOR%后端API: http://localhost:8000%NC%
echo.
echo %WARNING_COLOR%Docker管理命令:%NC%
echo   查看服务状态: docker-compose ps
echo   查看服务日志: docker-compose logs -f [service_name]
echo   重启服务: docker-compose restart [service_name]
echo   停止服务: docker-compose down
echo   重建服务: docker-compose up -d --build
echo.
echo %WARNING_COLOR%探针配置:%NC%
echo   服务器地址: http://localhost:8000
echo   配置文件: .\probe\probe_config.json
echo   运行探针: cd probe && python server_probe.py
echo.
pause
exit /b 0

:stop_services
echo %WARNING_COLOR%停止所有服务...%NC%
docker-compose down
echo %SUCCESS_COLOR%✓ 所有服务已停止%NC%
pause
exit /b 0

:restart_services
echo %WARNING_COLOR%重启所有服务...%NC%
docker-compose restart
echo %SUCCESS_COLOR%✓ 服务重启完成%NC%
pause
exit /b 0

:show_logs
echo %WARNING_COLOR%显示服务日志...%NC%
echo 按 Ctrl+C 退出日志查看
docker-compose logs -f
exit /b 0

:cleanup
echo %WARNING_COLOR%清理Docker资源...%NC%
echo 确定要清理所有Docker资源吗?
set /p "confirm=输入 y 确认清理: "
if /i "%confirm%"=="y" (
    docker-compose down -v --remove-orphans
    docker system prune -f
    echo %SUCCESS_COLOR%✓ 资源清理完成%NC%
) else (
    echo %INFO_COLOR%取消清理操作%NC%
)
pause
exit /b 0

:backup_db
echo %WARNING_COLOR%备份数据库...%NC%
set "backup_file=backup_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%.db"
set "backup_file=%backup_file: =0%"
if exist "data\monitor.db" (
    copy "data\monitor.db" "data\%backup_file%" >nul
    echo %SUCCESS_COLOR%✓ 数据库已备份到: data\%backup_file%%NC%
) else (
    echo %WARNING_COLOR%未找到数据库文件%NC%
)
pause
exit /b 0

:build_only
echo %WARNING_COLOR%仅构建镜像...%NC%
call :build_images
echo %SUCCESS_COLOR%✓ 镜像构建完成%NC%
pause
exit /b 0

:main
if "%1"=="stop" goto :stop_services
if "%1"=="restart" goto :restart_services
if "%1"=="logs" goto :show_logs
if "%1"=="cleanup" goto :cleanup
if "%1"=="backup" goto :backup_db
if "%1"=="build" goto :build_only
if "%1"=="start" goto :check_docker
if "%1"=="" goto :check_docker

echo 使用方法: %0 {start^|stop^|restart^|logs^|cleanup^|backup^|build}
echo.
echo 命令说明:
echo   start    - 启动所有服务 (默认)
echo   stop     - 停止所有服务
echo   restart  - 重启所有服务
echo   logs     - 显示服务日志
echo   cleanup  - 清理Docker资源
echo   backup   - 备份数据库
echo   build    - 仅构建镜像
pause
exit /b 1

rem 执行主函数
goto :main