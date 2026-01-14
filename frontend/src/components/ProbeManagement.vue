<template>
  <div class="probe-management">
    <div class="page-header">
      <h2>探针管理</h2>
      <button @click="showCreateModal = true" class="create-btn">
        + 创建新探针
      </button>
    </div>

    <!-- 探针列表 -->
    <div v-if="probes.length === 0" class="empty-state">
      <div class="empty-content">
        <div class="empty-icon">🔍</div>
        <h3>暂无探针</h3>
        <p>创建您的第一个监控探针来开始监控服务器</p>
        <button @click="showCreateModal = true" class="create-btn">创建探针</button>
      </div>
    </div>

    <div v-else class="probe-grid">
      <div v-for="probe in probes" :key="probe.id" class="probe-card">
        <div class="probe-header">
          <div class="probe-info">
            <h3>{{ probe.name }}</h3>
            <p class="probe-host">{{ probe.host }}:{{ probe.port }}</p>
          </div>
          <div class="probe-status">
            <span :class="['status-badge', probe.is_active ? 'active' : 'inactive']">
              {{ probe.is_active ? '活跃' : '停用' }}
            </span>
          </div>
        </div>

        <div class="probe-details">
          <div class="detail-item">
            <label>证书状态:</label>
            <span :class="['cert-status', getCertStatusClass(probe.certificate_status)]">
              {{ probe.certificate_status }}
            </span>
          </div>
          <div class="detail-item" v-if="probe.certificate_expires">
            <label>证书到期:</label>
            <span>{{ formatDate(probe.certificate_expires) }}</span>
          </div>
          <div class="detail-item">
            <label>创建时间:</label>
            <span>{{ formatDate(probe.created_at) }}</span>
          </div>
          <div class="detail-item" v-if="probe.last_seen">
            <label>最后活跃:</label>
            <span>{{ formatTime(probe.last_seen) }}</span>
          </div>
        </div>

        <div class="probe-description" v-if="probe.description">
          <p>{{ probe.description }}</p>
        </div>

        <div class="probe-actions">
          <button @click="handleEdit(probe)" class="edit-btn">编辑</button>
          <button @click="handleDownload(probe)" class="download-btn">下载</button>
          <button @click="handleDelete(probe)" class="delete-btn">删除</button>
        </div>
      </div>
    </div>

    <!-- 创建/编辑探针模态框 -->
    <div v-if="showCreateModal || showEditModal" class="modal-overlay" @click="closeModals">
      <div class="modal-content" @click.stop>
        <div class="modal-header">
          <h3>{{ showCreateModal ? '创建新探针' : '编辑探针' }}</h3>
          <button @click="closeModals" class="close-btn">&times;</button>
        </div>

        <form @submit.prevent="handleSubmit" class="modal-form">
          <div class="form-group">
            <label for="name">探针名称 *</label>
            <input
              id="name"
              v-model="form.name"
              type="text"
              required
              placeholder="输入探针名称"
              :disabled="loading"
            />
          </div>

          <div class="form-group">
            <label for="host">服务器地址 *</label>
            <input
              id="host"
              v-model="form.host"
              type="text"
              required
              placeholder="192.168.1.100 或 example.com"
              :disabled="loading"
            />
          </div>

          <div class="form-row">
            <div class="form-group">
              <label for="port">端口</label>
              <input
                id="port"
                v-model.number="form.port"
                type="number"
                min="1"
                max="65535"
                :disabled="loading"
              />
            </div>

            <div class="form-group">
              <label for="interval">采集间隔(秒)</label>
              <input
                id="interval"
                v-model.number="form.interval"
                type="number"
                min="30"
                max="3600"
                :disabled="loading"
              />
            </div>
          </div>

          <div class="form-group">
            <label for="description">描述</label>
            <textarea
              id="description"
              v-model="form.description"
              rows="3"
              placeholder="输入探针描述（可选）"
              :disabled="loading"
            ></textarea>
          </div>

          <div class="form-group">
            <label for="server_url">服务器URL *</label>
            <input
              id="server_url"
              v-model="form.server_url"
              type="url"
              required
              placeholder="https://your-domain.com"
              :disabled="loading"
            />
          </div>

          <div class="form-group">
            <label for="ports">监控端口</label>
            <div class="ports-input">
              <input
                v-model="newPort"
                type="number"
                min="1"
                max="65535"
                placeholder="输入端口号"
                @keyup.enter="addPort"
                :disabled="loading"
              />
              <button type="button" @click="addPort" :disabled="loading || !newPort">
                添加
              </button>
            </div>
            <div class="ports-list" v-if="form.ports.length > 0">
              <span v-for="port in form.ports" :key="port" class="port-tag">
                {{ port }}
                <button type="button" @click="removePort(port)" class="remove-port">×</button>
              </span>
            </div>
          </div>

          <div v-if="error" class="error-message">
            {{ error }}
          </div>

          <div class="modal-actions">
            <button type="button" @click="closeModals" :disabled="loading">
              取消
            </button>
            <button type="submit" :disabled="loading || !isFormValid" class="submit-btn">
              <div v-if="loading" class="spinner"></div>
              <span v-else>{{ showCreateModal ? '创建' : '更新' }}</span>
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- 删除确认模态框 -->
    <div v-if="showDeleteModal" class="modal-overlay" @click="showDeleteModal = false">
      <div class="modal-content delete-modal" @click.stop>
        <div class="modal-header">
          <h3>确认删除</h3>
          <button @click="showDeleteModal = false" class="close-btn">&times;</button>
        </div>
        
        <div class="delete-content">
          <p>确定要删除探针 "<strong>{{ probeToDelete?.name }}</strong>" 吗？</p>
          <p class="warning">此操作将同时吊销该探针的证书，删除后无法恢复。</p>
        </div>

        <div class="modal-actions">
          <button @click="showDeleteModal = false" :disabled="loading">取消</button>
          <button @click="confirmDelete" :disabled="loading" class="delete-btn">
            <div v-if="loading" class="spinner"></div>
            <span v-else>确认删除</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, computed } from 'vue'

