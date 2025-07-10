$keyboardName = "Your External Keyboard Name Here"
function Enable-Remap {
    Stop-Process -Name PowerToys -Force -ErrorAction SilentlyContinue
    Start-Process "$env:ProgramFiles\\PowerToys\\PowerToys.exe"
}
function Disable-Remap {
    Stop-Process -Name PowerToys -Force -ErrorAction SilentlyContinue
}
Register-WmiEvent -Class Win32_DeviceChangeEvent -Action {
    $devices = Get-PnpDevice -Class Keyboard | Where-Object { $_.Status -eq "OK" }
    $found = $devices | Where-Object { $_.FriendlyName -like "*$using:keyboardName*" }
    if ($found) { Enable-Remap } else { Disable-Remap }
}
Write-Host "🕵️‍♂️ Watching for keyboard: $keyboardName"
while ($true) { Start-Sleep 5 }
