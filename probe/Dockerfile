# 探针服务Dockerfile
FROM python:3.11-slim

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 复制探针代码
COPY . .

# 安装Python依赖（如果需要）
# RUN pip install -r requirements.txt

# 暴露端口（如果探针需要网络接口）
EXPOSE 8080

# 启动探针服务
CMD ["python", "server_probe.py"]