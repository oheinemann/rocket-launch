<#
.SYNOPSIS
    rocket-launch — Windows host entry point.

.DESCRIPTION
    Single-command Windows bootstrap. Solves the old "run it twice" problem:
    if WSL2 is not ready yet, it installs WSL2 + a distro, registers a RunOnce
    task so this script auto-resumes after the required reboot, and reboots.
    After the reboot it provisions Windows host apps via winget and then hands
    over to the POSIX install.sh inside WSL.

.PARAMETER Config
    Git URL of your private config repo. Defaults to the public example repo.

.EXAMPLE
    # Run from an elevated PowerShell:
    iex "& { $(irm https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.ps1) } -Config https://github.com/you/rocket-launch-config.git"
#>
[CmdletBinding()]
param(
    [string]$Config = "https://github.com/oheinemann/rocket-launch-config.git",
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$RepoRaw = "https://raw.githubusercontent.com/oheinemann/rocket-launch/main"

function Write-Step { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "!!! $m" -ForegroundColor Yellow }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script from an elevated (Administrator) PowerShell."
    }
}

function Test-WslReady {
    # WSL2 ready == wsl.exe present AND at least one distro installed & runnable.
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    try {
        $null = wsl.exe -l -q 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $distros = (wsl.exe -l -q) -split "`r?`n" | Where-Object { $_ -and $_.Trim() }
        return ($distros.Count -gt 0)
    } catch { return $false }
}

function Register-Resume {
    # RunOnce fires for the current user at next interactive logon, then is
    # removed automatically — so the script resumes exactly once after reboot.
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " +
           "`"iex '& { `$(irm $RepoRaw/install.ps1) } -Config $Config -Distro $Distro'`""
    New-ItemProperty -Path $key -Name "rocket-launch-resume" -Value $cmd -PropertyType String -Force | Out-Null
    Write-Ok "Registered post-reboot resume (RunOnce)."
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
Assert-Admin
Write-Step "rocket-launch (Windows host) — config: $Config"

if (-not (Test-WslReady)) {
    Write-Step "WSL2 not ready — installing WSL2 + $Distro"
    # `wsl --install` enables the features, installs the kernel and the distro
    # in one step on current Windows 10/11 builds.
    wsl.exe --install -d $Distro
    Register-Resume
    Write-Warn "A reboot is required. The setup will resume automatically after login."
    Write-Step "Rebooting in 10 seconds — press Ctrl+C to cancel."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    return
}

Write-Ok "WSL2 is ready."

# --- Phase 0b: provision Windows host GUI apps via winget ---
Write-Step "Provisioning Windows host apps (winget)"
$hostScript = "$env:TEMP\rocket-windows-host.ps1"
Invoke-RestMethod "$RepoRaw/bootstrap/windows-host.ps1" -OutFile $hostScript
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hostScript -Config $Config

# --- Hand over to the POSIX installer inside WSL ---
Write-Step "Handing over to install.sh inside WSL ($Distro)"
$wslCmd = "curl -fsSL $RepoRaw/install.sh | bash -s -- --config '$Config'"
wsl.exe -d $Distro -- bash -lc "$wslCmd"

Write-Step "rocket-launch finished. Host + WSL provisioned."
