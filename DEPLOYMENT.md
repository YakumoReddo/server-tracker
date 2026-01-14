# 前端部署配置说明

## 🎯 问题解决

之前的版本存在前端硬编码API地址的问题，导致前端总是连接 `http://localhost:8000`，无法连接到实际的远端后端服务。

## 🛠️ 解决方案

### 1. 环境变量配置

在 `.env.example` 中添加了 `PUBLISH_URL` 变量：

```bash
# 发布/部署配置
PUBLISH_URL=https://your-domain.com:8000
```

### 2. 前端代码改进

修改了 `frontend/src/App.vue`：

**之前**（硬编码）：
```javascript
const API_BASE = 'http://localhost:8000'
```

**现在**（环境变量）：
```javascript
const API_BASE = import.meta.env.VITE_PUBLISH_URL || 'http://localhost:8000'
```

### 3. 连接验证功能

添加了API连接状态检查：

```javascript
const verifyApiConnection = async () => {
  try {
    const response = await fetch(`${API_BASE}/api/health`)
    return response.ok
  } catch {
    return false
  }
}
```

## 📁 配置文件

### 开发环境配置 (`frontend/.env.development`)
```bash
VITE_PUBLISH_URL=http://localhost:8000
```

### 生产环境配置 (`frontend/.env.production`)
```bash
VITE_PUBLISH_URL=https://your-api-domain.com:8000
```

### 环境变量模板 (`frontend/.env`)
```bash
# 自动生成的环境配置
VITE_PUBLISH_URL=http://localhost:8000
```

## 🚀 部署方式

### 方式1：使用部署脚本（推荐）

```bash
# 开发环境
./deploy-frontend.sh development http://localhost:8000

# 生产环境
./deploy-frontend.sh production https://api.yourdomain.com:8000

# 预发布环境
./deploy-frontend.sh staging https://staging.yourdomain.com:8000

# 或者使用快捷选项
./deploy-frontend.sh -d  # 开发环境
./deploy-frontend.sh -p  # 生产环境
./deploy-frontend.sh -s  # 预发布环境
```

### 方式2：手动配置

1. **进入前端目录**：
   ```bash
   cd frontend
   ```

2. **设置环境变量**：
   ```bash
   export VITE_PUBLISH_URL=https://your-api-domain.com:8000
   ```

3. **安装依赖并构建**：
   ```bash
   npm install
   npm run build
   ```

### 方式3：环境文件覆盖

创建或修改 `frontend/.env` 文件：
```bash
VITE_PUBLISH_URL=https://your-actual-backend-domain.com:8000
```

然后运行：
```bash
npm run build
```

## 🔍 连接状态检查

前端现在会自动检查API连接状态：

1. **组件初始化时**：检查后端是否可达
2. **登录前**：验证API连接
3. **错误处理**：提供清晰的错误信息

如果连接失败，会显示：
```
⚠️ 无法连接到后端 https://your-api-domain.com:8000，请确保后端服务正在运行
```

## 📋 部署流程

### 开发环境
```bash
# 1. 启动后端
cd backend
python main.py

# 2. 启动前端开发服务器
cd frontend
npm run dev
```

### 生产环境
```bash
# 1. 配置环境变量
./deploy-frontend.sh production https://api.yourdomain.com:8000

# 2. 部署 dist 目录到Web服务器
# 将 frontend/dist 目录上传到你的Web服务器
```

## ⚙️ 多环境配置

### 环境变量优先级
1. 命令行导出：`export VITE_PUBLISH_URL=...`
2. `.env.local` 文件
3. `.env.development` 文件（开发环境）
4. `.env.production` 文件（生产环境）
5. 默认值：`http://localhost:8000`

### 不同环境的API地址
- **本地开发**：`http://localhost:8000`
- **开发服务器**：`http://dev.yourdomain.com:8000`
- **预发布环境**：`https://staging.yourdomain.com:8000`
- **生产环境**：`https://api.yourdomain.com:8000`

## 🛡️ 安全考虑

1. **HTTPS生产环境**：生产环境建议使用HTTPS
2. **CORS配置**：确保后端的CORS设置包含前端域名
3. **环境变量安全**：不要将敏感信息提交到版本控制

## 📝 常见问题

### Q: 前端显示"无法连接到后端"
**A**: 检查以下几点：
1. 后端服务是否启动
2. API地址是否正确
3. 网络连接是否正常
4. CORS配置是否正确

### Q: 部署后API地址仍然指向localhost
**A**: 确保：
1. 使用了正确的环境变量名称 `VITE_PUBLISH_URL`
2. 环境变量在构建时生效（不是运行时）
3. 清除了浏览器缓存

### Q: 不同环境使用不同的API地址
**A**: 可以使用不同的环境文件或环境变量：
```bash
# 开发
VITE_PUBLISH_URL=http://localhost:8000

# 生产
VITE_PUBLISH_URL=https://api.yourdomain.com:8000
```

## ✅ 验证部署

部署完成后，可以通过以下方式验证：

1. **健康检查**：
   ```bash
   curl https://your-frontend-domain.com/api/health
   ```

2. **前端控制台**：查看连接状态日志
3. **网络面板**：检查API请求的目标地址

## 📚 相关文件

- `frontend/src/App.vue` - 主要前端应用
- `.env.example` - 环境变量模板
- `deploy-frontend.sh` - 部署脚本
- `frontend/.env.development` - 开发环境配置
- `frontend/.env.production` - 生产环境配置