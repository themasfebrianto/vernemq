/**
 * VerneMQ Webhook Dashboard - Main JavaScript Module
 * ====================================================
 * Handles all API interactions, state management, and UI updates
 */

// =============================================================================
// STATE MANAGEMENT
// =============================================================================

const DashboardState = {
    mqttUsers: [],
    webhooks: [],
    systemStats: null,
    previousMetrics: {
        connections: 0,
        messages: 0,
        errors: 0
    },
    refreshInterval: null
};

// =============================================================================
// API SERVICE
// =============================================================================

const API = {
    baseUrl: '',

    async fetch(endpoint, options = {}) {
        try {
            const response = await fetch(`${this.baseUrl}${endpoint}`, {
                headers: { 'Content-Type': 'application/json', ...options.headers },
                ...options
            });
            return response;
        } catch (error) {
            console.error(`API Error [${endpoint}]:`, error);
            throw error;
        }
    },

    async get(endpoint) {
        return this.fetch(endpoint);
    },

    async post(endpoint, data) {
        return this.fetch(endpoint, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },

    async put(endpoint, data) {
        return this.fetch(endpoint, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
    },

    async delete(endpoint) {
        return this.fetch(endpoint, { method: 'DELETE' });
    }
};

// =============================================================================
// MQTT USER MANAGEMENT
// =============================================================================

const MqttUsers = {
    async load() {
        try {
            const search = document.getElementById('mqttUserSearch')?.value || '';
            const activeOnly = document.getElementById('mqttUserFilter')?.value || '';

            let url = '/api/mqttusers?';
            if (search) url += `search=${encodeURIComponent(search)}&`;
            if (activeOnly) url += `activeOnly=${activeOnly}&`;

            const response = await API.get(url);
            if (response.ok) {
                const data = await response.json();
                DashboardState.mqttUsers = data.items || [];
                this.render();
            }
        } catch (error) {
            console.error('Error loading MQTT users:', error);
            UI.showToast('Error loading MQTT users', 'danger');
        }
    },

    async loadStats() {
        try {
            const response = await API.get('/api/mqttusers/stats');
            if (response.ok) {
                const stats = await response.json();
                UI.setText('totalMqttUsers', stats.totalUsers);
                UI.setText('activeMqttUsers', stats.activeUsers);
                UI.setText('adminMqttUsers', stats.adminUsers);
                UI.setText('recentLogins', stats.recentLogins24h);
            }
        } catch (error) {
            console.error('Error loading stats:', error);
        }
    },

    render() {
        const tbody = document.getElementById('mqttUserTableBody');
        if (!tbody) return;

        if (DashboardState.mqttUsers.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" class="empty-state">
                        <i class="fas fa-users-slash empty-state-icon d-block"></i>
                        <div class="empty-state-text">No MQTT users found</div>
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = DashboardState.mqttUsers.map(user => `
            <tr>
                <td>
                    <div class="fw-semibold">${Utils.escapeHtml(user.username)}</div>
                    ${user.allowedClientId ? `<div class="small text-muted font-mono">${Utils.escapeHtml(user.allowedClientId)}</div>` : ''}
                </td>
                <td class="text-secondary">${user.description || '<span class="text-muted">–</span>'}</td>
                <td>
                    <span class="badge ${user.isActive ? 'badge-success' : 'badge-neutral'}">
                        ${user.isActive ? 'Active' : 'Inactive'}
                    </span>
                </td>
                <td>
                    ${user.isAdmin ? '<span class="badge badge-admin">Admin</span>' : '<span class="text-muted">Standard</span>'}
                </td>
                <td>
                    <div class="small">${user.lastLoginAt ? Utils.formatDateTime(user.lastLoginAt) : '<span class="text-muted">Never</span>'}</div>
                    ${user.lastLoginIp ? `<div class="small text-muted font-mono">${user.lastLoginIp}</div>` : ''}
                </td>
                <td class="fw-semibold text-center">${user.loginCount}</td>
                <td>
                    <div class="d-flex justify-content-end gap-1">
                        <button class="btn btn-outline btn-sm btn-icon" onclick="MqttUsers.edit(${user.id})" title="Edit">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-outline btn-sm btn-icon" onclick="MqttUsers.toggleActive(${user.id})" 
                            title="${user.isActive ? 'Deactivate' : 'Activate'}">
                            <i class="fas fa-${user.isActive ? 'pause' : 'play'}"></i>
                        </button>
                        <button class="btn btn-outline btn-sm btn-icon text-danger" 
                            onclick="MqttUsers.delete(${user.id}, '${Utils.escapeHtml(user.username)}')" title="Delete">
                            <i class="fas fa-trash-can"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `).join('');
    },

    async create() {
        const form = document.getElementById('createMqttUserForm');
        const formData = new FormData(form);

        const data = {
            username: formData.get('username'),
            password: formData.get('password'),
            description: formData.get('description') || null,
            allowedClientId: formData.get('allowedClientId') || null,
            allowedPublishTopics: formData.get('allowedPublishTopics') || null,
            allowedSubscribeTopics: formData.get('allowedSubscribeTopics') || null,
            maxConnections: parseInt(formData.get('maxConnections')) || 0,
            isAdmin: formData.get('isAdmin') === 'on'
        };

        try {
            const response = await API.post('/api/mqttusers', data);
            if (response.ok) {
                UI.closeModal('createMqttUserModal');
                form.reset();
                this.load();
                this.loadStats();
                UI.showToast('MQTT user created successfully!', 'success');
            } else {
                const error = await response.json();
                UI.showToast(error.error || 'Failed to create user', 'danger');
            }
        } catch (error) {
            UI.showToast('Error creating user: ' + error.message, 'danger');
        }
    },

    async edit(id) {
        try {
            const response = await API.get(`/api/mqttusers/${id}`);
            if (response.ok) {
                const user = await response.json();
                document.getElementById('editUserId').value = user.id;
                document.getElementById('editUsername').value = user.username;
                document.getElementById('editDescription').value = user.description || '';
                document.getElementById('editMaxConnections').value = user.maxConnections;
                document.getElementById('editPublishTopics').value = user.allowedPublishTopics || '';
                document.getElementById('editSubscribeTopics').value = user.allowedSubscribeTopics || '';
                document.getElementById('editIsAdmin').checked = user.isAdmin;
                document.getElementById('editIsActive').checked = user.isActive;

                UI.openModal('editMqttUserModal');
            }
        } catch (error) {
            UI.showToast('Error loading user: ' + error.message, 'danger');
        }
    },

    async update() {
        const id = document.getElementById('editUserId').value;
        const form = document.getElementById('editMqttUserForm');
        const formData = new FormData(form);

        const data = {
            description: formData.get('description') || null,
            allowedPublishTopics: formData.get('allowedPublishTopics') || null,
            allowedSubscribeTopics: formData.get('allowedSubscribeTopics') || null,
            maxConnections: parseInt(formData.get('maxConnections')) || 0,
            isAdmin: document.getElementById('editIsAdmin').checked,
            isActive: document.getElementById('editIsActive').checked
        };

        const newPassword = formData.get('newPassword');
        if (newPassword) data.newPassword = newPassword;

        try {
            const response = await API.put(`/api/mqttusers/${id}`, data);
            if (response.ok) {
                UI.closeModal('editMqttUserModal');
                this.load();
                this.loadStats();
                UI.showToast('MQTT user updated successfully!', 'success');
            } else {
                const error = await response.json();
                UI.showToast(error.error || 'Failed to update user', 'danger');
            }
        } catch (error) {
            UI.showToast('Error updating user: ' + error.message, 'danger');
        }
    },

    async toggleActive(id) {
        try {
            const response = await API.post(`/api/mqttusers/${id}/toggle-active`);
            if (response.ok) {
                this.load();
                this.loadStats();
                UI.showToast('User status toggled', 'success');
            }
        } catch (error) {
            UI.showToast('Error toggling user status', 'danger');
        }
    },

    async delete(id, username) {
        if (!confirm(`Are you sure you want to delete user "${username}"?`)) return;

        try {
            const response = await API.delete(`/api/mqttusers/${id}`);
            if (response.ok) {
                this.load();
                this.loadStats();
                UI.showToast('User deleted successfully', 'success');
            }
        } catch (error) {
            UI.showToast('Error deleting user', 'danger');
        }
    }
};

// =============================================================================
// WEBHOOK MANAGEMENT
// =============================================================================

const Webhooks = {
    async load() {
        try {
            const response = await API.get('/api/webhookmanagement');
            if (response.ok) {
                const data = await response.json();
                DashboardState.webhooks = data.items || [];
                this.render();
            }
        } catch (error) {
            console.error('Error loading webhooks:', error);
        }
    },

    render() {
        const tbody = document.getElementById('webhookTableBody');
        if (!tbody) return;

        if (DashboardState.webhooks.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="6" class="empty-state">
                        <i class="fas fa-link-slash empty-state-icon d-block"></i>
                        <div class="empty-state-text">No webhooks configured yet</div>
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = DashboardState.webhooks.map(wh => `
            <tr>
                <td>
                    <div class="fw-semibold">${Utils.escapeHtml(wh.name)}</div>
                    <div class="small text-muted">${Utils.escapeHtml(wh.description || '')}</div>
                </td>
                <td class="font-mono text-secondary truncate" style="max-width: 250px;">${Utils.escapeHtml(wh.url)}</td>
                <td><span class="badge badge-neutral">${wh.httpMethod}</span></td>
                <td>
                    <span class="badge ${wh.isActive ? 'badge-success' : 'badge-neutral'}">
                        ${wh.isActive ? 'Active' : 'Inactive'}
                    </span>
                </td>
                <td class="small text-secondary">${wh.updatedAt ? Utils.formatDateTime(wh.updatedAt) : '–'}</td>
                <td>
                    <div class="d-flex justify-content-end gap-1">
                        <button class="btn btn-outline btn-sm btn-icon text-success" onclick="Webhooks.test(${wh.id})" title="Test">
                            <i class="fas fa-play"></i>
                        </button>
                        <button class="btn btn-outline btn-sm btn-icon" onclick="Webhooks.edit(${wh.id})" title="Edit">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-outline btn-sm btn-icon text-danger" 
                            onclick="Webhooks.delete(${wh.id}, '${Utils.escapeHtml(wh.name)}')" title="Delete">
                            <i class="fas fa-trash-can"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `).join('');
    },

    async create() {
        const form = document.getElementById('createWebhookForm');
        const formData = new FormData(form);

        const triggers = [];
        form.querySelectorAll('input[name="triggers"]:checked').forEach(cb => {
            triggers.push(cb.value);
        });

        const data = {
            name: formData.get('name'),
            url: formData.get('url'),
            description: formData.get('description') || '',
            httpMethod: formData.get('httpMethod'),
            contentType: formData.get('contentType'),
            authenticationType: formData.get('authenticationType') || null,
            authenticationValue: formData.get('authenticationValue') || null,
            payloadTemplate: formData.get('payloadTemplate') || null,
            timeoutSeconds: parseInt(formData.get('timeoutSeconds')) || 30,
            retryCount: parseInt(formData.get('retryCount')) || 3,
            retryDelaySeconds: parseInt(formData.get('retryDelaySeconds')) || 5,
            triggers: triggers.length > 0 ? triggers : null
        };

        try {
            const response = await API.post('/api/webhookmanagement', data);
            if (response.ok) {
                UI.closeModal('createWebhookModal');
                form.reset();
                this.load();
                UI.showToast('Webhook created successfully!', 'success');
            } else {
                const error = await response.json();
                UI.showToast(error.error || 'Failed to create webhook', 'danger');
            }
        } catch (error) {
            UI.showToast('Error creating webhook: ' + error.message, 'danger');
        }
    },

    async edit(id) {
        try {
            const response = await API.get(`/api/webhookmanagement/${id}`);
            if (response.ok) {
                const wh = await response.json();
                document.getElementById('editWebhookId').value = wh.id;
                document.getElementById('editWebhookName').value = wh.name;
                document.getElementById('editWebhookMethod').value = wh.httpMethod;
                document.getElementById('editWebhookUrl').value = wh.url;
                document.getElementById('editWebhookDescription').value = wh.description || '';
                document.getElementById('editWebhookPayload').value = wh.payloadTemplate || '';
                document.getElementById('editWebhookTimeout').value = wh.timeoutSeconds;
                document.getElementById('editWebhookRetry').value = wh.retryCount;
                document.getElementById('editWebhookRetryDelay').value = wh.retryDelaySeconds;
                document.getElementById('editWebhookActive').checked = wh.isActive;

                UI.openModal('editWebhookModal');
            }
        } catch (error) {
            UI.showToast('Error loading webhook: ' + error.message, 'danger');
        }
    },

    async update() {
        const id = document.getElementById('editWebhookId').value;
        const form = document.getElementById('editWebhookForm');
        const formData = new FormData(form);

        const data = {
            name: formData.get('name'),
            url: formData.get('url'),
            description: formData.get('description'),
            httpMethod: formData.get('httpMethod'),
            payloadTemplate: formData.get('payloadTemplate'),
            timeoutSeconds: parseInt(formData.get('timeoutSeconds')),
            retryCount: parseInt(formData.get('retryCount')),
            retryDelaySeconds: parseInt(formData.get('retryDelaySeconds')),
            isActive: document.getElementById('editWebhookActive').checked
        };

        try {
            const response = await API.put(`/api/webhookmanagement/${id}`, data);
            if (response.ok) {
                UI.closeModal('editWebhookModal');
                this.load();
                UI.showToast('Webhook updated successfully!', 'success');
            } else {
                const error = await response.json();
                UI.showToast(error.error || 'Failed to update webhook', 'danger');
            }
        } catch (error) {
            UI.showToast('Error updating webhook: ' + error.message, 'danger');
        }
    },

    async delete(id, name) {
        if (!confirm(`Are you sure you want to delete webhook "${name}"?`)) return;

        try {
            const response = await API.delete(`/api/webhookmanagement/${id}`);
            if (response.ok) {
                this.load();
                UI.showToast('Webhook deleted successfully', 'success');
            }
        } catch (error) {
            UI.showToast('Error deleting webhook', 'danger');
        }
    },

    async test(id) {
        try {
            UI.showToast('Testing webhook...', 'info');
            const response = await API.post(`/api/webhookmanagement/${id}/test`, {});

            if (response.ok) {
                const result = await response.json();
                UI.showToast(`Webhook test started. Execution ID: ${result.executionLogId}`, 'success');
            } else {
                const error = await response.json();
                UI.showToast(error.error || 'Failed to test webhook', 'danger');
            }
        } catch (error) {
            UI.showToast('Error testing webhook: ' + error.message, 'danger');
        }
    }
};

// =============================================================================
// MONITORING
// =============================================================================

const Monitoring = {
    async loadVerneMQMetrics() {
        const startTime = Date.now();
        try {
            const response = await API.get('/api/system/vernemq-metrics');
            const latency = Date.now() - startTime;

            if (response.ok) {
                const metrics = await response.json();

                this.updateStatusCard('vernemq', metrics.isOnline);
                this.updateStatusCard('webhook', true);

                UI.setText('webhookLatency', `Latency: ${latency}ms`);

                const currentConnections = metrics.activeConnections || 0;
                const currentMessages = Math.round(metrics.messagesPerMinute || 0);

                this.updateMetricWithTrend('mqttConnections', 'connectionsTrend',
                    currentConnections, DashboardState.previousMetrics.connections);
                this.updateMetricWithTrend('mqttMessages', 'messagesTrend',
                    currentMessages, DashboardState.previousMetrics.messages);

                UI.setText('mqttSubscriptions', Utils.formatNumber(metrics.totalSubscriptions || 0));
                UI.setText('publishRate', Utils.formatNumber(metrics.messagesReceived || 0));
                UI.setText('subscribeRate', Utils.formatNumber(metrics.messagesSent || 0));
                UI.setText('publishRateBytes', Utils.formatBytes(metrics.bytesReceived || 0));
                UI.setText('subscribeRateBytes', Utils.formatBytes(metrics.bytesSent || 0));
                UI.setText('activeSessionsCount', Utils.formatNumber(currentConnections));
                UI.setText('lastRefresh', 'Last check: ' + new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));

                DashboardState.previousMetrics.connections = currentConnections;
                DashboardState.previousMetrics.messages = currentMessages;

                this.updateSignal('signalLatency', latency, [200, 500], `${latency}ms`);

            } else {
                this.updateStatusCard('vernemq', false);
                this.showAlert('vernemq-offline', 'VerneMQ Broker Offline',
                    'Unable to connect to VerneMQ. Check if the broker is running.', 'danger');
            }
        } catch (error) {
            console.error('Error loading VerneMQ metrics:', error);
            this.updateStatusCard('vernemq', false);
            this.showAlert('vernemq-error', 'VerneMQ Connection Error', error.message, 'danger');
        }
    },

    async loadSystemStatistics() {
        try {
            const response = await API.get('/api/system/statistics');
            if (response.ok) {
                DashboardState.systemStats = await response.json();
                const stats = DashboardState.systemStats;

                // Update health score - 100% if no executions (no failures = perfect health)
                const healthRate = stats.totalExecutions > 0 ? (stats.successRate || 0) : 100;
                this.updateHealthScore(healthRate, stats.totalExecutions || 0);

                // Update system uptime
                if (stats.uptime) {
                    UI.setText('systemUptime', Utils.formatUptime(stats.uptime));
                }

                UI.setText('failedAuthCount', stats.failedExecutions || 0);

                const failureRate = stats.totalExecutions > 0
                    ? ((stats.failedExecutions / stats.totalExecutions) * 100)
                    : 0;
                this.updateSignal('signalWebhooks', failureRate, [5, 15],
                    failureRate > 0 ? `${failureRate.toFixed(1)}% fail` : 'All OK', true);

                const pending = stats.pendingExecutions || 0;
                UI.setText('signalQueueDetails', pending > 0 ? `${pending} pending` : 'Clear');
                this.updateSignal('signalQueue', pending, [5, 20],
                    pending > 0 ? `${pending} pending` : 'Clear');

                const avgResponse = stats.averageResponseTimeMs || 0;
                this.updateSignal('signalLatency', avgResponse, [500, 2000],
                    avgResponse > 0 ? `${Math.round(avgResponse)}ms` : '--ms');
            }
        } catch (error) {
            console.error('Error loading system statistics:', error);
        }
    },

    async loadExecutionLogs() {
        try {
            const response = await API.get('/api/webhookmanagement/logs?pageSize=50');
            if (response.ok) {
                const data = await response.json();
                const logs = data.items || [];
                this.renderLogs(logs);
                this.updateErrorSummary(logs);
            }
        } catch (error) {
            console.error('Error loading logs:', error);
        }
    },

    renderLogs(logs) {
        const tbody = document.getElementById('logsTableBody');
        if (!tbody) return;

        if (logs.length === 0) {
            tbody.innerHTML = `<tr><td colspan="5" class="empty-state">No execution logs</td></tr>`;
            return;
        }

        tbody.innerHTML = logs.map(log => `
            <tr>
                <td class="small fw-medium">${Utils.formatDateTime(log.executionTime)}</td>
                <td class="small font-mono text-secondary">#${log.webhookId || log.id}</td>
                <td><span class="badge ${log.status === 'Success' ? 'badge-success' : 'badge-danger'}">${log.status}</span></td>
                <td class="small text-secondary">${log.responseTimeMs ? log.responseTimeMs + 'ms' : '–'}</td>
                <td class="small text-secondary">${log.triggeredBy || '–'}</td>
            </tr>
        `).join('');
    },

    updateErrorSummary(logs) {
        const now = new Date();
        const oneDayAgo = new Date(now - 24 * 60 * 60 * 1000);

        const recentErrors = logs.filter(log => {
            const isError = log.status !== 'Success';
            const logTime = new Date(log.executionTime);
            return isError && logTime >= oneDayAgo;
        });

        const errorCount = recentErrors.length;

        this.updateMetricWithTrend('errorCount24h', 'errorsTrend', errorCount, DashboardState.previousMetrics.errors);
        DashboardState.previousMetrics.errors = errorCount;

        const errorBadgeEl = document.getElementById('errorBadge');
        if (errorBadgeEl) {
            errorBadgeEl.textContent = errorCount;
            errorBadgeEl.className = errorCount > 0 ? 'badge badge-danger' : 'badge badge-neutral';
        }

        const errorsCardEl = document.getElementById('errorsCard');
        if (errorsCardEl) {
            errorsCardEl.className = errorCount > 5 ? 'metric-card accent-left accent-danger' :
                errorCount > 0 ? 'metric-card accent-left accent-warning' :
                    'metric-card accent-left accent-success';
        }

        this.updateSignal('signalAuth', errorCount, [3, 10],
            errorCount > 0 ? `${errorCount} errors` : 'All OK');

        if (errorCount > 10) {
            this.showAlert('high-error-rate', 'High Error Rate Detected',
                `${errorCount} webhook failures in the last 24 hours.`, 'danger');
        } else if (errorCount > 5) {
            this.showAlert('elevated-errors', 'Elevated Error Rate',
                `${errorCount} webhook failures detected.`, 'warning');
        } else {
            this.clearAlert('high-error-rate');
            this.clearAlert('elevated-errors');
        }

        this.renderRecentErrors(recentErrors);
    },

    renderRecentErrors(errors) {
        const listEl = document.getElementById('recentErrorsList');
        if (!listEl) return;

        if (errors.length === 0) {
            listEl.innerHTML = `
                <div class="empty-state" style="padding: 1rem;">
                    <i class="fas fa-check-circle text-success"></i>
                    <span class="ms-2">No recent errors</span>
                </div>
            `;
            return;
        }

        const displayErrors = errors.slice(0, 5);
        listEl.innerHTML = displayErrors.map(log => `
            <div class="error-item">
                <i class="fas fa-times-circle error-item-icon"></i>
                <div class="error-item-content">
                    <div class="error-item-status">${log.status}</div>
                    <div class="error-item-time">${Utils.timeAgo(new Date(log.executionTime))}</div>
                </div>
            </div>
        `).join('');
    },

    updateStatusCard(service, isOnline) {
        const dotEl = document.getElementById(`${service}Dot`);
        const cardEl = document.getElementById(`${service}StatusCard`);

        if (dotEl) {
            dotEl.className = `status-dot ${isOnline ? 'online pulsing' : 'offline'}`;
        }

        if (cardEl) {
            const textEl = cardEl.querySelector('.status-card-value');
            if (textEl) {
                textEl.textContent = isOnline ? 'Online' : 'Offline';
                textEl.className = `status-card-value ${isOnline ? 'text-success' : 'text-danger'}`;
            }
        }

        if (isOnline) {
            this.clearAlert(`${service}-offline`);
            this.clearAlert(`${service}-error`);
        }
    },

    updateMetricWithTrend(metricId, trendId, current, previous) {
        const metricEl = document.getElementById(metricId);
        const trendEl = document.getElementById(trendId);

        if (metricEl) {
            metricEl.textContent = Utils.formatNumber(current);
        }

        if (trendEl && previous > 0) {
            const diff = current - previous;
            const percentChange = ((diff / previous) * 100).toFixed(0);

            if (diff > 0) {
                trendEl.className = 'metric-trend up';
                trendEl.innerHTML = `<i class="fas fa-arrow-up"></i> +${percentChange}%`;
            } else if (diff < 0) {
                trendEl.className = 'metric-trend down';
                trendEl.innerHTML = `<i class="fas fa-arrow-down"></i> ${percentChange}%`;
            } else {
                trendEl.className = 'metric-trend neutral';
                trendEl.innerHTML = `<i class="fas fa-minus"></i> 0%`;
            }
        }
    },

    updateHealthScore(successRate, totalExecutions) {
        const progressEl = document.getElementById('healthScoreProgress');
        const valueEl = document.getElementById('healthScoreValue');
        const detailsEl = document.getElementById('healthScoreDetails');

        if (progressEl && valueEl) {
            const circumference = 2 * Math.PI * 38;
            const offset = circumference - (successRate / 100) * circumference;

            progressEl.style.strokeDasharray = circumference;
            progressEl.style.strokeDashoffset = offset;
            valueEl.textContent = `${Math.round(successRate)}%`;

            // Color based on score - green for >= 95, yellow for >= 80, red for < 80
            let color = '#10b981'; // green
            if (successRate < 95 && totalExecutions > 0) color = '#f59e0b'; // yellow
            if (successRate < 80 && totalExecutions > 0) color = '#ef4444'; // red

            progressEl.style.stroke = color;
            valueEl.style.color = color;
        }

        if (detailsEl) {
            detailsEl.textContent = totalExecutions > 0
                ? `${totalExecutions} total executions`
                : 'No executions yet';
        }
    },

    updateSignal(signalId, value, thresholds, detailText, inverted = false) {
        const signalEl = document.getElementById(signalId);
        const detailsEl = document.getElementById(signalId + 'Details');

        if (!signalEl) return;

        let status = 'healthy';
        if (value > thresholds[1]) status = 'critical';
        else if (value > thresholds[0]) status = 'warning';

        signalEl.className = `signal-item ${status}`;
        const dotEl = signalEl.querySelector('.signal-dot');
        if (dotEl) dotEl.className = `signal-dot ${status}`;

        if (detailsEl && detailText) detailsEl.textContent = detailText;
    },

    showAlert(id, title, message, type = 'danger') {
        const container = document.getElementById('criticalAlertsContainer');
        if (!container) return;

        if (document.getElementById(`alert-${id}`)) return;

        const alertHtml = `
            <div class="alert-banner ${type}" id="alert-${id}">
                <div class="alert-icon">
                    <i class="fas ${type === 'danger' ? 'fa-circle-exclamation' : 'fa-triangle-exclamation'}"></i>
                </div>
                <div class="alert-content">
                    <div class="alert-title">${title}</div>
                    <div class="alert-message">${message}</div>
                </div>
                <div class="alert-actions">
                    <button class="btn btn-sm btn-outline" onclick="Monitoring.clearAlert('${id}')">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
            </div>
        `;

        container.insertAdjacentHTML('beforeend', alertHtml);
    },

    clearAlert(id) {
        const alert = document.getElementById(`alert-${id}`);
        if (alert) alert.remove();
    }
};

// =============================================================================
// UI UTILITIES
// =============================================================================

const UI = {
    setText(id, text) {
        const el = document.getElementById(id);
        if (el) el.textContent = text;
    },

    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `alert alert-${type} shadow-lg border-0 d-flex align-items-center gap-3 fade show position-fixed`;
        toast.style.cssText = 'bottom: 24px; right: 24px; z-index: 9999; min-width: 320px; border-radius: 12px; padding: 1rem 1.25rem;';

        const icons = {
            success: 'fa-circle-check',
            danger: 'fa-circle-exclamation',
            warning: 'fa-triangle-exclamation',
            info: 'fa-circle-info'
        };

        toast.innerHTML = `
            <i class="fas ${icons[type] || icons.info} fa-lg"></i>
            <div class="flex-grow-1 fw-medium">${message}</div>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;

        document.body.appendChild(toast);

        setTimeout(() => {
            if (toast.parentElement) {
                const bsAlert = new bootstrap.Alert(toast);
                bsAlert.close();
            }
        }, 4000);
    },

    openModal(id) {
        new bootstrap.Modal(document.getElementById(id)).show();
    },

    closeModal(id) {
        const modal = bootstrap.Modal.getInstance(document.getElementById(id));
        if (modal) modal.hide();
    }
};

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

const Utils = {
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    },

    formatNumber(num) {
        if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
        if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
        return num.toString();
    },

    formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    },

    formatDateTime(dateStr) {
        return new Date(dateStr).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' });
    },

    timeAgo(date) {
        const seconds = Math.floor((new Date() - date) / 1000);
        if (seconds < 60) return 'just now';
        if (seconds < 3600) return Math.floor(seconds / 60) + 'm ago';
        if (seconds < 86400) return Math.floor(seconds / 3600) + 'h ago';
        return Math.floor(seconds / 86400) + 'd ago';
    },

    formatUptime(uptimeStr) {
        // .NET TimeSpan JSON format can be:
        // "00:02:55.1234567" (hours:minutes:seconds.fraction) - short durations
        // "1.02:30:45.1234567" (days.hours:minutes:seconds.fraction) - long durations
        // "720:30:45" (hours:minutes:seconds) - hours can be > 24
        if (!uptimeStr) return '-';

        let totalHours = 0, minutes = 0;

        if (typeof uptimeStr === 'string') {
            // First, remove fractional seconds if present (everything after last dot in time part)
            let cleanStr = uptimeStr;

            // Check if format is "d.hh:mm:ss" (has dot before first colon) or "hh:mm:ss.fraction"
            const firstColonIdx = uptimeStr.indexOf(':');
            const firstDotIdx = uptimeStr.indexOf('.');

            if (firstDotIdx !== -1 && firstColonIdx !== -1 && firstDotIdx > firstColonIdx) {
                // Dot is after colon, so it's fractional seconds - strip it
                cleanStr = uptimeStr.substring(0, firstDotIdx);
            }

            if (firstDotIdx !== -1 && firstDotIdx < firstColonIdx) {
                // Dot is before colon - format is "days.hours:minutes:seconds"
                const [daysPart, rest] = cleanStr.split('.');
                const days = parseInt(daysPart) || 0;
                // rest might still have fractional, clean it
                const timeParts = rest.split(':');
                const hours = parseInt(timeParts[0]) || 0;
                minutes = parseInt(timeParts[1]) || 0;
                totalHours = days * 24 + hours;
            } else {
                // Format: "hours:minutes:seconds" (no days prefix)
                const parts = cleanStr.split(':');
                totalHours = parseInt(parts[0]) || 0;
                minutes = parseInt(parts[1]) || 0;
            }
        } else if (typeof uptimeStr === 'number') {
            // If it's a number, assume it's total seconds
            totalHours = Math.floor(uptimeStr / 3600);
            minutes = Math.floor((uptimeStr % 3600) / 60);
        }

        const days = Math.floor(totalHours / 24);
        const hours = totalHours % 24;

        if (days > 0) {
            return `${days}d ${hours}h`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m`;
        } else if (minutes > 0) {
            return `${minutes}m`;
        } else {
            return '< 1m';
        }
    },

    debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            clearTimeout(timeout);
            timeout = setTimeout(() => func.apply(this, args), wait);
        };
    }
};

