<#
Sets or reads the battery charge threshold on MSI laptops via the MSI_ACPI
WMI interface (namespace root\wmi, GUID ABBC0F6E-8EA1-11D1-00A0-C90629100000).

This talks directly to the embedded controller (EC register 0xd7) -- the
same interface MSI Center itself uses. Once set, the threshold is stored in
EC firmware and enforced in hardware: charging stops at the configured
percentage on its own, with no background process or monitoring script
needed, and it survives reboots.

Verified by round-trip test on an MSI Cyborg 15 A12VE (2026-08-18): write 80
-> read back 0xD0 (0x80 | 80). Encoding: write (percent | 0x80), read
(byte & 0x7F). Bit 7 marks the write as valid; it is not a separate
enable/disable flag -- writing 100 removes the practical limit (charges
normally to full).

KNOWN QUIRK -- displayed charge undershoots the EC threshold: the EC's own
fuel-gauge reading (what it compares against the threshold to decide when
to stop) is not the same counter as the percentage Windows displays (derived
from ACPI capacity values on its own refresh cadence). In practice the EC
can reach its threshold and cut charging before Windows' displayed number
catches up, so asking for 80 can visibly stop at ~78. This is a mismatch
between two independent counters, not a bug in the write/readback above --
readback always reflects exactly what was written to the register.
Confirmed on the Cyborg 15 A12VE: requesting 80 visibly stopped at 78.

Fix: -Offset adds a few extra points to the EC threshold so the *displayed*
stop point lands on -Percent. Default is 2 (the observed gap on this
machine). If your displayed stop point still doesn't match -Percent,
recalibrate: let it charge to a stop, note the gap, adjust -Offset by that
amount next time. Battery wear can drift full-charge-capacity over time, so
re-check the calibration occasionally.

Requires administrator privileges (WMI method calls to this class need an
elevated token). Self-elevates if not already running as admin.
#>

param(
    [ValidateRange(0, 100)]
    [int]$Percent = 80,

    [ValidateRange(-20, 20)]
    [int]$Offset = 2,

    [switch]$Get
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Percent $Percent -Offset $Offset"
    if ($Get) { $argList += " -Get" }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

$ecAddress = 0xd7

function Get-MsiAcpiInstance {
    $inst = Get-CimInstance -Namespace root\wmi -ClassName MSI_ACPI -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $inst) {
        throw "MSI_ACPI WMI class not found. This laptop's firmware may not expose the MSI ACPI-WMI interface (different model/generation)."
    }
    return $inst
}

function Get-BatteryChargeLimit {
    $inst = Get-MsiAcpiInstance
    $bytes = New-Object byte[] 32
    $bytes[0] = $ecAddress
    $pkg = New-CimInstance -ClassName Package_32 -Namespace root\wmi -Property @{ Bytes = $bytes } -ClientOnly
    $result = Invoke-CimMethod -InputObject $inst -MethodName Get_Data -Arguments @{ Data = $pkg } -ErrorAction Stop
    $raw = $result.Data.CimInstanceProperties["Bytes"].Value[1]
    return [int]($raw -band 0x7F)
}

function Set-BatteryChargeLimit {
    param([Parameter(Mandatory)][ValidateRange(0, 100)][int]$EcValue)
    $inst = Get-MsiAcpiInstance
    $bytes = New-Object byte[] 32
    $bytes[0] = $ecAddress
    $bytes[1] = [byte]($EcValue -bor 0x80)
    $pkg = New-CimInstance -ClassName Package_32 -Namespace root\wmi -Property @{ Bytes = $bytes } -ClientOnly
    $result = Invoke-CimMethod -InputObject $inst -MethodName Set_Data -Arguments @{ Data = $pkg } -ErrorAction Stop
    if (-not $result.ReturnValue) {
        throw "Set_Data returned failure."
    }
    Start-Sleep -Milliseconds 300
    $confirmed = Get-BatteryChargeLimit
    if ($confirmed -ne $EcValue) {
        throw "Verification failed: wrote $EcValue but EC now reads $confirmed. Not trusting this write -- check manually before relying on it."
    }
}

if ($Get) {
    $current = Get-BatteryChargeLimit
    if ($current -eq 0) {
        Write-Host "No charge limit set (laptop charges normally to 100%)."
    } else {
        Write-Host "EC threshold register currently reads: $current%"
        Write-Host "(This is the raw EC value, which may include a compensation offset -- see the -Offset note if the displayed charge doesn't stop where you expect.)"
    }
} else {
    $ecValue = [Math]::Max(0, [Math]::Min(100, $Percent + $Offset))
    Set-BatteryChargeLimit -EcValue $ecValue
    if ($Offset -ne 0) {
        Write-Host "Charge limit set: EC threshold $ecValue% ($Percent% target + $Offset% offset) and verified."
        Write-Host "This compensates for the known gap between the EC's internal charge counter and Windows' displayed percentage -- charging should now visibly stop around $Percent%. If it doesn't, adjust -Offset and re-run."
    } else {
        Write-Host "Charge limit set to $Percent% and verified."
    }
    Write-Host "This is persistent in EC firmware -- no background service needed."
}
