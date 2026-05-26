Add-Type -AssemblyName System.Windows.Forms

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = "Select folder to save system inventory CSV files"
$folderDialog.ShowNewFolderButton = $true

if ($folderDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Export cancelled by user." -ForegroundColor Yellow
    return
}
Write-Host "`nPlease Select a folder to save the CSV files." -ForegroundColor Green
$runPath = $folderDialog.SelectedPath

Write-Host "`nPlease wait, gathering system information..." -ForegroundColor Green

$computerSystem = Get-CimInstance Win32_ComputerSystem
$os             = Get-CimInstance Win32_OperatingSystem
$cpu            = Get-CimInstance Win32_Processor | Select-Object -First 1
$chassis = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes

# User (interactive first, fallback to last logon)
$user = (Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue |
         Select-Object -First 1).UserName

# Windows Feature Version (22H2 / 23H2)
$winVer = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" `
    -ErrorAction SilentlyContinue

$osVersion = if ($winVer.DisplayVersion) {
    $winVer.DisplayVersion
} else {
    $winVer.ReleaseId
}

# RAM in GB
$ramGB = [Math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)

# Antivirus
$antivirus = Get-CimInstance `
    -Namespace root/SecurityCenter2 `
    -ClassName AntiVirusProduct `
    -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty displayName -First 1

# BitLocker
$bitlocker = Get-BitLockerVolume `
    -MountPoint $os.SystemDrive `
    -ErrorAction SilentlyContinue

$encrypted = if ($bitlocker.VolumeStatus -eq 'FullyEncrypted') { "Yes" } else { "No" }

$recoveryKey = ($bitlocker.KeyProtector |
    Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
).RecoveryPassword


# Determine chassis type (Laptop vs Desktop)
if ($chassis | Where-Object { $_ -in 8,9,10,14 }) {
   $chassisType = "Laptop"
    # Laptop chassis codes:
    # 8  Notebook, 9  Laptop, 10 Portable, 14 Sub‑Notebook
} else {
    $chassisType = "Desktop"
    # Desktop chassis codes:
    # 3 Desktop, 4 Low Profile Desktop, 5 Pizza Box, 6 Mini Tower, 7 Tower
}


# Build output object
$info = [PSCustomObject]@{
    "Device Name"  = $env:COMPUTERNAME
    "User"         = $user
    "Make"         = $computerSystem.Manufacturer
    "Model"        = $computerSystem.Model
    "Processor"    = $cpu.Name
    "RAM (GB)"     = $ramGB
    "OS"           = $os.Caption
    "OS Version"   = $osVersion
    "Antivirus"    = $antivirus
    "Type"         = $chassisType
    "Encrypted"    = $encrypted
    "Recovery Key" = $recoveryKey
}

# System Filename with timestamp and save variables
$timestamp  = Get-Date -Format ddMMyy-HHmmss
$singlePath = Join-Path $runPath "$env:COMPUTERNAME-$timestamp.csv"
$masterPath = Join-Path $runPath "AllSystems.csv"

Write-Host "`nExporting system information to CSV files..." -ForegroundColor Green
# 1) Export per-machine file (overwrites each time)
$info | Export-Csv $singlePath -NoTypeInformation

# 2) Append to master file (create header if it doesn't exist)
if (Test-Path $masterPath) {
    $info | Export-Csv $masterPath -NoTypeInformation -Append
} else {
    $info | Export-Csv $masterPath -NoTypeInformation
}

Write-Host "`nExported: "
Write-Host $singlePath -ForegroundColor Cyan

Write-Host "`nUpdated All Systems CSV: "
Write-Host $masterPath -ForegroundColor Cyan
Write-Host "`nDone!" -ForegroundColor Green

# Open the folder automatically
Invoke-Item $runPath
