<template>
  <div id="app">
    <div v-if="!isAuthenticated" class="login-container">
      <LoginForm @login="handleLogin" />
    </div>
    
    <div v-else class="main-container">
      <header class="header">
        <h1 class="title">ServerTracker 管理面板</h1>
        <div class="header-actions">
          <span class="user-info">欢迎, {{ currentUser?.username }}</span>
          <button @click="logout" class="logout-btn">退出</button>
        </div>
      </header>

      <main class="main-content">
        <div class="tab-container">
          <div class="tabs">
            <button 
              :class="['tab', { active: activeTab === 'servers' }]"
              @click="activeTab = 'servers'"
            >
              服务器监控
            </button>
            <button 
              :class="['tab', { active: activeTab === 'probes' }]"
              @click="activeTab = 'probes'"
            >
              探针管理
            </button>
          </div>

          <!-- 服务器监控页面 -->
          <div v-if="activeTab === 'servers'" class="tab-content">
            <div class="server-list">
              <h2>服务器列表</h2>
              <div class="server-grid">
                <div 
                  v-for="server in servers" 
                  :key="server.id"
                  :class="['server-card', { active: server.is_active, selected: selectedServer?.id === server.id }]"
                  @click="selectServer(server)"
                >
                  <div class="server-header">
                    <h3>{{ server.name }}</h3>
                    <span :class="['status-badge', server.is_active ? 'online' : 'offline']">
                      {{ server.is_active ? '在线' : '离线' }}
                    </span>
                  </div>
                  <p class="server-host">{{ server.host }}:{{ server.port }}</p>
                  <p v-if="server.last_seen" class="last-seen">
                    最后活跃: {{ formatTime(server.last_seen) }}
                  </p>
                  <div v-if="getLatestMetrics(server.id)" class="quick-metrics">
                    <div class="metric">
                      <span>CPU:</span>
                      <span :class="getCpuStatus(getLatestMetrics(server.id).cpu_usage)">
                        {{ getLatestMetrics(server.id).cpu_usage?.toFixed(1) || 0 }}%
                      </span>
                    </div>
                    <div class="metric">
                      <span>内存:</span>
                      <span :class="getMemoryStatus(getLatestMetrics(server.id).memory_usage)">
                        {{ getLatestMetrics(server.id).memory_usage?.toFixed(1) || 0 }}%
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div v-if="selectedServer" class="server-details">
              <h2>{{ selectedServer.name }} - 详细监控</h2>
              
              <div class="metrics-overview">
                <div class="metric-card">
                  <h3>CPU 使用率</h3>
                  <div class="progress-bar">
                    <div 
                      class="progress-fill cpu" 
                      :style="{ width: (currentMetrics?.cpu_usage || 0) + '%' }"
                    ></div>
                  </div>
                  <span class="metric-value">{{ currentMetrics?.cpu_usage?.toFixed(1) || 0 }}%</span>
                </div>

                <div class="metric-card">
                  <h3>内存使用率</h3>
                  <div class="progress-bar">
                    <div 
                      class="progress-fill memory" 
                      :style="{ width: (currentMetrics?.memory_usage || 0) + '%' }"
                    ></div>
                  </div>
                  <span class="metric-value">{{ currentMetrics?.memory_usage?.toFixed(1) || 0 }}%</span>
                </div>

                <div class="metric-card">
                  <h3>磁盘使用率</h3>
                  <div class="progress-bar">
                    <div 
                      class="progress-fill disk" 
                      :style="{ width: (currentMetrics?.disk_usage || 0) + '%' }"
                    ></div>
                  </div>
                  <span class="metric-value">{{ currentMetrics?.disk_usage?.toFixed(1) || 0 }}%</span>
                </div>
              </div>

              <div class="port-status">
                <h3>端口状态</h3>
                <div class="port-grid">
                  <div 
                    v-for="(status, port) in getPortStatus(selectedServer.id)" 
                    :key="port"
                    :class="['port-item', status ? 'open' : 'closed']"
                  >
                    <span class="port-number">{{ port }}</span>
                    <span class="port-state">{{ status ? '开放' : '关闭' }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 探针管理页面 -->
          <div v-if="activeTab === 'probes'" class="tab-content">
            <ProbeManagement 
              :probes="probes" 
              @create-probe="handleCreateProbe"
              @update-probe="handleUpdateProbe"
              @delete-probe="handleDeleteProbe"
              @download-probe="handleDownloadProbe"
            />
          </div>
        </div>
      </main>
    </div>
  </div>
</template>

<script>
import { ref, onMounted, onUnmounted } from 'vue'
import LoginForm from './components/LoginForm.vue'
import ProbeManagement from './components/ProbeManagement.vue'

export default {
  name: 'App',
  components: {
    LoginForm,
    ProbeManagement
  },
  setup() {
    const isAuthenticated = ref(false)
    const currentUser = ref(null)
    const activeTab = ref('servers')
    const servers = ref([])
    const selectedServer = ref(null)
    const currentMetrics = ref(null)
    const metrics = ref({})
    const probes = ref([])
    const wsConnected = ref(false)
    let ws = null

    const API_BASE = import.meta.env.VITE_PUBLISH_URL || 'http://localhost:8000'

    const fetchCurrentUser = async () => {
      try {
        const token = localStorage.getItem('access_token')
        if (!token) return
        
        const response = await fetch(`${API_BASE}/api/auth/me`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        
        if (response.ok) {
          const userData = await response.json()
          currentUser.value = userData
          isAuthenticated.value = true
        } else {
          localStorage.removeItem('access_token')
          localStorage.removeItem('refresh_token')
        }
      } catch (error) {
        console.error('Failed to fetch current user:', error)
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
      }
    }

    const fetchServers = async () => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/servers`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        const data = await response.json()
        servers.value = data.servers || []
      } catch (error) {
        console.error('Failed to fetch servers:', error)
      }
    }

    const fetchProbes = async () => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/admin/probes`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        if (response.ok) {
          const data = await response.json()
          probes.value = data
        }
      } catch (error) {
        console.error('Failed to fetch probes:', error)
      }
    }

    const verifyApiConnection = async () => {
      try {
        console.log(`🔍 检查后端连接: ${API_BASE}`)
        const response = await fetch(`${API_BASE}/api/health`)
        if (response.ok) {
          console.log(`✅ 后端连接正常: ${API_BASE}`)
          return true
        } else {
          console.error(`❌ 后端连接异常: ${response.status}`)
          return false
        }
      } catch (error) {
        console.error(`❌ 无法连接到后端 ${API_BASE}:`, error.message)
        return false
      }
    }

    const handleLogin = async (credentials) => {
      try {
        // 先验证API连接
        const isConnected = await verifyApiConnection()
        if (!isConnected) {
          throw new Error(`无法连接到后端服务 ${API_BASE}，请检查服务是否启动`)
        }

        const response = await fetch(`${API_BASE}/api/auth/login`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(credentials)
        })
        
        if (response.ok) {
          const data = await response.json()
          localStorage.setItem('access_token', data.access_token)
          localStorage.setItem('refresh_token', data.refresh_token)
          await fetchCurrentUser()
          await Promise.all([fetchServers(), fetchProbes()])
        } else {
          throw new Error('登录失败，请检查用户名和密码')
        }
      } catch (error) {
        console.error('Login error:', error)
        throw error
      }
    }

    const logout = () => {
      localStorage.removeItem('access_token')
      localStorage.removeItem('refresh_token')
      isAuthenticated.value = false
      currentUser.value = null
      servers.value = []
      probes.value = []
      if (ws) {
        ws.close()
      }
    }

    const fetchMetrics = async (serverId) => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/servers/${serverId}/metrics/latest`, {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        const data = await response.json()
        if (data.metrics) {
          metrics.value[serverId] = data.metrics
          if (selectedServer.value?.id === serverId) {
            currentMetrics.value = data.metrics
          }
        }
      } catch (error) {
        console.error('Failed to fetch metrics:', error)
      }
    }

    const handleCreateProbe = async (probeData) => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/admin/probes`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(probeData)
        })
        
        if (response.ok) {
          await fetchProbes()
        }
      } catch (error) {
        console.error('Failed to create probe:', error)
      }
    }

    const handleUpdateProbe = async (probeId, updateData) => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/admin/probes/${probeId}`, {
          method: 'PUT',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(updateData)
        })
        
        if (response.ok) {
          await fetchProbes()
        }
      } catch (error) {
        console.error('Failed to update probe:', error)
      }
    }

    const handleDeleteProbe = async (probeId) => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/admin/probes/${probeId}`, {
          method: 'DELETE',
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        
        if (response.ok) {
          await fetchProbes()
        }
      } catch (error) {
        console.error('Failed to delete probe:', error)
      }
    }

    const handleDownloadProbe = async (probeId) => {
      try {
        const token = localStorage.getItem('access_token')
        const response = await fetch(`${API_BASE}/api/admin/probes/${probeId}/package`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`
          }
        })
        
        if (response.ok) {
          const data = await response.json()
          // 触发下载
          const downloadResponse = await fetch(`${API_BASE}${data.download_url}`, {
            headers: {
              'Authorization': `Bearer ${token}`
            }
          })
          // 处理文件下载
        }
      } catch (error) {
        console.error('Failed to download probe:', error)
      }
    }

    const selectServer = (server) => {
      selectedServer.value = server
      fetchMetrics(server.id)
    }

    const getLatestMetrics = (serverId) => {
      return metrics.value[serverId]
    }

    const getPortStatus = (serverId) => {
      const metric = getLatestMetrics(serverId)
      if (metric?.port_status) {
        try {
          return JSON.parse(metric.port_status)
        } catch {
          return {}
        }
      }
      return {}
    }

    const getCpuStatus = (cpuUsage) => {
      if (cpuUsage > 80) return 'status-critical'
      if (cpuUsage > 60) return 'status-warning'
      return 'status-ok'
    }

    const getMemoryStatus = (memoryUsage) => {
      if (memoryUsage > 80) return 'status-critical'
      if (memoryUsage > 60) return 'status-warning'
      return 'status-ok'
    }

    const formatTime = (timeStr) => {
      return new Date(timeStr).toLocaleString('zh-CN')
    }

    onMounted(async () => {
      // 检查API连接状态
      const isConnected = await verifyApiConnection()
      
      if (!isConnected) {
        console.warn(`⚠️ 无法连接到后端 ${API_BASE}，请确保后端服务正在运行`)
        return
      }

      await fetchCurrentUser()
      
      if (isAuthenticated.value) {
        await Promise.all([fetchServers(), fetchProbes()])
        
        const interval = setInterval(() => {
          servers.value.forEach(server => {
            if (server.is_active) {
              fetchMetrics(server.id)
            }
          })
        }, 30000)
        
        onUnmounted(() => {
          clearInterval(interval)
          if (ws) {
            ws.close()
          }
        })
      }
    })

    return {
      isAuthenticated,
      currentUser,
      activeTab,
      servers,
      selectedServer,
      currentMetrics,
      metrics,
      probes,
      wsConnected,
      handleLogin,
      logout,
      selectServer,
      getLatestMetrics,
      getPortStatus,
      getCpuStatus,
      getMemoryStatus,
      formatTime,
      handleCreateProbe,
      handleUpdateProbe,
      handleDeleteProbe,
      handleDownloadProbe
    }
  }
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segue UI', Roboto, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

#app {
  min-height: 100vh;
}

.login-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  padding: 1rem;
}

.main-container {
  min-height: 100vh;
}

.header {
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(10px);
  padding: 1rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

.title {
  color: #333;
  font-size: 1.5rem;
  font-weight: 600;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.user-info {
  color: #666;
  font-size: 0.9rem;
}

.logout-btn {
  padding: 0.5rem 1rem;
  background: #ef4444;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.9rem;
}

.logout-btn:hover {
  background: #dc2626;
}

.main-content {
  padding: 1rem;
  max-width: 1200px;
  margin: 0 auto;
}

.tab-container {
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  overflow: hidden;
}

.tabs {
  display: flex;
  border-bottom: 1px solid #e5e7eb;
}

.tab {
  flex: 1;
  padding: 1rem;
  background: none;
  border: none;
  cursor: pointer;
  font-size: 1rem;
  color: #666;
  transition: all 0.3s ease;
}

.tab:hover {
  background: #f9fafb;
  color: #333;
}

.tab.active {
  color: #3b82f6;
  border-bottom: 2px solid #3b82f6;
  background: #f0f9ff;
}

.tab-content {
  padding: 1.5rem;
}

.server-list h2, .tab-content h2 {
  color: #333;
  margin-bottom: 1rem;
  font-size: 1.25rem;
}

.server-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1rem;
  margin-bottom: 2rem;
}

.server-card {
  background: #f8fafc;
  border-radius: 8px;
  padding: 1rem;
  cursor: pointer;
  transition: all 0.3s ease;
  border: 2px solid transparent;
}

.server-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.server-card.selected {
  border-color: #3b82f6;
  box-shadow: 0 0 0 4px rgba(59, 130, 246, 0.1);
}

.server-card.active {
  border-left: 4px solid #10b981;
}

.server-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.server-header h3 {
  color: #333;
  font-size: 1.1rem;
  font-weight: 600;
}

.status-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 20px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
}

.status-badge.online {
  background: #dcfce7;
  color: #166534;
}

.status-badge.offline {
  background: #fee2e2;
  color: #991b1b;
}

.server-host {
  color: #666;
  font-size: 0.875rem;
  margin-bottom: 0.5rem;
}

.last-seen {
  color: #888;
  font-size: 0.75rem;
  margin-bottom: 1rem;
}

.quick-metrics {
  display: flex;
  gap: 1rem;
}

.metric {
  display: flex;
  flex-direction: column;
  align-items: center;
  font-size: 0.75rem;
}

.metric span:first-child {
  color: #666;
  margin-bottom: 0.25rem;
}

.metric span:last-child {
  font-weight: 600;
  color: #333;
}

.status-ok {
  color: #16a34a;
}

.status-warning {
  color: #ea580c;
}

.status-critical {
  color: #dc2626;
}

.server-details {
  background: #f0f9ff;
  border-radius: 8px;
  padding: 1.5rem;
  margin-top: 1rem;
}

.server-details h2 {
  color: #1e40af;
  margin-bottom: 1.5rem;
  font-size: 1.25rem;
}

.metrics-overview {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1rem;
  margin-bottom: 2rem;
}

.metric-card {
  background: white;
  border-radius: 8px;
  padding: 1rem;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
}

.metric-card h3 {
  color: #374151;
  margin-bottom: 1rem;
  font-size: 0.875rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.progress-bar {
  background: #e5e7eb;
  border-radius: 10px;
  height: 8px;
  margin-bottom: 0.5rem;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  border-radius: 10px;
  transition: width 0.3s ease;
}

.progress-fill.cpu {
  background: linear-gradient(90deg, #10b981, #059669);
}

.progress-fill.memory {
  background: linear-gradient(90deg, #f59e0b, #d97706);
}

.progress-fill.disk {
  background: linear-gradient(90deg, #3b82f6, #2563eb);
}

.metric-value {
  font-size: 1.5rem;
  font-weight: 700;
  color: #374151;
}

.port-status h3 {
  color: #374151;
  margin-bottom: 1rem;
  font-size: 1rem;
}

.port-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 0.75rem;
}

.port-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0.75rem;
  border-radius: 8px;
  background: white;
}

.port-item.open {
  background: #dcfce7;
  border: 1px solid #bbf7d0;
}

.port-item.closed {
  background: #fee2e2;
  border: 1px solid #fecaca;
}

.port-number {
  font-weight: 600;
  color: #374151;
  margin-bottom: 0.25rem;
}

.port-state {
  font-size: 0.75rem;
  text-transform: uppercase;
  font-weight: 600;
}

.port-item.open .port-state {
  color: #166534;
}

.port-item.closed .port-state {
  color: #991b1b;
}

@media (max-width: 768px) {
  .header {
    flex-direction: column;
    gap: 1rem;
    text-align: center;
  }
  
  .server-grid {
    grid-template-columns: 1fr;
  }
  
  .metrics-overview {
    grid-template-columns: 1fr;
  }
  
  .main-content {
    padding: 0.5rem;
  }
}
</style>