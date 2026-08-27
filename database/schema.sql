-- =====================================================================
-- KrishiQueue Database Schema (SIH Problem Statement 26032)
-- Department of Consumer Affairs (DoCA) Procurement Platform
-- Compatible with: SQLite, PostgreSQL 12+, MySQL 8+ / MariaDB
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ROLES & PERMISSIONS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roles (
    role_id VARCHAR(32) PRIMARY KEY,
    role_name VARCHAR(64) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO roles (role_id, role_name, description) VALUES
('SUPER_ADMIN', 'Super Administrator', 'Full platform access, admin credential management, and audit logs'),
('CENTRE_OPERATOR', 'Procurement Centre Operator', 'Manages token queues, weights recording, and MSP confirmation'),
('FARMER_USER', 'Registered Farmer User', 'Can book procurement slots, track live tokens, and view payment status'),
('CITIZEN_VIEWER', 'Citizen Public Viewer', 'Read-only access to live mandi queue dashboards')
ON CONFLICT (role_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. ADMIN & OPERATOR CREDENTIALS TABLE
-- Stores official staff login credentials with salted cryptographic hashes
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_credentials (
    admin_id VARCHAR(64) PRIMARY KEY,
    username VARCHAR(64) UNIQUE NOT NULL,
    email VARCHAR(128) UNIQUE NOT NULL,
    phone VARCHAR(15) NOT NULL,
    name VARCHAR(128) NOT NULL,
    designation VARCHAR(128) DEFAULT 'Nodal Procurement Officer',
    assigned_centre_id VARCHAR(64),
    role VARCHAR(32) NOT NULL DEFAULT 'CENTRE_OPERATOR',
    
    -- Security & Hash Fields
    password_hash VARCHAR(128) NOT NULL,    -- SHA-256 (password + salt)
    salt VARCHAR(64) NOT NULL,             -- 16-byte Cryptographic Random Salt (Hex)
    
    -- 2FA & Password Recovery Fields
    security_question VARCHAR(255) DEFAULT 'What is your nodal procurement district?',
    security_answer_hash VARCHAR(128),      -- SHA-256 (normalized_answer + security_salt)
    security_answer_salt VARCHAR(64),
    
    -- Account Lifecycle & Audit
    is_active BOOLEAN DEFAULT TRUE,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP NULL,
    last_login_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (role) REFERENCES roles(role_id)
);

CREATE INDEX IF NOT EXISTS idx_admin_username ON admin_credentials(username);
CREATE INDEX IF NOT EXISTS idx_admin_email ON admin_credentials(email);
CREATE INDEX IF NOT EXISTS idx_admin_role ON admin_credentials(role);

-- ---------------------------------------------------------------------
-- 3. USER (FARMER) CREDENTIALS & PROFILE TABLE
-- Stores registered farmer login credentials, Aadhaar/Land refs, and details
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_credentials (
    user_id VARCHAR(64) PRIMARY KEY,
    phone VARCHAR(15) UNIQUE NOT NULL,       -- Primary login identifier
    username VARCHAR(64) UNIQUE NULL,        -- Optional custom username
    name VARCHAR(128) NOT NULL,
    email VARCHAR(128) NULL,
    village VARCHAR(128) NOT NULL,
    district VARCHAR(128) NULL,
    state VARCHAR(128) NULL,
    farmer_id_ref VARCHAR(16) NOT NULL,      -- Last 4 digits or full Aadhaar/Land Record ID
    primary_crop VARCHAR(64) NOT NULL,
    expected_qty_quintals DECIMAL(10, 2) DEFAULT 0.00,
    role VARCHAR(32) NOT NULL DEFAULT 'FARMER_USER',
    
    -- Security & Hash Fields
    password_hash VARCHAR(128) NOT NULL,    -- SHA-256 (password_or_pin + salt)
    salt VARCHAR(64) NOT NULL,             -- 16-byte Cryptographic Random Salt (Hex)
    
    -- Account Lifecycle
    is_active BOOLEAN DEFAULT TRUE,
    failed_login_attempts INT DEFAULT 0,
    last_login_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (role) REFERENCES roles(role_id)
);

CREATE INDEX IF NOT EXISTS idx_user_phone ON user_credentials(phone);
CREATE INDEX IF NOT EXISTS idx_user_farmer_ref ON user_credentials(farmer_id_ref);

-- ---------------------------------------------------------------------
-- 4. AUTHENTICATION SESSIONS & TOKENS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_sessions (
    session_id VARCHAR(128) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    username VARCHAR(64) NOT NULL,
    role VARCHAR(32) NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_revoked BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_session_user ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_session_expires ON auth_sessions(expires_at);

-- ---------------------------------------------------------------------
-- 5. AUTHENTICATION & SECURITY AUDIT LOGS TABLE
-- Immutable log of all login, logout, password change, and reset events
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_audit_logs (
    log_id VARCHAR(64) PRIMARY KEY,
    event_type VARCHAR(64) NOT NULL,        -- 'LOGIN_SUCCESS', 'LOGIN_FAILED', 'PASSWORD_CHANGE', 'PASSWORD_RESET', 'REGISTER', 'LOGOUT'
    user_identifier VARCHAR(128) NOT NULL,  -- username, phone or email
    user_id VARCHAR(64) NULL,
    role VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL,            -- 'SUCCESS', 'FAILED', 'BLOCKED'
    ip_address VARCHAR(45) DEFAULT '127.0.0.1',
    details TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON auth_audit_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_user ON auth_audit_logs(user_identifier);
CREATE INDEX IF NOT EXISTS idx_audit_event ON auth_audit_logs(event_type);

-- ---------------------------------------------------------------------
-- 6. PROCUREMENT CENTRES TABLE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS procurement_centres (
    centre_id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    location VARCHAR(255) NOT NULL,
    capacity_per_hour INT NOT NULL DEFAULT 12,
    open_hour INT NOT NULL DEFAULT 8,
    close_hour INT NOT NULL DEFAULT 18,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 7. BOOKINGS & TOKEN QUEUE TABLE
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bookings (
    booking_id VARCHAR(64) PRIMARY KEY,
    farmer_id VARCHAR(64) NOT NULL,
    centre_id VARCHAR(64) NOT NULL,
    booking_date DATE NOT NULL,
    time_slot VARCHAR(10) NOT NULL,
    token_number INT NOT NULL,
    quantity_quintals DECIMAL(10, 2) NOT NULL,
    crop VARCHAR(64),
    status VARCHAR(32) NOT NULL DEFAULT 'booked', -- 'booked', 'serving', 'procured', 'paid', 'cancelled'
    
    -- Procurement Result Fields
    procured_qty DECIMAL(10, 2) NULL,
    msp_rate DECIMAL(10, 2) NULL,
    total_amount DECIMAL(12, 2) NULL,
    payment_status VARCHAR(32) DEFAULT 'pending', -- 'pending', 'processed', 'paid'
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (farmer_id) REFERENCES user_credentials(user_id),
    FOREIGN KEY (centre_id) REFERENCES procurement_centres(centre_id)
);

CREATE INDEX IF NOT EXISTS idx_booking_centre_date ON bookings(centre_id, booking_date);
CREATE INDEX IF NOT EXISTS idx_booking_farmer ON bookings(farmer_id);
CREATE INDEX IF NOT EXISTS idx_booking_token ON bookings(centre_id, booking_date, token_number);

-- ---------------------------------------------------------------------
-- 8. SMS & APP NOTIFICATION LOGS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sms_notifications (
    notification_id VARCHAR(64) PRIMARY KEY,
    farmer_id VARCHAR(64) NOT NULL,
    phone VARCHAR(15) NOT NULL,
    message TEXT NOT NULL,
    delivery_status VARCHAR(32) DEFAULT 'DELIVERED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (farmer_id) REFERENCES user_credentials(user_id)
);
