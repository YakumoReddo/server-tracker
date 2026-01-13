# 服务器监测工具 - ServerTracker

一个用于监测多个服务器状态的完整解决方案，支持移动端网页访问。

## 功能特性

- ✅ **多服务器监测**: 支持同时监测多台服务器
- ✅ **实时数据更新**: WebSocket实时推送指标更新
- ✅ **移动端适配**: 响应式设计，支持手机和平板访问
- ✅ **系统指标监测**: CPU、内存、磁盘使用率
- ✅ **网络监测**: 端口状态监测
- ✅ **Web界面**: 美观的现代化界面
- ✅ **探针部署**: 轻量级探针程序

## 技术栈

- **后端**: Python + FastAPI + SQLAlchemy + SQLite
- **前端**: Vue 3 + Vite + 原生CSS
- **探针**: Python + psutil
- **实时通信**: WebSocket

## 项目结构

```
servertracker/
├── backend/                 # 后端API服务
│   ├── main.py             # FastAPI主应用
│   ├── models.py           # 数据库模型
│   ├── schemas.py          # Pydantic模式
│   ├── services.py         # 业务逻辑
│   ├── database.py         # 数据库配置
│   └── requirements.txt    # Python依赖
├── probe/                   # 监测探针
│   ├── server_probe.py     # 探针主程序
│   └── probe_config.json   # 探针配置文件
├── frontend/                # 前端界面
│   └── src/
│       ├── App.vue         # 主应用组件
│       ├── main.js         # 入口文件
│       └── style.css       # 样式文件
├── docs/                    # 文档
└── README.md               # 说明文档
```

## 快速开始

### 1. 后端服务启动

```bash
# 安装Python依赖
cd backend
pip install -r requirements.txt

# 启动FastAPI服务
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

后端服务将在 http://localhost:8000 启动

### 2. 前端界面启动

```bash
# 安装Node.js依赖
cd frontend
npm install

# 启动开发服务器
npm run dev
```

前端界面将在 http://localhost:5173 启动

### 3. 部署监测探针

在要监测的服务器上：

```bash
# 安装探针依赖
pip install psutil requests

# 配置探针
# 编辑 probe_config.json 中的 server_url 和 probe_key

# 运行探针
python server_probe.py
```

## 使用指南

### 添加监测服务器

1. 通过API添加服务器：
```bash
curl -X POST "http://localhost:8000/api/servers" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Web服务器",
    "host": "192.168.1.100",
    "port": 22,
    "description": "主要Web服务器"
  }'
```

2. 获取探针密钥：
```bash
curl "http://localhost:8000/api/servers"
```

3. 在目标服务器上配置探针，编辑 `probe_config.json`：
```json
{
  "server_url": "http://你的监控服务器IP:8000",
  "probe_key": "从API获取的密钥",
  "interval": 60,
  "ports": [80, 443, 3306, 6379]
}
```

4. 启动探针：
```bash
python server_probe.py
```

### 监测指标

探针会收集以下指标：
- **CPU使用率**: 处理器使用百分比
- **内存使用率**: 系统内存使用百分比  
- **磁盘使用率**: 根分区使用百分比
- **端口状态**: 指定端口的连接状态
- **系统运行时间**: 服务器连续运行时间

### 实时监控

- 前端界面会实时显示服务器状态
- WebSocket连接显示实时数据更新
- 支持移动设备访问

## API文档

### 服务器管理

- `GET /api/servers` - 获取所有服务器
- `POST /api/servers` - 添加新服务器
- `GET /api/servers/{id}` - 获取特定服务器
- `PUT /api/servers/{id}` - 更新服务器信息
- `DELETE /api/servers/{id}` - 删除服务器

### 指标数据

- `GET /api/servers/{id}/metrics/latest` - 获取最新指标
- `GET /api/servers/{id}/metrics` - 获取历史指标
- `POST /api/servers/{id}/metrics` - 手动提交指标
- `POST /api/probe/{probe_key}/metrics` - 探针提交指标

### 实时通信

- `WebSocket /ws` - 实时指标更新推送

### 系统状态

- `GET /api/health` - 健康检查
- `GET /` - API基本信息

## 配置说明

### 后端配置

环境变量：
- `DATABASE_URL`: 数据库连接字符串 (默认: sqlite:///./monitor.db)

### 探针配置

`probe_config.json`:
```json
{
  "server_url": "http://监控服务器地址:8000",
  "probe_key": "服务器的唯一密钥",
  "interval": 60,           # 采集间隔(秒)
  "ports": [80, 443, 3306]  # 要监测的端口列表
}
```

## 生产部署

### Docker部署

1. 创建Dockerfile:
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY backend/requirements.txt .
RUN pip install -r requirements.txt

COPY backend/ .
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

2. 构建和运行:
```bash
docker build -t servertracker .
docker run -p 8000:8000 servertracker
```

### Nginx反向代理

```nginx
server {
    listen 80;
    server_name your-domain.com;

    # 前端静态文件
    location / {
        root /path/to/frontend/dist;
        try_files $uri $uri/ /index.html;
    }

    # API代理
    location /api/ {
        proxy_pass http://localhost:8000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket代理
    location /ws {
        proxy_pass http://localhost:8000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 故障排除

### 常见问题

1. **探针无法连接**
   - 检查 `server_url` 是否正确
   - 确认防火墙允许连接
   - 验证 `probe_key` 是否有效

2. **前端无法加载数据**
   - 确认后端服务运行正常
   - 检查CORS配置
   - 验证API地址配置

3. **指标数据缺失**
   - 检查探针日志
   - 确认服务器权限
   - 验证网络连接

### 日志查看

- 后端日志: 查看启动终端的输出
- 探针日志: 探针运行时会输出到控制台

## 性能优化

- 数据库定期清理历史数据
- 调整探针采集间隔
- 使用Redis缓存热点数据
- 前端实现虚拟滚动优化大数据列表

## 安全考虑

- 生产环境中限制CORS域名
- 使用HTTPS加密通信
- 探针通信可以添加签名验证
- 定期轮换探针密钥

## 扩展功能

可以基于此项目继续开发：
- 告警规则和通知
- 历史数据图表展示
- 多用户权限管理
- 更多系统指标采集
- 分布式部署支持

## 许可证

MIT License - 可自由使用和修改

## 支持

如有问题请提交Issue或Pull Request。