<template>
  <div id="app">
    <header class="header">
      <h1 class="title">服务器监测</h1>
      <div class="connection-status">
        <span :class="['status-indicator', wsConnected ? 'connected' : 'disconnected']"></span>
        <span class="status-text">{{ wsConnected ? '已连接' : '未连接' }}</span>
      </div>
    </header>

    <main class="main-content">
      <div v-if="loading" class="loading">
        <div class="spinner"></div>
        <p>加载中...</p>
      </div>

      <div v-else class="content">
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
    </main>
  </div>
</template>

<script>
import { ref, onMounted, onUnmounted } from 'vue'

export default {
  name: 'App',
  setup() {
    const servers = ref([])
    const selectedServer = ref(null)
    const currentMetrics = ref(null)
    const metrics = ref({})
    const loading = ref(true)
    const wsConnected = ref(false)
    let ws = null

    const API_BASE = 'http://localhost:8000'

    const fetchServers = async () => {
      try {
        const response = await fetch(`${API_BASE}/api/servers`)
        const data = await response.json()
        servers.value = data.servers || []
      } catch (error) {
        console.error('Failed to fetch servers:', error)
      }
    }

    const fetchMetrics = async (serverId) => {
      try {
        const response = await fetch(`${API_BASE}/api/servers/${serverId}/metrics/latest`)
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

    const connectWebSocket = () => {
      try {
        ws = new WebSocket('ws://localhost:8000/ws')
        
        ws.onopen = () => {
          wsConnected.value = true
          console.log('WebSocket connected')
        }
        
        ws.onmessage = (event) => {
          const data = JSON.parse(event.data)
          if (data.type === 'metrics_update') {
            fetchMetrics(data.server_id)
          }
        }
        
        ws.onclose = () => {
          wsConnected.value = false
          console.log('WebSocket disconnected')
          setTimeout(connectWebSocket, 3000)
        }
        
        ws.onerror = (error) => {
          console.error('WebSocket error:', error)
        }
      } catch (error) {
        console.error('Failed to connect WebSocket:', error)
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
      await fetchServers()
      loading.value = false
      
      connectWebSocket()
      
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
    })

    return {
      servers,
      selectedServer,
      currentMetrics,
      loading,
      wsConnected,
      selectServer,
      getLatestMetrics,
      getPortStatus,
      getCpuStatus,
      getMemoryStatus,
      formatTime
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
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

#app {
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

.connection-status {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.status-indicator {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.status-indicator.connected {
  background: #4ade80;
  animation: pulse 2s infinite;
}

.status-indicator.disconnected {
  background: #ef4444;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.status-text {
  font-size: 0.875rem;
  color: #666;
}

.main-content {
  padding: 1rem;
  max-width: 1200px;
  margin: 0 auto;
}

.loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 400px;
  color: white;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 4px solid rgba(255, 255, 255, 0.3);
  border-top: 4px solid white;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin-bottom: 1rem;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.server-list h2 {
  color: white;
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
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  padding: 1rem;
  cursor: pointer;
  transition: all 0.3s ease;
  border: 2px solid transparent;
}

.server-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
}

.server-card.selected {
  border-color: #4f46e5;
  box-shadow: 0 0 0 4px rgba(79, 70, 229, 0.1);
}

.server-card.active {
  border-left: 4px solid #4ade80;
}

.server-card.inactive {
  border-left: 4px solid #ef4444;
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
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  padding: 1.5rem;
  margin-top: 1rem;
}

.server-details h2 {
  color: #333;
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
  background: #f8fafc;
  border-radius: 8px;
  padding: 1rem;
}

.metric-card h3 {
  color: #333;
  margin-bottom: 1rem;
  font-size: 0.875rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.progress-bar {
  background: #e2e8f0;
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
  background: linear-gradient(90deg, #4ade80, #22c55e);
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
  color: #333;
}

.port-status h3 {
  color: #333;
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
  background: #f8fafc;
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
  color: #333;
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
  
  .server-details {
    padding: 1rem;
  }
}
</style>