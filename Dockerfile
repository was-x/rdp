# Windows RDP Server with Docker + Ngrok - Complete Setup Script
# Save as setup-rdp.ps1 and run as Administrator

param(
    [string]$Username = "Administrator",
    [string]$Password = "Darkboy336",
    [string]$NgrokAuthToken = "2qiXwqE9lFYqe9NvvpTGZTj7F5h_2Wquuw8qRBApdFBQox56J"
)

Write-Host "=== Windows RDP Server Setup ===" -ForegroundColor Green
Write-Host "Username: $Username" -ForegroundColor Yellow
Write-Host "Password: $Password" -ForegroundColor Yellow

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges. Please run as Administrator." -ForegroundColor Red
    exit 1
}

# Function to check if command exists
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

# Check and install Docker Desktop
if (-NOT (Test-CommandExists "docker")) {
    Write-Host "Docker not found. Installing Docker Desktop..." -ForegroundColor Yellow
    
    # Download Docker Desktop
    $dockerInstaller = "DockerDesktopInstaller.exe"
    $dockerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
    
    Invoke-WebRequest -Uri $dockerUrl -OutFile $dockerInstaller
    
    Write-Host "Installing Docker Desktop... This may take a few minutes." -ForegroundColor Yellow
    Start-Process -FilePath $dockerInstaller -ArgumentList "install --quiet" -Wait
    
    # Wait for Docker to start
    Write-Host "Waiting for Docker to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Remove installer
    Remove-Item $dockerInstaller -Force
} else {
    Write-Host "Docker is already installed." -ForegroundColor Green
}

# Download and install ngrok
if (-NOT (Test-CommandExists "ngrok")) {
    Write-Host "Installing ngrok..." -ForegroundColor Yellow
    
    # Download ngrok
    $ngrokZip = "ngrok.zip"
    $ngrokUrl = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip"
    
    Invoke-WebRequest -Uri $ngrokUrl -OutFile $ngrokZip
    
    # Extract ngrok
    Expand-Archive -Path $ngrokZip -DestinationPath "C:\Windows\System32\" -Force
    Remove-Item $ngrokZip -Force
    
    Write-Host "Ngrok installed successfully." -ForegroundColor Green
} else {
    Write-Host "Ngrok is already installed." -ForegroundColor Green
}

# Configure ngrok with auth token
if ($NgrokAuthToken -ne "YOUR_NGROK_AUTH_TOKEN_HERE") {
    Write-Host "Configuring ngrok with your auth token..." -ForegroundColor Yellow
    & ngrok config add-authtoken $NgrokAuthToken
} else {
    Write-Host "Please update the NgrokAuthToken in the script with your actual ngrok auth token." -ForegroundColor Red
    Write-Host "You can get it from: https://dashboard.ngrok.com/get-started/your-authtoken" -ForegroundColor Yellow
}

# Create Dockerfile for Windows RDP
Write-Host "Creating Docker configuration..." -ForegroundColor Yellow

$dockerfileContent = @"
# Windows RDP Server
FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Install Chocolatey
RUN @powershell -NoProfile -ExecutionPolicy Bypass -Command \
    "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))" && \
    SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

# Install RDP and tools
RUN powershell -Command \
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 ; \
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" ; \
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 ; \
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "SecurityLayer" -Value 0

# Create user with password
RUN net user $Username $Password /add /y && \
    net localgroup administrators $Username /add

# Set never expire password
RUN wmic useraccount where "name='$Username'" set PasswordExpires=False

EXPOSE 3389

CMD ["cmd", "/k", "echo RDP Server is running... && timeout /t 999999"]
"@

$dockerfileContent | Out-File -FilePath "Dockerfile" -Encoding ASCII

# Build Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t windows-rdp-server .

# Stop any existing container
docker stop windows-rdp-container 2>$null
docker rm windows-rdp-container 2>$null

# Run Docker container
Write-Host "Starting RDP server container..." -ForegroundColor Yellow
docker run -d --name windows-rdp-container -p 3389:3389 windows-rdp-server

Write-Host "Waiting for container to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Start ngrok tunnel
Write-Host "Starting ngrok tunnel..." -ForegroundColor Green
Start-Process -FilePath "ngrok" -ArgumentList "tcp 3389" -WindowStyle Hidden

# Wait a moment for ngrok to start
Start-Sleep -Seconds 5

# Get ngrok public URL
Write-Host "Getting ngrok public URL..." -ForegroundColor Yellow
try {
    $ngrokStatus = Invoke-RestMethod -Uri "http://localhost:4040/api/tunnels" -ErrorAction Stop
    $publicUrl = $ngrokStatus.tunnels[0].public_url
    $publicUrl = $publicUrl -replace "tcp://", ""
    $hostname, $port = $publicUrl -split ":"
    
    Write-Host "`n=== RDP SERVER READY ===" -ForegroundColor Green
    Write-Host "Public Host: $hostname" -ForegroundColor Cyan
    Write-Host "Public Port: $port" -ForegroundColor Cyan
    Write-Host "Username: $Username" -ForegroundColor Cyan
    Write-Host "Password: $Password" -ForegroundColor Cyan
    Write-Host "`nRDP Connection String:" -ForegroundColor Yellow
    Write-Host "mstsc /v:$hostname`:$port" -ForegroundColor White
    
    # Create connection file
    $rdpContent = @"
screen mode id:i:2
use multimon:i:0
desktopwidth:i:1024
desktopheight:i:768
session bpp:i:32
winposstr:s:0,1,793,95,1625,768
compression:i:1
keyboardhook:i:2
audiocapturemode:i:0
videoplaybackmode:i:1
connection type:i:7
networkautodetect:i:1
bandwidthautodetect:i:1
displayconnectionbar:i:1
enableworkspacereconnect:i:0
disable wallpaper:i:0
allow font smoothing:i:0
allow desktop composition:i:0
disable full window drag:i:1
disable menu anims:i:1
disable themes:i:0
disable cursor setting:i:0
bitmapcachepersistenable:i:1
full address:s:$hostname`:$port
audiomode:i:0
redirectprinters:i:1
redirectcomports:i:0
redirectsmartcards:i:1
redirectwebauthn:i:1
redirectclipboard:i:1
redirectposdevices:i:0
autoreconnection enabled:i:1
authentication level:i:2
prompt for credentials:i:0
negotiate security layer:i:0
remoteapplicationmode:i:0
alternate shell:s:
shell working directory:s:
gatewayhostname:s:
gatewayusagemethod:i:4
gatewaycredentialssource:i:4
gatewayprofileusagemethod:i:0
promptcredentialonce:i:0
use redirection server name:i:0
rdgiskdcproxy:i:0
kdcproxyname:s:
username:s:$Username
"@

    $rdpContent | Out-File -FilePath "rdp-connection.rdp" -Encoding ASCII
    Write-Host "`nRDP connection file created: rdp-connection.rdp" -ForegroundColor Green
    
} catch {
    Write-Host "Could not get ngrok URL automatically. Please check ngrok dashboard." -ForegroundColor Red
    Write-Host "Run manually: ngrok tcp 3389" -ForegroundColor Yellow
}

Write-Host "`nSetup completed! Use the credentials above to connect via RDP." -ForegroundColor Green
Write-Host "To stop the server: docker stop windows-rdp-container" -ForegroundColor Yellow
Write-Host "To view ngrok dashboard: http://localhost:4040" -ForegroundColor Yellow