export default {
  name: 'ProbeManagement',
  props: {
    probes: {
      type: Array,
      default: () => []
    }
  },
  emits: ['create-probe', 'update-probe', 'delete-probe', 'download-probe'],
  setup(props, { emit }) {
    const showCreateModal = ref(false)
    const showEditModal = ref(false)
    const showDeleteModal = ref(false)
    const loading = ref(false)
    const error = ref('')
    const probeToDelete = ref(null)
    const newPort = ref('')
    const editingProbe = ref(null)

    const form = ref({
      name: '',
      host: '',
      port: 22,
      description: '',
      server_url: '',
      interval: 60,
      ports: []
    })

    const isFormValid = computed(() => {
      return form.value.name.trim() && 
             form.value.host.trim() && 
             form.value.server_url.trim()
    })

    const addPort = () => {
      const port = parseInt(newPort.value)
      if (port && !form.value.ports.includes(port)) {
        form.value.ports.push(port)
        newPort.value = ''
      }
    }

    const removePort = (port) => {
      form.value.ports = form.value.ports.filter(p => p !== port)
    }

    const resetForm = () => {
      form.value = {
        name: '',
        host: '',
        port: 22,
        description: '',
        server_url: '',
        interval: 60,
        ports: []
      }
      error.value = ''
      newPort.value = ''
      editingProbe.value = null
    }

    const closeModals = () => {
      showCreateModal.value = false
      showEditModal.value = false
      resetForm()
    }

    const handleSubmit = async () => {
      loading.value = true
      error.value = ''

      try {
        const probeData = { ...form.value }
        
        if (showCreateModal.value) {
          await emit('create-probe', probeData)
        } else if (editingProbe.value) {
          await emit('update-probe', editingProbe.value.id, probeData)
        }
        
        closeModals()
      } catch (err) {
        error.value = '操作失败，请重试'
        console.error('Probe operation error:', err)
      } finally {
        loading.value = false
      }
    }

    const handleEdit = (probe) => {
      editingProbe.value = probe
      form.value = {
        name: probe.name,
        host: probe.host,
        port: probe.port,
        description: probe.description || '',
        server_url: '',
        interval: 60,
        ports: []
      }
      showEditModal.value = true
    }

    const handleDelete = (probe) => {
      probeToDelete.value = probe
      showDeleteModal.value = true
    }

    const confirmDelete = async () => {
      if (!probeToDelete.value) return
      
      loading.value = true
      try {
        await emit('delete-probe', probeToDelete.value.id)
        showDeleteModal.value = false
        probeToDelete.value = null
      } catch (err) {
        error.value = '删除失败，请重试'
        console.error('Delete probe error:', err)
      } finally {
        loading.value = false
      }
    }

    const handleDownload = async (probe) => {
      try {
        await emit('download-probe', probe.id)
      } catch (err) {
        error.value = '下载失败，请重试'
        console.error('Download probe error:', err)
      }
    }

    const getCertStatusClass = (status) => {
      if (status.includes('有效') || status.includes('活跃')) return 'valid'
      if (status.includes('即将过期') || status.includes('警告')) return 'warning'
      if (status.includes('已过期') || status.includes('吊销')) return 'expired'
      return 'unknown'
    }

    const formatDate = (dateStr) => {
      return new Date(dateStr).toLocaleDateString('zh-CN')
    }

    const formatTime = (timeStr) => {
      return new Date(timeStr).toLocaleString('zh-CN')
    }

    return {
      showCreateModal,
      showEditModal,
      showDeleteModal,
      loading,
      error,
      form,
      newPort,
      isFormValid,
      addPort,
      removePort,
      closeModals,
      handleSubmit,
      handleEdit,
      handleDelete,
      confirmDelete,
      handleDownload,
      getCertStatusClass,
      formatDate,
      formatTime
    }
  }
}
</script>

