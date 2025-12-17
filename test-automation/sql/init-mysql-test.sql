-- VerneMQ MySQL Test Database Initialization Script
-- This script sets up test users and permissions for VerneMQ testing with MySQL

-- Create test database
CREATE DATABASE IF NOT EXISTS vernemq_test;
USE vernemq_test;

-- Create test users table for authentication
CREATE TABLE IF NOT EXISTS vmq_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create test ACL rules table
CREATE TABLE IF NOT EXISTS vmq_acl_rules (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    topic_pattern VARCHAR(255) NOT NULL,
    permission ENUM('publish', 'subscribe') NOT NULL,
    qos_level INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create test session data table
CREATE TABLE IF NOT EXISTS vmq_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(255),
    session_data JSON,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Create test plugin configuration table
CREATE TABLE IF NOT EXISTS vmq_plugin_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    plugin_name VARCHAR(255) NOT NULL,
    config_key VARCHAR(255) NOT NULL,
    config_value TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test users with hashed passwords
INSERT INTO vmq_users (username, password_hash, is_active) VALUES
('testuser', 'testpassword123', TRUE),
('admin', 'admin123', TRUE),
('sensor1', 'sensorpass1', TRUE),
('sensor2', 'sensorpass2', TRUE),
('device1', 'devicepass1', TRUE),
('device2', 'devicepass2', TRUE)
ON DUPLICATE KEY UPDATE 
    password_hash = VALUES(password_hash),
    is_active = VALUES(is_active);

-- Insert test ACL rules
INSERT INTO vmq_acl_rules (username, topic_pattern, permission, qos_level, is_active) VALUES
('testuser', 'test/#', 'publish', 1, TRUE),
('testuser', 'test/#', 'subscribe', 1, TRUE),
('admin', '#', 'publish', 2, TRUE),
('admin', '#', 'subscribe', 2, TRUE),
('sensor1', 'sensors/+/data', 'publish', 0, TRUE),
('sensor1', 'sensors/+/status', 'publish', 0, TRUE),
('sensor2', 'sensors/+/data', 'publish', 0, TRUE),
('sensor2', 'sensors/+/status', 'publish', 0, TRUE),
('device1', 'devices/+/command', 'subscribe', 1, TRUE),
('device1', 'devices/+/status', 'publish', 1, TRUE),
('device2', 'devices/+/command', 'subscribe', 1, TRUE),
('device2', 'devices/+/status', 'publish', 1, TRUE)
ON DUPLICATE KEY UPDATE
    topic_pattern = VALUES(topic_pattern),
    permission = VALUES(permission),
    qos_level = VALUES(qos_level),
    is_active = VALUES(is_active);

-- Insert test plugin configurations
INSERT INTO vmq_plugin_config (plugin_name, config_key, config_value, is_active) VALUES
('vmq_diversity', 'mysql_host', 'mysql', TRUE),
('vmq_diversity', 'mysql_port', '3306', TRUE),
('vmq_diversity', 'mysql_database', 'vernemq_test', TRUE),
('vmq_diversity', 'mysql_user', 'vmq_test_user', TRUE),
('vmq_diversity', 'mysql_password', 'vmq_test_password', TRUE),
('vmq_acl', 'config_file', '/opt/vernemq/etc/vmq.acl', TRUE),
('vmq_webhooks', 'enabled', 'false', TRUE)
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    is_active = VALUES(is_active);

-- Create indexes for better performance
CREATE INDEX idx_vmq_users_username ON vmq_users(username);
CREATE INDEX idx_vmq_users_active ON vmq_users(is_active);
CREATE INDEX idx_vmq_acl_rules_username ON vmq_acl_rules(username);
CREATE INDEX idx_vmq_acl_rules_pattern ON vmq_acl_rules(topic_pattern);
CREATE INDEX idx_vmq_sessions_client_id ON vmq_sessions(client_id);
CREATE INDEX idx_vmq_sessions_active ON vmq_sessions(is_active);
CREATE INDEX idx_vmq_plugin_config_plugin ON vmq_plugin_config(plugin_name);

-- Grant permissions to test user
GRANT ALL PRIVILEGES ON vernemq_test.* TO 'vmq_test_user'@'%';
FLUSH PRIVILEGES;

-- Create a view for easy user authentication queries
CREATE OR REPLACE VIEW vmq_auth_view AS
SELECT 
    u.username,
    u.password_hash,
    u.is_active,
    GROUP_CONCAT(DISTINCT CONCAT(a.topic_pattern, ':', a.permission, ':', a.qos_level) SEPARATOR ',') as acl_rules
FROM vmq_users u
LEFT JOIN vmq_acl_rules a ON u.username = a.username AND a.is_active = TRUE
WHERE u.is_active = TRUE
GROUP BY u.username, u.password_hash, u.is_active;

-- Insert some sample session data for testing
INSERT INTO vmq_sessions (client_id, username, session_data, is_active) VALUES
('test-client-001', 'testuser', '{"subscriptions": ["test/topic1", "test/topic2"], "qos": 1}', TRUE),
('sensor-client-001', 'sensor1', '{"subscriptions": ["sensors/+/data"], "qos": 0, "last_reading": "23.5"}', TRUE),
('device-client-001', 'device1', '{"subscriptions": ["devices/+/command"], "qos": 1, "status": "online"}', TRUE)
ON DUPLICATE KEY UPDATE
    session_data = VALUES(session_data),
    last_seen = CURRENT_TIMESTAMP,
    is_active = VALUES(is_active);

-- Final verification
SELECT 'VerneMQ MySQL test database initialization completed successfully!' as status;