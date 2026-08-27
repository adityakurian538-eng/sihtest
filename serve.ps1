# =====================================================================
# KrishiQueue Backend Server & Database Engine
# SIH Problem Statement 26032 - DoCA Procurement Platform
# Serves Web UI & REST API for User/Admin Authentication & Queue Engine
# =====================================================================

$port = 5500
$workspace = "c:\SIH"
$dataDir = Join-Path $workspace "data"
$dbFile = Join-Path $dataDir "krishiqueue_database.json"

if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

# ---------------------------------------------------------------------
# Cryptographic Password Hashing & Security Utilities
# ---------------------------------------------------------------------
function New-CryptoSalt([int]$byteCount = 16) {
    $bytes = New-Object byte[] $byteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace("-", "").ToLower()
}

function Get-CryptoHash([string]$plainText, [string]$salt) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plainText + $salt)
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLower()
}

function Verify-CryptoHash([string]$plainText, [string]$storedHash, [string]$salt) {
    if ([string]::IsNullOrEmpty($plainText) -or [string]::IsNullOrEmpty($storedHash) -or [string]::IsNullOrEmpty($salt)) {
        return $false
    }
    return ((Get-CryptoHash $plainText $salt) -eq $storedHash)
}

# Convert PSCustomObject to a real Hashtable (needed after ConvertFrom-Json)
function ConvertTo-Hashtable($psObj) {
    $ht = @{}
    if ($psObj) {
        $psObj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    }
    return $ht
}

# ---------------------------------------------------------------------
# Database Persistence Layer
# ---------------------------------------------------------------------
function Initialize-Database {
    if (-not (Test-Path $dbFile)) {
        $adminSalt = New-CryptoSalt
        $adminPassHash = Get-CryptoHash "admin123" $adminSalt
        $adminSecSalt = New-CryptoSalt
        $adminSecAnswerHash = Get-CryptoHash "vidisha" $adminSecSalt
        $farmerSalt = New-CryptoSalt
        $farmerPassHash = Get-CryptoHash "farmer123" $farmerSalt

        $initialDB = @{
            admins = @(
                @{
                    id = "ADM_001"; username = "admin"; email = "admin@krishiqueue.gov.in"
                    phone = "9876543210"; name = "Shri R. K. Sharma (Nodal Officer)"
                    designation = "Chief Procurement Officer"; role = "SUPER_ADMIN"
                    password_hash = $adminPassHash; salt = $adminSalt
                    security_question = "What is your nodal procurement district?"
                    security_answer_hash = $adminSecAnswerHash; security_answer_salt = $adminSecSalt
                    created_at = [DateTime]::UtcNow.ToString("o"); last_login_at = $null; is_active = $true
                }
            )
            users = @(
                @{
                    id = "USR_F001"; phone = "9876543210"; username = "ramesh"; name = "Ramesh Yadav"
                    village = "Bilaspur"; district = "Vidisha"; state = "Madhya Pradesh"
                    farmer_id_ref = "4821"; crop = "Wheat"; qty = 40; role = "FARMER_USER"
                    password_hash = $farmerPassHash; salt = $farmerSalt
                    created_at = [DateTime]::UtcNow.ToString("o"); last_login_at = $null; is_active = $true
                }
            )
            centres = @(
                @{ id = "C1"; name = "Ganjbasoda Procurement Centre"; location = "Vidisha, MP"; capacityPerHour = 12; openHour = 8; closeHour = 18 },
                @{ id = "C2"; name = "Karnal Mandi Yard 2"; location = "Karnal, Haryana"; capacityPerHour = 16; openHour = 7; closeHour = 19 }
            )
            bookings = @()
            notifications = @(
                @{
                    id = "NOTIF_001"; farmerId = "USR_F001"
                    message = "Welcome Ramesh! Your KrishiQueue account is active."
                    time = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                }
            )
            queueState = @{}
            tokenCounters = @{}
            audit_logs = @(
                @{
                    id = "LOG_001"; event_type = "SYSTEM_INITIALIZE"; user_identifier = "SYSTEM"
                    role = "SYSTEM"; status = "SUCCESS"; ip_address = "127.0.0.1"
                    details = "KrishiQueue database initialized with secure salted credentials."
                    timestamp = [DateTime]::UtcNow.ToString("o")
                }
            )
        }

        [System.IO.File]::WriteAllText($dbFile, (ConvertTo-Json $initialDB -Depth 10), [System.Text.Encoding]::UTF8)
        Write-Host "Initialized new database at: $dbFile" -ForegroundColor Cyan
    }
}