<style scoped>
.probe-management {
  padding: 0;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 2rem;
}

.page-header h2 {
  color: #374151;
  font-size: 1.5rem;
  font-weight: 600;
}

.create-btn {
  padding: 0.75rem 1.5rem;
  background: #10b981;
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
}

.create-btn:hover {
  background: #059669;
  transform: translateY(-1px);
}

.empty-state {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 400px;
}

.empty-content {
  text-align: center;
  padding: 2rem;
}

.empty-icon {
  font-size: 4rem;
  margin-bottom: 1rem;
}

.empty-content h3 {
  color: #374151;
  font-size: 1.5rem;
  margin-bottom: 0.5rem;
}

.empty-content p {
  color: #6b7280;
  margin-bottom: 2rem;
}

.probe-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
  gap: 1.5rem;
}

.probe-card {
  background: white;
  border-radius: 8px;
  padding: 1.5rem;
  border: 1px solid #e5e7eb;
  transition: all 0.2s ease;
}

.probe-card:hover {
  border-color: #3b82f6;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.probe-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1rem;
}

.probe-info h3 {
  color: #1f2937;
  font-size: 1.1rem;
  font-weight: 600;
  margin-bottom: 0.25rem;
}

.probe-host {
  color: #6b7280;
  font-size: 0.875rem;
}

.status-badge {
  padding: 0.25rem 0.75rem;
  border-radius: 20px;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
}

.status-badge.active {
  background: #dcfce7;
  color: #166534;
}

.status-badge.inactive {
  background: #fee2e2;
  color: #991b1b;
}

.probe-details {
  margin-bottom: 1rem;
}

.detail-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0;
  border-bottom: 1px solid #f3f4f6;
}

.detail-item:last-child {
  border-bottom: none;
}

.detail-item label {
  color: #6b7280;
  font-size: 0.875rem;
}

.detail-item span {
  color: #374151;
  font-size: 0.875rem;
}

.cert-status.valid {
  color: #16a34a;
}

.cert-status.warning {
  color: #ea580c;
}

.cert-status.expired {
  color: #dc2626;
}

.probe-description {
  margin-bottom: 1rem;
  padding: 0.75rem;
  background: #f9fafb;
  border-radius: 6px;
}

