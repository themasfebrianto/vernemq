-- VerneMQ Test Database Initialization Script
-- This script sets up test users and permissions for VerneMQ testing

-- Create test database if it doesn't exist
CREATE DATABASE IF NOT EXISTS vernemq_test;
USE vernemq_test;

-- Create test users table for authentication
CREATE TABLE IF NOT EXISTS vmq_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create test ACL rules table
CREATE TABLE IF NOT EXISTS vmq_acl_rules (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    topic_pattern VARCHAR(255) NOT NULL,
    permission ENUM('publish', 'subscribe') NOT NULL,
    qos_level INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create test session data table
CREATE TABLE IF NOT EXISTS vmq_sessions (
    id SERIAL PRIMARY KEY,
    client_id VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(255),
    session_data JSON,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Create test plugin configuration table
CREATE TABLE IF NOT EXISTS vmq_plugin_config (
    id SERIAL PRIMARY KEY,
    plugin_name VARCHAR(255) NOT NULL,
    config_key VARCHAR(255) NOT NULL,
    config_value TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test users with hashed passwords
-- Note: In production, these would be properly hashed
INSERT INTO vmq_users (username, password_hash, is_active) VALUES
('testuser', 'testpassword123', true),
('admin', 'admin123', true),
('sensor1', 'sensorpass1', true),
('sensor2', 'sensorpass2', true),
('device1', 'devicepass1', true),
('device2', 'devicepass2', true)
ON DUPLICATE KEY UPDATE 
    password_hash = VALUES(password_hash),
    is_active = VALUES(is_active);

-- Insert test ACL rules
INSERT INTO vmq_acl_rules (username, topic_pattern, permission, qos_level, is_active) VALUES
('testuser', 'test/#', 'publish', 1, true),
('testuser', 'test/#', 'subscribe', 1, true),
('admin', '#', 'publish', 2, true),
('admin', '#', 'subscribe', 2, true),
('sensor1', 'sensors/+/data', 'publish', 0, true),
('sensor1', 'sensors/+/status', 'publish', 0, true),
('sensor2', 'sensors/+/data', 'publish', 0, true),
('sensor2', 'sensors/+/status', 'publish', 0, true),
('device1', 'devices/+/command', 'subscribe', 1, true),
('device1', 'devices/+/status', 'publish', 1, true),
('device2', 'devices/+/command', 'subscribe', 1, true),
('device2', 'devices/+/status', 'publish', 1, true)
ON DUPLICATE KEY UPDATE
    topic_pattern = VALUES(topic_pattern),
    permission = VALUES(permission),
    qos_level = VALUES(qos_level),
    is_active = VALUES(is_active);

-- Insert test plugin configurations
INSERT INTO vmq_plugin_config (plugin_name, config_key, config_value, is_active) VALUES
('vmq_diversity', 'postgresql_host', 'postgres', true),
('vmq_diversity', 'postgresql_port', '5432', true),
('vmq_diversity', 'postgresql_database', 'vernemq_test', true),
('vmq_diversity', 'postgresql_user', 'vmq_test_user', true),
('vmq_diversity', 'postgresql_password', 'vmq_test_password', true),
('vmq_acl', 'config_file', '/opt/vernemq/etc/vmq.acl', true),
('vmq_webhooks', 'enabled', 'false', true)
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    is_active = VALUES(is_active);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_vmq_users_username ON vmq_users(username);
CREATE INDEX IF NOT EXISTS idx_vmq_users_active ON vmq_users(is_active);
CREATE INDEX IF NOT EXISTS idx_vmq_acl_rules_username ON vmq_acl_rules(username);
CREATE INDEX IF NOT EXISTS idx_vmq_acl_rules_pattern ON vmq_acl_rules(topic_pattern);
CREATE INDEX IF NOT EXISTS idx_vmq_sessions_client_id ON vmq_sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_vmq_sessions_active ON vmq_sessions(is_active);
CREATE INDEX IF NOT EXISTS idx_vmq_plugin_config_plugin ON vmq_plugin_config(plugin_name);

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
LEFT JOIN vmq_acl_rules a ON u.username = a.username AND a.is_active = true
WHERE u.is_active = true
GROUP BY u.username, u.password_hash, u.is_active;

-- Insert some sample session data for testing
INSERT INTO vmq_sessions (client_id, username, session_data, is_active) VALUES
('test-client-001', 'testuser', '{"subscriptions": ["test/topic1", "test/topic2"], "qos": 1}', true),
('sensor-client-001', 'sensor1', '{"subscriptions": ["sensors/+/data"], "qos": 0, "last_reading": "23.5"}', true),
('device-client-001', 'device1', '{"subscriptions": ["devices/+/command"], "qos": 1, "status": "online"}', true)
ON DUPLICATE KEY UPDATE
    session_data = VALUES(session_data),
    last_seen = CURRENT_TIMESTAMP,
    is_active = VALUES(is_active);

-- Create stored procedures for common operations
DELIMITER //

-- Procedure to authenticate user
CREATE PROCEDURE IF NOT EXISTS AuthenticateUser(
    IN p_username VARCHAR(255),
    IN p_password VARCHAR(255),
    OUT p_result BOOLEAN,
    OUT p_user_id INT
)
BEGIN
    DECLARE v_password_hash VARCHAR(255);
    
    SELECT password_hash, id INTO v_password_hash, p_user_id
    FROM vmq_users 
    WHERE username = p_username AND is_active = true;
    
    -- In a real implementation, you would verify the password hash
    -- For testing purposes, we'll do a simple comparison
    IF v_password_hash = p_password THEN
        SET p_result = TRUE;
    ELSE
        SET p_result = FALSE;
        SET p_user_id = NULL;
    END IF;
END//

-- Procedure to get ACL rules for user
CREATE PROCEDURE IF NOT EXISTS GetUserACL(
    IN p_username VARCHAR(255)
)
BEGIN
    SELECT topic_pattern, permission, qos_level
    FROM vmq_acl_rules
    WHERE username = p_username AND is_active = true
    ORDER BY topic_pattern;
END//

-- Procedure to update session data
CREATE PROCEDURE IF NOT EXISTS UpdateSession(
    IN p_client_id VARCHAR(255),
    IN p_username VARCHAR(255),
    IN p_session_data JSON
)
BEGIN
    INSERT INTO vmq_sessions (client_id, username, session_data, is_active)
    VALUES (p_client_id, p_username, p_session_data, true)
    ON DUPLICATE KEY UPDATE
        username = p_username,
        session_data = p_session_data,
        last_seen = CURRENT_TIMESTAMP,
        is_active = true;
END//

DELIMITER ;

-- Final verification
SELECT 'VerneMQ test database initialization completed successfully!' as status;