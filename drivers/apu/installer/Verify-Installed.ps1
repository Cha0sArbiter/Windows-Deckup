param([string]$OutputPath=(Join-Path $PSScriptRoot 'verification.json'))
$ErrorActionPreference='Stop'
$hardware='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'
$devices=@(Get-PnpDevice -Class Display -PresentOnly | Where-Object { $_.InstanceId.StartsWith($hardware+'\',[StringComparison]::OrdinalIgnoreCase) })
if ($devices.Count -ne 1) { throw 'Expected exactly one LCD Steam Deck AE GPU.' }
$values=@{}
Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName 'DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_Service' | ForEach-Object { $values[$_.KeyName]=$_.Data }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeckupIntegrity {
    [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int cls, IntPtr data, int length, out int returned);
}
'@
$buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(8)
try {
    [Runtime.InteropServices.Marshal]::WriteInt32($buffer,8); $returned=0
    if ([DeckupIntegrity]::NtQuerySystemInformation(103,$buffer,8,[ref]$returned) -ne 0) { throw 'Live Code Integrity query failed.' }
    $options=[Runtime.InteropServices.Marshal]::ReadInt32($buffer,4)
} finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
$image=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$values['DEVPKEY_Device_Service']) -Name ImagePath).ImagePath
$image=[Environment]::ExpandEnvironmentVariables($image).Trim('"')
if ($image.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) { $image=Join-Path $env:SystemRoot $image.Substring(12) }
if ($image.StartsWith('\??\')) { $image=$image.Substring(4) }
$image=[IO.Path]::GetFullPath($image)
$expectedRoot=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository')).TrimEnd('\')+'\'
if (-not $image.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($image) -ne 'amdkmdag.sys') { throw 'Unexpected GPU service kernel path.' }
$kernelHash=(Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
$configHash=(Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $image) 'amdgcf.dat') -Algorithm SHA256).Hash
$normal=($options -band 1) -ne 0 -and ($options -band 2) -eq 0
$passed=$normal -and $values['DEVPKEY_Device_ProblemCode'] -eq 0 -and $values['DEVPKEY_Device_DriverVersion'] -eq '32.0.21043.21001' -and $kernelHash -eq 'AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152' -and $configHash -eq '7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717'
$report=[PSCustomObject]@{Passed=$passed;CapturedUtc=[datetime]::UtcNow.ToString('o');BootUtc=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o');Device=$devices[0].InstanceId;ProblemCode=$values['DEVPKEY_Device_ProblemCode'];Inf=$values['DEVPKEY_Device_DriverInfPath'];Version=$values['DEVPKEY_Device_DriverVersion'];CodeIntegrityOptions=$options;TestModeActive=(($options -band 2)-ne 0);KernelSHA256=$kernelHash;ConfigurationSHA256=$configHash;Limitation='Read-only identity/signing/hash verification; rendering and sleep are separate hardware tests.'}
$report | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$report | ConvertTo-Json
if (-not $passed) { throw 'The selected GPU does not match the verified normal-mode configuration candidate.' }
