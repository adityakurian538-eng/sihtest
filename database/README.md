# KrishiQueue Database & Authentication System

**SIH Problem Statement 26032** — Department of Consumer Affairs (DoCA), Ministry of Consumer Affairs, Food & Public Distribution.

This directory contains the relational SQL schemas, seed scripts, and documentation for storing **User (Farmer)** and **Admin (Nodal Officer / Operator)** login credentials securely.

---

## 1. Security & Credential Storage Architecture

### Password Hashing Specification
1. **Salt Generation**: Every account (User and Admin) receives a unique, cryptographically secure 16-byte random hexadecimal salt during registration or credential creation.
2. **Hash Function**: Passwords are never stored in plaintext. The system computes:
   $$\text{password\_hash} = \text{SHA256}(\text{password} + \text{salt})$$
3. **Password Verification**:
   When a user or admin logs in:
   1. Fetch user by phone/username/email.
   2. Retrieve the stored `salt`.
   3. Compute $\text{SHA256}(\text{input\_password} + \text{salt})$.
   4. Compare computed hash with stored `password_hash` in constant time.

### Security Audit Logging
Every authentication-related event is recorded in the `auth_audit_logs` table:
- `LOGIN_SUCCESS` / `LOGIN_FAILED`
- `PASSWORD_CHANGE`
- `PASSWORD_RESET` (OTP or Security Question)
- `USER_REGISTER`
- `LOGOUT`

---

## 2. Table Schemas

| Table Name | Description | Key Fields |
| :--- | :--- | :--- |
| `roles` | RBAC Role definitions | `role_id`, `role_name`, `description` |
| `admin_credentials` | Nodal officers & staff logins | `username`, `email`, `password_hash`, `salt`, `security_question`, `security_answer_hash` |
| `user_credentials` | Farmer login credentials & profile | `phone`, `username`, `password_hash`, `salt`, `farmer_id_ref`, `village`, `crop` |
| `auth_sessions` | Active login sessions & tokens | `session_id`, `user_id`, `role`, `expires_at` |
| `auth_audit_logs` | Security & compliance audit trail | `event_type`, `user_identifier`, `status`, `ip_address`, `timestamp` |
| `procurement_centres` | Mandi procurement locations | `centre_id`, `name`, `location`, `capacity_per_hour` |
| `bookings` | Slot booking & token queue | `farmer_id`, `centre_id`, `token_number`, `quantity_quintals`, `status` |
| `sms_notifications` | Simulated SMS / app alerts | `farmer_id`, `phone`, `message`, `delivery_status` |

---

## 3. Pre-Seeded Default Accounts

| Role | Username / Identifier | Default Password | Email / Phone |
| :--- | :--- | :--- | :--- |
| **Super Admin** | `admin` | `admin123` | `admin@krishiqueue.gov.in` |
| **Farmer User** | `9876543210` (or `ramesh`) | `farmer123` | Phone: `9876543210` |

---

## 4. Setup in Other Database Engines

### SQLite
```powershell
sqlite3 krishiqueue.db < database\schema.sql
sqlite3 krishiqueue.db < database\seed.sql
```

### PostgreSQL
```bash
psql -U postgres -d krishiqueue -f database/schema.sql
psql -U postgres -d krishiqueue -f database/seed.sql
```

### MySQL / MariaDB
```bash
mysql -u root -p krishiqueue < database/schema.sql
mysql -u root -p krishiqueue < database/seed.sql
```

---

## 5. REST API Endpoints

The integrated PowerShell server (`serve.ps1`) exposes the following endpoints:

- `POST /api/auth/user/register` — Register a new farmer with phone & salted password
- `POST /api/auth/user/login` — Login as farmer (phone + password)
- `POST /api/auth/admin/login` — Login as admin / operator
- `POST /api/auth/admin/change-password` — Change password for admin
- `POST /api/auth/admin/send-otp` — Request 2FA password reset OTP
- `POST /api/auth/admin/reset-password` — Verify OTP or security question & set new password
- `GET /api/admin/users` — Retrieve list of stored user & admin accounts
- `GET /api/admin/audit-logs` — Retrieve security audit trail
- `GET /api/data` — Retrieve synced centres, bookings, and queue state
- `POST /api/bookings` — Create a new procurement booking & token
- `POST /api/queue/call-next` — Advance queue to next token
- `POST /api/procurement/record` — Record weight and MSP rate
- `POST /api/procurement/pay` — Mark disbursement completed
