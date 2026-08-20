#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy API + upsert platform owner on Cali.
  Password only via env PLATFORM_ADMIN_PASSWORD (never committed).

.EXAMPLE
  $env:PLATFORM_ADMIN_PASSWORD='…'
  powershell -ExecutionPolicy Bypass -File tools\deploy_cali_owner.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName = '135.106.186.90',
  [string]$User = 'root',
  [string]$Branch = 'ui-studio-polish',
  [string]$KeyPath = ''
)

$ErrorActionPreference = 'Stop'
if (-not $KeyPath) { $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519' }
$sshCandidates = @(
  'C:\Program Files\Git\usr\bin\ssh.exe',
  'C:\Windows\System32\OpenSSH\ssh.exe'
)
$ssh = $sshCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ssh) { throw 'ssh.exe not found' }
if (-not (Test-Path $KeyPath)) { throw "SSH key missing: $KeyPath" }

$email = if ($env:PLATFORM_ADMIN_EMAIL) { $env:PLATFORM_ADMIN_EMAIL } else { 'igorkarikh36@gmail.com' }
$name  = if ($env:PLATFORM_ADMIN_NAME)  { $env:PLATFORM_ADMIN_NAME }  else { 'Игорь Карих' }
$phone = if ($env:PLATFORM_ADMIN_PHONE) { $env:PLATFORM_ADMIN_PHONE } else { '79803447473' }
$pass  = $env:PLATFORM_ADMIN_PASSWORD
if (-not $pass) { throw 'Set env PLATFORM_ADMIN_PASSWORD before running.' }

function Invoke-Remote([string]$Cmd) {
  Write-Host "==> remote" -ForegroundColor Cyan
  & $ssh -i $KeyPath -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${User}@${HostName}" $Cmd
  if ($LASTEXITCODE -ne 0) { throw "remote failed ($LASTEXITCODE)" }
}

Write-Host "==> pull $Branch" -ForegroundColor Cyan
Invoke-Remote "cd /opt/det-app-src && git fetch origin && git checkout $Branch && git pull origin $Branch"
Invoke-Remote "cp -r /opt/det-app-src/server/. /opt/det-app/"

# Update .env keys via python on remote (password not echoed in our logs beyond ssh)
$py = @'
import os, pathlib, re
p = pathlib.Path("/opt/det-app/.env")
text = p.read_text(encoding="utf-8") if p.exists() else ""
repl = {
  "PLATFORM_ADMIN_EMAIL": os.environ["E"],
  "PLATFORM_ADMIN_NAME": os.environ["N"],
  "PLATFORM_ADMIN_PHONE": os.environ["P"],
  "PLATFORM_ADMIN_PASSWORD": os.environ["W"],
  "OWNER_DESTRUCTIVE_PIN": "9294",
}
for k,v in repl.items():
  line = f"{k}={v}"
  if re.search(rf"^{re.escape(k)}=.*$", text, flags=re.M):
    text = re.sub(rf"^{re.escape(k)}=.*$", line, text, count=1, flags=re.M)
  else:
    text = (text.rstrip() + "\n" + line + "\n") if text else (line + "\n")
p.write_text(text, encoding="utf-8")
print("env_ok")
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($py))
# Escape single quotes for remote bash
function Esc([string]$s) { return $s.Replace("'", "'\''") }
$e = Esc $email; $n = Esc $name; $ph = Esc $phone; $w = Esc $pass
Invoke-Remote "E='$e' N='$n' P='$ph' W='$w' python3 -c `"import base64,os; exec(base64.b64decode('$b64').decode())`""

Write-Host "==> rebuild api" -ForegroundColor Cyan
Invoke-Remote "cd /opt/det-app && docker compose up -d --build"
Start-Sleep -Seconds 12
Write-Host "==> health" -ForegroundColor Cyan
curl.exe -s "http://api.det-app.ru/health"
Write-Host ""

Write-Host "==> upsert platform owner" -ForegroundColor Cyan
# Copy upsert script into container via stdin is hard; run inline python with env from compose .env
Invoke-Remote @"
cd /opt/det-app && docker compose exec -T api python -c "import os; from sqlalchemy import select; from app.db import SessionLocal; from app.models import User; from app.security import hash_password; from app.phone_util import phone_digits10; db=SessionLocal(); email=os.environ.get('PLATFORM_ADMIN_EMAIL','').lower().strip(); password=os.environ.get('PLATFORM_ADMIN_PASSWORD',''); name=os.environ.get('PLATFORM_ADMIN_NAME','Platform Owner'); phone=phone_digits10(os.environ.get('PLATFORM_ADMIN_PHONE') or '') or None; assert email and password, 'missing env'; u=db.scalar(select(User).where(User.email==email));
u=u or (db.scalar(select(User).where(User.phone==phone)) if phone else None);
exec('if u is None:\n u=User(email=email, phone=phone, password_hash=hash_password(password), full_name=name, is_platform_admin=True, is_active=True, company_id=None); db.add(u); a=\"created\"\nelse:\n u.email=email; u.full_name=name; u.is_platform_admin=True; u.is_active=True; u.company_id=None; u.password_hash=hash_password(password)\n if phone: u.phone=phone\n a=\"updated\"\ndb.commit(); print(a, u.id, u.email)')"
"@

Write-Host "DONE" -ForegroundColor Green
