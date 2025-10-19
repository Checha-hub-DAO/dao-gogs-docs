param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$InputCsv,
    [string[]]$UrlCsv,
    [string]$OutFile
)

$ErrorActionPreference = "Stop"
function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok  ($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }

$Root = (Resolve-Path -LiteralPath $Root).Path
$contactsDir = Join-Path $Root "contacts"
New-Item -ItemType Directory -Force -Path $contactsDir | Out-Null
$OutFile = if ($OutFile) { $OutFile } else { Join-Path $contactsDir "podillia_contacts.csv" }

$cols = "Name", "Org", "Role", "City", "Phone", "Email", "Channel", "Notes", "Source", "Verified", "UpdatedUtc"
$bag = New-Object System.Collections.Generic.List[object]

function Normalize-Row($r) {
    $o = [ordered]@{}
    foreach ($c in $cols) { $o[$c] = $null }

    $o["Name"] = ($r.Name, $r.FullName, $r.Contact) -ne $null | Select-Object -First 1
    $o["Org"] = ($r.Org, $r.Organization, $r.Company) -ne $null | Select-Object -First 1
    $o["Role"] = ($r.Role, $r.Position) -ne $null | Select-Object -First 1
    $o["City"] = ($r.City, $r.Location) -ne $null | Select-Object -First 1
    $o["Phone"] = ($r.Phone, $r.Tel) -ne $null | Select-Object -First 1
    $o["Email"] = ($r.Email, $r.Mail) -ne $null | Select-Object -First 1
    $o["Channel"] = ($r.Channel, $r.Platform) -ne $null | Select-Object -First 1
    $o["Notes"] = ($r.Notes, $r.Note) -ne $null | Select-Object -First 1
    $o["Source"] = ($r.Source, $r.Origin) -ne $null | Select-Object -First 1
    $o["Verified"] = ($r.Verified) -ne $null | Select-Object -First 1
    $o["UpdatedUtc"] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    if ($o["Email"]) { $o["Email"] = $o["Email"].ToString().Trim().ToLower() }
    if ($o["Phone"]) { $o["Phone"] = ($o["Phone"] -replace '[^\d\+]', '').Trim() }

    return [PSCustomObject]$o
}

# Pull URL CSVs (optional)
$tmp = Join-Path $contactsDir "_tmp"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if ($UrlCsv) {
    foreach ($u in $UrlCsv) {
        try {
            Info "Downloading: $u"
            $fn = Join-Path $tmp ("url_" + [guid]::NewGuid().ToString("N") + ".csv")
            Invoke-WebRequest -Uri $u -OutFile $fn -UseBasicParsing
            $InputCsv += $fn
        }
        catch {
            Warn "Failed to download ${u}: $($_.Exception.Message)"
        }
    }
}

# Merge
foreach ($f in $InputCsv) {
    if (-not $f) { continue }
    if (-not (Test-Path -LiteralPath $f)) { Warn "Skip, missing file: $f"; continue }
    Info "Import: $f"
    $rows = Import-Csv -LiteralPath $f
    foreach ($r in $rows) { $bag.Add( (Normalize-Row $r) ) }
}

# Dedup by Email|Phone
$dedup = $bag | Group-Object {
    $k = ""
    if ($_.Email) { $k += "E:" + $_.Email }
    if ($_.Phone) { $k += "|P:" + $_.Phone }
    if ([string]::IsNullOrWhiteSpace($k)) { $k = "NO_KEY:" + [guid]::NewGuid().ToString("N") }
    $k
} | ForEach-Object { $_.Group | Select-Object -First 1 }

if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
$dedup | Select-Object $cols | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutFile

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Ok "Done: $OutFile (rows: $($dedup.Count))"

