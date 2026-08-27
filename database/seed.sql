-- =====================================================================
-- KrishiQueue Initial Seed Data
-- Department of Consumer Affairs (DoCA) Procurement Platform
-- =====================================================================

-- 1. Insert Procurement Centres
INSERT INTO procurement_centres (centre_id, name, location, capacity_per_hour, open_hour, close_hour)
VALUES 
('C1', 'Ganjbasoda Procurement Centre', 'Vidisha, Madhya Pradesh', 12, 8, 18),
('C2', 'Karnal Mandi Yard 2', 'Karnal, Haryana', 16, 7, 19)
ON CONFLICT (centre_id) DO NOTHING;

-- 2. Insert Super Admin Credentials
-- Default Admin:
-- Username: admin | Email: admin@krishiqueue.gov.in | Password: admin123
-- Security Question Answer: Vidisha
INSERT INTO admin_credentials (
    admin_id, username, email, phone, name, designation, assigned_centre_id, role,
    password_hash, salt, security_question, security_answer_hash, security_answer_salt, is_active
) VALUES (
    'ADM_001',
    'admin',
    'admin@krishiqueue.gov.in',
    '9876543210',
    'Shri R. K. Sharma (Nodal Officer)',
    'Chief Procurement Officer',
    'C1',
    'SUPER_ADMIN',
    '85115167dd1940dd1001fd3157142f34173a6beb1d9f797fea521217e269a47b', -- SHA-256('admin123' + salt)
    '9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c',
    'What is your nodal procurement district?',
    'e9174de21bf606b5377db6dad33ce909bd045b0c7c218ed92923b1ea8ba2978c', -- SHA-256('vidisha' + salt)
    '7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d',
    TRUE
) ON CONFLICT (username) DO NOTHING;

-- 3. Insert Demo Farmer / User Credentials
-- Demo Farmer:
-- Phone: 9876543210 | Username: ramesh | Password: farmer123
INSERT INTO user_credentials (
    user_id, phone, username, name, email, village, district, state,
    farmer_id_ref, primary_crop, expected_qty_quintals, role,
    password_hash, salt, is_active
) VALUES (
    'USR_F001',
    '9876543210',
    'ramesh',
    'Ramesh Yadav',
    'ramesh.farmer@example.com',
    'Bilaspur',
    'Vidisha',
    'Madhya Pradesh',
    '4821',
    'Wheat',
    40.00,
    'FARMER_USER',
    'e864b73b4adfe72bdad34feeb06cc56f88239d7e5640945ba06f67cb10ad5e61', -- SHA-256('farmer123' + salt)
    '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d',
    TRUE
) ON CONFLICT (phone) DO NOTHING;

-- 4. Initial Audit Log
INSERT INTO auth_audit_logs (
    log_id, event_type, user_identifier, user_id, role, status, ip_address, details
) VALUES (
    'LOG_INIT_001',
    'SYSTEM_INITIALIZED',
    'SYSTEM',
    'ADM_001',
    'SUPER_ADMIN',
    'SUCCESS',
    '127.0.0.1',
    'KrishiQueue authentication database initialized with default security seeds'
);
