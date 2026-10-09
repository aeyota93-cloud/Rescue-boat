# Задачи планировщика «Шлюпки спасения»: запуск с правами администратора без окна UAC
# (режим VPN без этих прав не работает).
#   \RescueBoat\Start      по требованию: ярлыки и обычный запуск RescueBoat.exe передают ему запуск;
#   \RescueBoat\Autostart  при входе текущего пользователя в Windows, программа свёрнута в трей.
# Вызывают установщик (install, uninstall) и сама программа (переключатель «Автозапуск»).
# Нужны права администратора, кроме status.
param(
    [ValidateSet('install', 'uninstall', 'enable-autostart', 'disable-autostart', 'status')]
    [string]$Action = 'status'
)
$ErrorActionPreference = 'Stop'
$folder = '\RescueBoat\'
$exe = Join-Path $PSScriptRoot 'RescueBoat.exe'
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

function Register-RescueBoatTask([string]$name, [string]$arguments, $trigger) {
    $action = New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $PSScriptRoot
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    # По умолчанию задача не стартует от батареи и снимается через 3 дня: обе настройки выключаем.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances Parallel
    $params = @{
        TaskPath = $folder; TaskName = $name; Action = $action
        Principal = $principal; Settings = $settings; Force = $true
    }
    if ($trigger) { $params.Trigger = $trigger }
    Register-ScheduledTask @params | Out-Null
}

function Get-RescueBoatTask([string]$name) {
    Get-ScheduledTask -TaskPath $folder -TaskName $name -ErrorAction SilentlyContinue
}

switch ($Action) {
    'install' {
        Register-RescueBoatTask 'Start' '--from-task' $null
    }
    'enable-autostart' {
        Register-RescueBoatTask 'Autostart' '--from-task --autostart' (New-ScheduledTaskTrigger -AtLogOn -User $user)
    }
    'disable-autostart' {
        if (Get-RescueBoatTask 'Autostart') {
            Unregister-ScheduledTask -TaskPath $folder -TaskName 'Autostart' -Confirm:$false
        }
    }
    'uninstall' {
        foreach ($name in 'Start', 'Autostart') {
            if (Get-RescueBoatTask $name) {
                Unregister-ScheduledTask -TaskPath $folder -TaskName $name -Confirm:$false
            }
        }
    }
    'status' {
        if (Get-RescueBoatTask 'Autostart') { 'enabled' } else { 'disabled' }
    }
}