// =============================================================================
// GLOBAL FUNCTIONS (for onclick handlers)
// =============================================================================

function createMqttUser() { MqttUsers.create(); }
function updateMqttUser() { MqttUsers.update(); }
function createWebhook() { Webhooks.create(); }
function updateWebhook() { Webhooks.update(); }
function editMqttUser(id) { MqttUsers.edit(id); }
function toggleMqttUserActive(id) { MqttUsers.toggleActive(id); }
function deleteMqttUser(id, username) { MqttUsers.delete(id, username); }
function editWebhook(id) { Webhooks.edit(id); }
function deleteWebhook(id, name) { Webhooks.delete(id, name); }
function testWebhook(id) { Webhooks.test(id); }

function refreshAllData() {
    MqttUsers.load();
    MqttUsers.loadStats();
    Webhooks.load();
    Monitoring.loadVerneMQMetrics();
    Monitoring.loadSystemStatistics();
    Monitoring.loadExecutionLogs();
}

// =============================================================================
// INITIALIZATION
// =============================================================================

document.addEventListener('DOMContentLoaded', function () {
    // Initial data load
    MqttUsers.load();
    MqttUsers.loadStats();
    Webhooks.load();
    Monitoring.loadVerneMQMetrics();
    Monitoring.loadSystemStatistics();
    Monitoring.loadExecutionLogs();

    // Auto-refresh monitoring data every 30 seconds
    DashboardState.refreshInterval = setInterval(() => {
        Monitoring.loadVerneMQMetrics();
        Monitoring.loadSystemStatistics();
        Monitoring.loadExecutionLogs();
    }, 30000);

    // Search and filter handlers
    const searchEl = document.getElementById('mqttUserSearch');
    if (searchEl) {
        searchEl.addEventListener('input', Utils.debounce(() => MqttUsers.load(), 300));
    }

    const filterEl = document.getElementById('mqttUserFilter');
    if (filterEl) {
        filterEl.addEventListener('change', () => MqttUsers.load());
    }

    // Auth type toggle
    const authTypeSelect = document.querySelector('select[name="authenticationType"]');
    const authValueContainer = document.getElementById('authValueContainer');
    if (authTypeSelect && authValueContainer) {
        authTypeSelect.addEventListener('change', function () {
            authValueContainer.style.display = this.value ? 'block' : 'none';
        });
    }
});