function Get-Database {
    Initialize-Database
    try {
        $json = [System.IO.File]::ReadAllText($dbFile, [System.Text.Encoding]::UTF8)
        return ($json | ConvertFrom-Json)
    } catch {
        Write-Host "Error reading database: $_" -ForegroundColor Red
        return $null
    }
}

function Save-Database($dbObj) {
    try {
        [System.IO.File]::WriteAllText($dbFile, (ConvertTo-Json $dbObj -Depth 10), [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "Error saving database: $_" -ForegroundColor Red
    }
}

function Add-AuditLog($db, [string]$eventType, [string]$userId, [string]$role, [string]$status, [string]$ip, [string]$details) {
    $entry = @{
        id = "LOG_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        event_type = $eventType; user_identifier = $userId; role = $role
        status = $status; ip_address = $ip; details = $details
        timestamp = [DateTime]::UtcNow.ToString("o")
    }
    $list = [System.Collections.ArrayList]@($db.audit_logs)
    $list.Insert(0, $entry)
    if ($list.Count -gt 500) { $list = $list.GetRange(0, 500) }
    $db.audit_logs = $list
}

# ---------------------------------------------------------------------
# HTTP Listener
# ---------------------------------------------------------------------
Initialize-Database

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() }
catch { Write-Host "Could not start: $_" -ForegroundColor Red; exit 1 }

Write-Host "=================================================================" -ForegroundColor Green
Write-Host " KrishiQueue Server & Database API Running on http://localhost:$port/" -ForegroundColor Green
Write-Host " Database file: $dbFile" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

$mime = @{
    ".html"=  "text/html; charset=utf-8"; ".css" = "text/css; charset=utf-8"
    ".js"  = "application/javascript; charset=utf-8"; ".json" = "application/json; charset=utf-8"
    ".png" = "image/png"; ".jpg" = "image/jpeg"; ".svg" = "image/svg+xml"; ".ico" = "image/x-icon"
}
$otpStore = @{}

function Send-JsonResponse($res, [int]$statusCode, $data) {
    try {
        $res.StatusCode = $statusCode
        $res.ContentType = "application/json; charset=utf-8"
        $res.AddHeader("Access-Control-Allow-Origin", "*")
        $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
        $json = ConvertTo-Json $data -Depth 10
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.Close()
    } catch {}
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        $localPath = [System.Uri]::UnescapeDataString($req.Url.LocalPath)
        $clientIp = $req.RemoteEndPoint.Address.ToString()
        $httpMethod = $req.HttpMethod.ToUpper()

        if ($httpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
            $res.AddHeader("Access-Control-Allow-Origin", "*")
            $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
            $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
            $res.Close()
            continue
        }

        $body = $null
        if ($req.HasEntityBody -and $req.ContentLength64 -gt 0) {
            $buffer = New-Object byte[] $req.ContentLength64
            $read = $req.InputStream.Read($buffer, 0, $buffer.Length)
            $enc = if ($req.ContentEncoding) { $req.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
            $raw = $enc.GetString($buffer, 0, $read)
            if ($raw) { try { $body = $raw | ConvertFrom-Json } catch {} }
        }

        # =====================================================================
        # REST API ROUTING
        # =====================================================================
        if ($localPath.StartsWith("/api/")) {
            $db = Get-Database

            # -----------------------------------------------------------------
            # 1. USER REGISTER
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/user/register" -and $httpMethod -eq "POST") {
                if (-not $body -or -not $body.phone -or -not $body.name) {
                    Send-JsonResponse $res 400 @{ error = "Missing required fields: phone, name, password" }
                    continue
                }
                $phone = $body.phone.Trim()
                $existing = @($db.users) | Where-Object { $_.phone -eq $phone }
                if ($existing) {
                    Add-AuditLog $db "USER_REGISTER" $phone "FARMER_USER" "FAILED" $clientIp "Phone already registered"
                    Save-Database $db
                    Send-JsonResponse $res 400 @{ error = "A farmer account with this mobile number already exists." }
                    continue
                }
                $pass = if ($body.password) { $body.password } else { "123456" }
                $salt = New-CryptoSalt
                $hash = Get-CryptoHash $pass $salt
                $newUser = @{
                    id = "USR_F" + [Guid]::NewGuid().ToString("N").Substring(0,6).ToUpper()
                    phone = $phone
                    username = if ($body.username) { $body.username.Trim() } else { $phone }
                    name = $body.name.Trim()
                    village = if ($body.village) { $body.village.Trim() } else { "-" }
                    district = if ($body.district) { $body.district.Trim() } else { "" }
                    state = if ($body.state) { $body.state.Trim() } else { "" }
                    farmer_id_ref = if ($body.farmerId) { $body.farmerId.Trim() } else { $phone.Substring([Math]::Max(0,$phone.Length-4)) }
                    crop = if ($body.crop) { $body.crop } else { "Wheat" }
                    qty = if ($body.qty) { [double]$body.qty } else { 0 }
                    role = "FARMER_USER"
                    password_hash = $hash; salt = $salt
                    created_at = [DateTime]::UtcNow.ToString("o"); last_login_at = $null; is_active = $true
                }
                $ul = [System.Collections.ArrayList]@($db.users); $ul.Add($newUser) | Out-Null; $db.users = $ul
                $nl = [System.Collections.ArrayList]@($db.notifications)
                $nl.Insert(0, @{ id="NOTIF_"+[Guid]::NewGuid().ToString("N").Substring(0,6); farmerId=$newUser.id; message="Welcome $($newUser.name)! Account active."; time=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() })
                $db.notifications = $nl
                Add-AuditLog $db "USER_REGISTER" $phone "FARMER_USER" "SUCCESS" $clientIp "Registered: $($newUser.name)"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; user=@{id=$newUser.id;name=$newUser.name;phone=$newUser.phone;village=$newUser.village;farmer_id_ref=$newUser.farmer_id_ref;crop=$newUser.crop;role=$newUser.role}; message="Farmer account registered." }
                continue
            }

            # -----------------------------------------------------------------
            # 2. USER LOGIN
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/user/login" -and $httpMethod -eq "POST") {
                if (-not $body -or -not $body.phone -or -not $body.password) {
                    Send-JsonResponse $res 400 @{ error = "Mobile number and password required." }
                    continue
                }
                $phone = $body.phone.Trim()
                $user = @($db.users) | Where-Object { $_.phone -eq $phone -or $_.username -eq $phone }
                if (-not $user) {
                    Add-AuditLog $db "USER_LOGIN" $phone "FARMER_USER" "FAILED" $clientIp "Not found"
                    Save-Database $db
                    Send-JsonResponse $res 401 @{ error = "Invalid mobile number or password." }
                    continue
                }
                if (-not (Verify-CryptoHash $body.password $user.password_hash $user.salt)) {
                    Add-AuditLog $db "USER_LOGIN" $phone "FARMER_USER" "FAILED" $clientIp "Wrong password"
                    Save-Database $db
                    Send-JsonResponse $res 401 @{ error = "Invalid mobile number or password." }
                    continue
                }
                $user | Add-Member -MemberType NoteProperty -Name last_login_at -Value ([DateTime]::UtcNow.ToString("o")) -Force
                $tok = "USR_SESS_" + [Guid]::NewGuid().ToString("N")
                Add-AuditLog $db "USER_LOGIN" $phone "FARMER_USER" "SUCCESS" $clientIp "Logged in: $($user.name)"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; token=$tok; user=@{id=$user.id;name=$user.name;phone=$user.phone;village=$user.village;farmer_id_ref=$user.farmer_id_ref;crop=$user.crop;role=$user.role;token=$tok} }
                continue
            }

            # -----------------------------------------------------------------
            # 3. ADMIN LOGIN
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/admin/login" -and $httpMethod -eq "POST") {
                if (-not $body -or -not $body.username -or -not $body.password) {
                    Send-JsonResponse $res 400 @{ error = "Username and password required." }
                    continue
                }
                $uid = $body.username.Trim().ToLower()
                $admin = @($db.admins) | Where-Object { $_.username.ToLower() -eq $uid -or $_.email.ToLower() -eq $uid }
                if (-not $admin) {
                    Add-AuditLog $db "ADMIN_LOGIN" $uid "ADMIN" "FAILED" $clientIp "Account not found"
                    Save-Database $db
                    Send-JsonResponse $res 401 @{ error = "Invalid username or password." }
                    continue
                }
                if (-not (Verify-CryptoHash $body.password $admin.password_hash $admin.salt)) {
                    Add-AuditLog $db "ADMIN_LOGIN" $uid "ADMIN" "FAILED" $clientIp "Wrong password"
                    Save-Database $db
                    Send-JsonResponse $res 401 @{ error = "Invalid username or password." }
                    continue
                }
                $admin | Add-Member -MemberType NoteProperty -Name last_login_at -Value ([DateTime]::UtcNow.ToString("o")) -Force
                $tok = "ADM_SESS_" + [Guid]::NewGuid().ToString("N")
                Add-AuditLog $db "ADMIN_LOGIN" $uid "ADMIN" "SUCCESS" $clientIp "Admin in: $($admin.name)"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; token=$tok; admin=@{id=$admin.id;username=$admin.username;email=$admin.email;name=$admin.name;designation=$admin.designation;role=$admin.role;token=$tok} }
                continue
            }

            # -----------------------------------------------------------------
            # 4. ADMIN CHANGE PASSWORD
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/admin/change-password" -and $httpMethod -eq "POST") {
                $uid = if ($body.username) { $body.username.Trim().ToLower() } else { "admin" }
                $admin = @($db.admins) | Where-Object { $_.username.ToLower() -eq $uid -or $_.email.ToLower() -eq $uid }
                if (-not $admin) { Send-JsonResponse $res 404 @{ error = "Admin not found." }; continue }
                if (-not (Verify-CryptoHash $body.currentPassword $admin.password_hash $admin.salt)) {
                    Add-AuditLog $db "PASSWORD_CHANGE" $uid "ADMIN" "FAILED" $clientIp "Wrong current password"
                    Save-Database $db
                    Send-JsonResponse $res 400 @{ error = "Incorrect current password." }
                    continue
                }
                $newPass = $body.newPassword
                if (-not $newPass -or $newPass.Length -lt 6) {
                    Send-JsonResponse $res 400 @{ error = "New password must be at least 6 characters." }
                    continue
                }
                $newSalt = New-CryptoSalt
                $admin | Add-Member -MemberType NoteProperty -Name password_hash -Value (Get-CryptoHash $newPass $newSalt) -Force
                $admin | Add-Member -MemberType NoteProperty -Name salt -Value $newSalt -Force
                $admin | Add-Member -MemberType NoteProperty -Name updated_at -Value ([DateTime]::UtcNow.ToString("o")) -Force
                Add-AuditLog $db "PASSWORD_CHANGE" $uid "ADMIN" "SUCCESS" $clientIp "Password updated"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; message="Admin password updated successfully in database." }
                continue
            }

            # -----------------------------------------------------------------
            # 5. ADMIN SEND OTP
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/admin/send-otp" -and $httpMethod -eq "POST") {
                $uid = if ($body.username) { $body.username.Trim().ToLower() } else { "" }
                $admin = @($db.admins) | Where-Object { $_.username.ToLower() -eq $uid -or $_.email.ToLower() -eq $uid }
                if (-not $admin) { Send-JsonResponse $res 404 @{ error = "Admin not found." }; continue }
                $otp = (Get-Random -Min 100000 -Max 999999).ToString()
                $otpStore[$uid] = @{ otp=$otp; ts=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
                Add-AuditLog $db "OTP_SENT" $uid "ADMIN" "SUCCESS" $clientIp "Reset OTP dispatched"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; otp=$otp; phone=$admin.phone; email=$admin.email; message="OTP sent." }
                continue
            }

            # -----------------------------------------------------------------
            # 6. ADMIN RESET PASSWORD
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/auth/admin/reset-password" -and $httpMethod -eq "POST") {
                $uid = if ($body.username) { $body.username.Trim().ToLower() } else { "" }
                $admin = @($db.admins) | Where-Object { $_.username.ToLower() -eq $uid -or $_.email.ToLower() -eq $uid }
                if (-not $admin) { Send-JsonResponse $res 404 @{ error = "Admin not found." }; continue }
                $ok = $false
                if ($body.method -eq "otp") {
                    $e = $otpStore[$uid]
                    if ($e -and $e.otp -eq $body.otp -and (([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-$e.ts) -le 300)) {
                        $ok = $true; $otpStore.Remove($uid)
                    } else { Send-JsonResponse $res 400 @{ error = "Invalid or expired OTP." }; continue }
                } elseif ($body.method -eq "security_question") {
                    $ans = if ($body.answer) { $body.answer.Trim().ToLower() } else { "" }
                    if (Verify-CryptoHash $ans $admin.security_answer_hash $admin.security_answer_salt) { $ok = $true }
                    else { Add-AuditLog $db "PASSWORD_RESET" $uid "ADMIN" "FAILED" $clientIp "Wrong security answer"; Save-Database $db; Send-JsonResponse $res 400 @{ error = "Incorrect security answer." }; continue }
                }
                if ($ok) {
                    if (-not $body.newPassword -or $body.newPassword.Length -lt 6) { Send-JsonResponse $res 400 @{ error = "New password must be at least 6 characters." }; continue }
                    $ns = New-CryptoSalt
                    $admin | Add-Member -MemberType NoteProperty -Name password_hash -Value (Get-CryptoHash $body.newPassword $ns) -Force
                    $admin | Add-Member -MemberType NoteProperty -Name salt -Value $ns -Force
                    $admin | Add-Member -MemberType NoteProperty -Name updated_at -Value ([DateTime]::UtcNow.ToString("o")) -Force
                    Add-AuditLog $db "PASSWORD_RESET" $uid "ADMIN" "SUCCESS" $clientIp "Password reset via $($body.method)"
                    Save-Database $db
                    Send-JsonResponse $res 200 @{ success=$true; message="Password reset successfully." }
                } else { Send-JsonResponse $res 400 @{ error = "Verification failed." } }
                continue
            }

            # -----------------------------------------------------------------
            # 7. ADMIN USER DIRECTORY
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/admin/users" -and $httpMethod -eq "GET") {
                $users = @($db.users) | ForEach-Object {
                    $sp = if ($_.salt) { $_.salt.Substring(0,[Math]::Min(8,$_.salt.Length)) + "..." } else { "" }
                    @{ id=$_.id; phone=$_.phone; username=$_.username; name=$_.name; village=$_.village; farmer_id_ref=$_.farmer_id_ref; crop=$_.crop; qty=$_.qty; role=$_.role; has_password=(-not [string]::IsNullOrEmpty($_.password_hash)); salt_prefix=$sp; created_at=$_.created_at; last_login_at=$_.last_login_at }
                }
                $admins = @($db.admins) | ForEach-Object {
                    $sp = if ($_.salt) { $_.salt.Substring(0,[Math]::Min(8,$_.salt.Length)) + "..." } else { "" }
                    @{ id=$_.id; username=$_.username; email=$_.email; name=$_.name; designation=$_.designation; role=$_.role; has_password=$true; salt_prefix=$sp; created_at=$_.created_at; last_login_at=$_.last_login_at }
                }
                Send-JsonResponse $res 200 @{ users=$users; admins=$admins }
                continue
            }

            # -----------------------------------------------------------------
            # 8. ADMIN AUDIT LOGS
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/admin/audit-logs" -and $httpMethod -eq "GET") {
                Send-JsonResponse $res 200 @{ audit_logs = $db.audit_logs }
                continue
            }

            # -----------------------------------------------------------------
            # 9. DATA SYNC
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/data" -and $httpMethod -eq "GET") {
                Send-JsonResponse $res 200 @{
                    centres=$db.centres; bookings=$db.bookings; notifications=$db.notifications
                    queueState=$db.queueState; tokenCounters=$db.tokenCounters
                    farmersCount=@($db.users).Count; bookingsCount=@($db.bookings).Count
                }
                continue
            }

            # -----------------------------------------------------------------
            # 10. SLOT BOOKING
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/bookings" -and $httpMethod -eq "POST") {
                if (-not $body -or -not $body.phone) { Send-JsonResponse $res 400 @{ error="Missing phone" }; continue }
                $phone = $body.phone.Trim()
                $user = @($db.users) | Where-Object { $_.phone -eq $phone }
                if (-not $user) { Send-JsonResponse $res 400 @{ error="Farmer not registered. Please register first." }; continue }

                $cid = [string]$body.centreId
                $dt = [string]$body.date
                $tm = [string]$body.time
                $qty = if ($body.qty) { [double]$body.qty } else { 0 }
                $key = "${cid}_${dt}"

                # Handle PSCustomObject tokenCounters (ConvertFrom-Json issue)
                $tc = ConvertTo-Hashtable $db.tokenCounters
                $tok = if ($tc.ContainsKey($key)) { [int]$tc[$key] + 1 } else { 1 }
                $tc[$key] = $tok
                $db.tokenCounters = $tc

                # Handle PSCustomObject queueState
                $qs = ConvertTo-Hashtable $db.queueState
                if (-not $qs.ContainsKey($key)) { $qs[$key] = 0 }
                $db.queueState = $qs

                $centre = @($db.centres) | Where-Object { $_.id -eq $cid }
                $centreName = if ($centre) { $centre.name } else { "Procurement Centre" }

                $booking = @{
                    id = "B_" + [Guid]::NewGuid().ToString("N").Substring(0,7)
                    farmerId=$user.id; centreId=$cid; date=$dt; time=$tm; token=$tok
                    qty=$qty; crop=$user.crop; status="booked"
                    procuredQty=$null; rate=$null; amount=$null; paymentStatus="pending"
                    createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                }
                $bl = [System.Collections.ArrayList]@($db.bookings); $bl.Add($booking) | Out-Null; $db.bookings = $bl

                $nl = [System.Collections.ArrayList]@($db.notifications)
                $nl.Insert(0, @{ id="NOTIF_"+[Guid]::NewGuid().ToString("N").Substring(0,6); farmerId=$user.id; message="Slot booked at $centreName on $dt. Token #$tok."; time=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() })
                $db.notifications = $nl

                Add-AuditLog $db "SLOT_BOOKED" $phone "FARMER_USER" "SUCCESS" $clientIp "Token #$tok at $centreName on $dt"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; booking=$booking }
                continue
            }

            # -----------------------------------------------------------------
            # 11. QUEUE CALL NEXT
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/queue/call-next" -and $httpMethod -eq "POST") {
                $cid = [string]$body.centreId
                $dt = [string]$body.date
                $key = "${cid}_${dt}"

                $qs = ConvertTo-Hashtable $db.queueState
                $curr = if ($qs.ContainsKey($key)) { [int]$qs[$key] } else { 0 }
                $next = $curr + 1

                $booking = @($db.bookings) | Where-Object { $_.centreId -eq $cid -and $_.date -eq $dt -and $_.token -eq $next -and $_.status -ne "cancelled" }
                if (-not $booking) { Send-JsonResponse $res 404 @{ error="No more farmers in queue." }; continue }

                $qs[$key] = $next; $db.queueState = $qs
                $booking | Add-Member -MemberType NoteProperty -Name status -Value "serving" -Force
                $centre = @($db.centres) | Where-Object { $_.id -eq $cid }
                $centreName = if ($centre) { $centre.name } else { "Centre" }

                $nl = [System.Collections.ArrayList]@($db.notifications)
                $nl.Insert(0, @{ id="NOTIF_"+[Guid]::NewGuid().ToString("N").Substring(0,6); farmerId=$booking.farmerId; message="Your turn at $centreName! Token #$($booking.token)."; time=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() })
                $db.notifications = $nl

                Add-AuditLog $db "QUEUE_CALL_NEXT" "OPERATOR" "ADMIN" "SUCCESS" $clientIp "Called Token #$next at $centreName"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; booking=$booking; nowServing=$next }
                continue
            }

            # -----------------------------------------------------------------
            # 12. RECORD PROCUREMENT
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/procurement/record" -and $httpMethod -eq "POST") {
                $bid = [string]$body.bookingId
                $booking = @($db.bookings) | Where-Object { $_.id -eq $bid }
                if (-not $booking) { Send-JsonResponse $res 404 @{ error="Booking not found." }; continue }
                $pqty = [double]$body.procuredQty; $rate = [double]$body.rate
                $booking | Add-Member -MemberType NoteProperty -Name procuredQty -Value $pqty -Force
                $booking | Add-Member -MemberType NoteProperty -Name rate -Value $rate -Force
                $booking | Add-Member -MemberType NoteProperty -Name amount -Value ([Math]::Round($pqty * $rate)) -Force
                $booking | Add-Member -MemberType NoteProperty -Name status -Value "procured" -Force
                $nl = [System.Collections.ArrayList]@($db.notifications)
                $nl.Insert(0, @{ id="NOTIF_"+[Guid]::NewGuid().ToString("N").Substring(0,6); farmerId=$booking.farmerId; message="Procurement recorded: $pqty qtl @ Rs.$rate/q. Total: Rs.$($booking.amount)."; time=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() })
                $db.notifications = $nl
                Add-AuditLog $db "PROCUREMENT_RECORD" "OPERATOR" "ADMIN" "SUCCESS" $clientIp "Recorded $pqty qtl for $bid"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; booking=$booking }
                continue
            }

            # -----------------------------------------------------------------
            # 13. MARK PAID
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/procurement/pay" -and $httpMethod -eq "POST") {
                $bid = [string]$body.bookingId
                $booking = @($db.bookings) | Where-Object { $_.id -eq $bid }
                if (-not $booking) { Send-JsonResponse $res 404 @{ error="Booking not found." }; continue }
                $booking | Add-Member -MemberType NoteProperty -Name paymentStatus -Value "paid" -Force
                $booking | Add-Member -MemberType NoteProperty -Name status -Value "paid" -Force
                $nl = [System.Collections.ArrayList]@($db.notifications)
                $nl.Insert(0, @{ id="NOTIF_"+[Guid]::NewGuid().ToString("N").Substring(0,6); farmerId=$booking.farmerId; message="Payment of Rs.$($booking.amount) credited. Thank you."; time=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() })
                $db.notifications = $nl
                Add-AuditLog $db "PAYMENT_DISBURSED" "OPERATOR" "ADMIN" "SUCCESS" $clientIp "Payment complete for $bid"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; booking=$booking }
                continue
            }

            # -----------------------------------------------------------------
            # 14. ADD CENTRE
            # -----------------------------------------------------------------
            if ($localPath -eq "/api/centres" -and $httpMethod -eq "POST") {
                $nc = @{
                    id = "C" + (@($db.centres).Count + 1)
                    name = [string]$body.name; location = [string]$body.location
                    capacityPerHour = if ($body.capacityPerHour) { [int]$body.capacityPerHour } else { 12 }
                    openHour = 8; closeHour = 18
                }
                $cl = [System.Collections.ArrayList]@($db.centres); $cl.Add($nc) | Out-Null; $db.centres = $cl
                Add-AuditLog $db "CENTRE_ADDED" "ADMIN" "ADMIN" "SUCCESS" $clientIp "Added: $($nc.name)"
                Save-Database $db
                Send-JsonResponse $res 200 @{ success=$true; centre=$nc }
                continue
            }

            Send-JsonResponse $res 404 @{ error = "Endpoint not found: $localPath" }
            continue
        }

        # =====================================================================
        # STATIC FILE SERVING
        # =====================================================================
        if ($localPath -eq "/" -or [string]::IsNullOrWhiteSpace($localPath)) { $localPath = "/index.html" }
        $filePath = Join-Path $workspace ($localPath.TrimStart('/'))
        if (-not (Test-Path $filePath -PathType Leaf)) { $filePath = Join-Path $workspace "index.html" }

        try {
            if (Test-Path $filePath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "text/html; charset=utf-8" }
                $res.ContentLength64 = $bytes.Length
                $res.StatusCode = 200
                $res.AddHeader("Access-Control-Allow-Origin", "*")
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
                $res.OutputStream.Write($err, 0, $err.Length)
            }
            $res.Close()
        } catch {}
    } catch {}
}
