# Minecraft 統合版 アカウント切り替え調査ツール - スナップショット差分
# 作者: Ragazzo249
#
# snapshot.ps1 で採取した2つの状態を比較し、
# アカウント切り替えで実際に書き換わったファイルを抽出する。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}" -Before before -After after
# tako:cwd: ${fileDir}

param(
    [Parameter(Mandatory = $true)]
    [string]$Before,

    [Parameter(Mandatory = $true)]
    [string]$After,

    # ディレクトリの更新時刻の変化も表示する（既定は非表示、ノイズが多いため）
    [switch]$IncludeDirs
)

$ErrorActionPreference = 'Stop'

$snapDir = Join-Path $PSScriptRoot 'snapshots'

function Read-Snapshot {
    param([string]$Label)
    $path = Join-Path $snapDir "$Label.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "スナップショットが見つかりません: $path"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
}

function ConvertTo-Map {
    param($Snapshot)
    $map = @{}
    foreach ($f in $Snapshot.files) { $map[$f.key] = $f }
    return $map
}

$snapA = Read-Snapshot $Before
$snapB = Read-Snapshot $After
$mapA = ConvertTo-Map $snapA
$mapB = ConvertTo-Map $snapB

Write-Host "比較: $Before ($($snapA.takenAt))  ->  $After ($($snapB.takenAt))" -ForegroundColor Cyan
Write-Host ""

$added = New-Object System.Collections.Generic.List[object]
$removed = New-Object System.Collections.Generic.List[object]
$changed = New-Object System.Collections.Generic.List[object]

foreach ($key in $mapB.Keys) {
    $b = $mapB[$key]
    if (-not $mapA.ContainsKey($key)) {
        $added.Add($b)
        continue
    }
    $a = $mapA[$key]
    if ($b.dir -and -not $IncludeDirs) { continue }

    $diffReason = @()
    if ($a.hash -ne $b.hash) { $diffReason += '内容' }
    if ($a.size -ne $b.size) { $diffReason += "サイズ $($a.size)->$($b.size)" }
    if ($diffReason.Count -gt 0) {
        $changed.Add([PSCustomObject]@{
            area   = $b.area
            path   = $b.path
            reason = ($diffReason -join ', ')
            mtime  = $b.mtime
        })
    }
}

foreach ($key in $mapA.Keys) {
    if (-not $mapB.ContainsKey($key)) { $removed.Add($mapA[$key]) }
}

function Show-Group {
    param([string]$Title, $Items, [string]$Color)
    Write-Host "$Title ($($Items.Count) 件)" -ForegroundColor $Color
    if ($Items.Count -eq 0) {
        Write-Host "  なし" -ForegroundColor DarkGray
        Write-Host ""
        return
    }
    foreach ($grp in ($Items | Group-Object area | Sort-Object Name)) {
        Write-Host "  [$($grp.Name)]" -ForegroundColor DarkCyan
        foreach ($i in ($grp.Group | Sort-Object path)) {
            $extra = ''
            if ($i.PSObject.Properties.Name -contains 'reason') { $extra = "  <- $($i.reason)" }
            Write-Host "    $($i.path)$extra"
        }
    }
    Write-Host ""
}

Show-Group '● 追加されたファイル' $added 'Green'
Show-Group '● 削除されたファイル' $removed 'Red'
Show-Group '● 内容が変わったファイル' $changed 'Yellow'

$total = $added.Count + $removed.Count + $changed.Count
Write-Host "差分合計: $total 件" -ForegroundColor Cyan

# 切り替えの本命候補（トークンとアカウント別データ）を強調して再掲する
$key = @($added; $removed; $changed) | Where-Object { $_.area -in @('tokens', 'bedrock', 'xip') }
if ($key.Count -gt 0) {
    Write-Host ""
    Write-Host "アカウント状態に直接関わる領域 (tokens / bedrock / xip): $($key.Count) 件" -ForegroundColor Magenta
}
