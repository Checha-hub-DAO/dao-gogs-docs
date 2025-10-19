# Utils.TZ.ps1
function Get-KyivDate {
    param([datetime]$Base = (Get-Date))
    $ids = @('FLE Standard Time', 'Europe/Kyiv') # Windows / cross-plat fallback
    foreach ($id in $ids) {
        try {
            $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($id)
            return [System.TimeZoneInfo]::ConvertTime($Base, $tz)
        }
        catch {}
    }
    return $Base
}