.probe-description p {
  color: #6b7280;
  font-size: 0.875rem;
  line-height: 1.4;
}

.probe-actions {
  display: flex;
  gap: 0.5rem;
}

.probe-actions button {
  flex: 1;
  padding: 0.5rem;
  border: none;
  border-radius: 4px;
  font-size: 0.875rem;
  cursor: pointer;
  transition: all 0.2s ease;
}

.edit-btn {
  background: #3b82f6;
  color: white;
}

.edit-btn:hover {
  background: #2563eb;
}

.download-btn {
  background: #f59e0b;
  color: white;
}

.download-btn:hover {
  background: #d97706;
}

.delete-btn {
  background: #ef4444;
  color: white;
}

.delete-btn:hover {
  background: #dc2626;
}

.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
}

.modal-content {
  background: white;
  border-radius: 8px;
  width: 90%;
  max-width: 600px;
  max-height: 90vh;
  overflow-y: auto;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1.5rem;
  border-bottom: 1px solid #e5e7eb;
}

.modal-header h3 {
  color: #1f2937;
  font-size: 1.25rem;
  font-weight: 600;
}

.close-btn {
  background: none;
  border: none;
  font-size: 1.5rem;
  color: #6b7280;
  cursor: pointer;
  padding: 0.25rem;
}

.modal-form {
  padding: 1.5rem;
}

.form-group {
  margin-bottom: 1.5rem;
}

.form-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

.form-group label {
  display: block;
  color: #374151;
  font-size: 0.875rem;
  font-weight: 500;
  margin-bottom: 0.5rem;
}

.form-group input,
.form-group textarea {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #d1d5db;
  border-radius: 6px;
  font-size: 0.875rem;
  transition: border-color 0.2s ease;
}

.form-group input:focus,
.form-group textarea:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.ports-input {
  display: flex;
  gap: 0.5rem;
}

.ports-input input {
  flex: 1;
}

.ports-input button {
  padding: 0.75rem 1rem;
  background: #3b82f6;
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.875rem;
}

.ports-input button:hover:not(:disabled) {
  background: #2563eb;
}

.ports-list {
  margin-top: 0.5rem;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.port-tag {
  display: inline-flex;
  align-items: center;
  padding: 0.25rem 0.5rem;
  background: #dbeafe;
  color: #1e40af;
  border-radius: 4px;
  font-size: 0.75rem;
  gap: 0.5rem;
}

.remove-port {
  background: none;
  border: none;
  color: #1e40af;
  cursor: pointer;
  padding: 0;
  margin-left: 0.25rem;
}

.error-message {
  background: #fef2f2;
  color: #dc2626;
  padding: 0.75rem;
  border-radius: 6px;
  font-size: 0.875rem;
  margin-bottom: 1rem;
  border: 1px solid #fecaca;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 1rem;
  margin-top: 2rem;
}

.modal-actions button {
  padding: 0.75rem 1.5rem;
  border: 1px solid #d1d5db;
  border-radius: 6px;
  background: white;
  color: #374151;
  cursor: pointer;
  font-size: 0.875rem;
}

.modal-actions button:hover:not(:disabled) {
  background: #f9fafb;
}

.submit-btn {
  background: #3b82f6 !important;
  color: white !important;
  border-color: #3b82f6 !important;
}

.submit-btn:hover:not(:disabled) {
  background: #2563eb !important;
}

.delete-modal {
  max-width: 400px;
}

.delete-content {
  padding: 1.5rem;
}

.delete-content p {
  margin-bottom: 1rem;
  color: #374151;
}

.warning {
  color: #dc2626 !important;
  font-size: 0.875rem;
}

.spinner {
  width: 16px;
  height: 16px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top: 2px solid currentColor;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

@media (max-width: 768px) {
  .probe-grid {
    grid-template-columns: 1fr;
  }
  
  .page-header {
    flex-direction: column;
    gap: 1rem;
    align-items: stretch;
  }
  
  .form-row {
    grid-template-columns: 1fr;
  }
  
  .modal-content {
    width: 95%;
    margin: 1rem;
  }
}
</style>