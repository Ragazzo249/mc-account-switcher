# Minecraft 統合版 アカウント切り替え調査ツール - スナップショット採取
# 作者: Ragazzo249
#
# アカウント切り替えの前後でファイル状態を記録し、
# 「サインイン状態がどのファイルに記録されているか」を特定するために使う。
# 読み取り専用。ファイルの内容は一切保存せず、ハッシュのみを記録する。
#
# tako:run[before]: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}" -Label before
# tako:run[after]: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}" -Label after
# tako:cwd: ${fileDir}

param(
    [Parameter(Mandatory = $true)]
    [string]$Label
)

$ErrorActionPreference = 'Stop'

# 調査対象。アカウント切り替えで書き換わる可能性がある領域をすべて含める
$targets = @(
    @{ Name = 'bedrock'; Path = "$env:APPDATA\Minecraft Bedrock" }
    @{ Name = 'uwp';     Path = "$env:LOCALAPPDATA\Packages\Microsoft.MinecraftUWP_8wekyb3d8bbwe" }
    @{ Name = 'xip';     Path = "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider_8wekyb3d8bbwe" }
    @{ Name = 'gaming';  Path = "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalCache" }
    @{ Name = 'tokens';  Path = "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache" }
)

# 差分ノイズにしかならない領域は除外する。
# minecraftWorlds はワールドDBで巨大かつ切り替えとは無関係、
# INetCache/INetCookies 等はアプリ内ブラウザのキャッシュ。
$excludePatterns = @(
    '\\minecraftWorlds\\'
    '\\AC\\INetCache\\'
    '\\AC\\INetCookies\\'
    '\\AC\\INetHistory\\'
    '\\AC\\Temp\\'
    '\\Screenshots\\'
)

# これを超えるファイルはハッシュを取らない（切り替え判定に不要なうえ時間がかかる）
$maxHashBytes = 32MB

function Test-Excluded {
    param([string]$FullPath)
    foreach ($pattern in $excludePatterns) {
        if ($FullPath -like "*$pattern*") { return $true }
    }
    return $false
}

function Get-Snapshot {
    param([string]$Name, [string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        Write-Host ("  {0,-8} : 存在しません ({1})" -f $Name, $Root) -ForegroundColor DarkGray
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $items = Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue

    foreach ($item in $items) {
        if (Test-Excluded $item.FullName) { continue }

        $relative = $item.FullName.Substring($Root.Length).TrimStart('\')
        $isDir = $item.PSIsContainer

        $hash = $null
        $size = $null
        if (-not $isDir) {
            $size = $item.Length
            if ($size -le $maxHashBytes) {
                try {
                    $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
                } catch {
                    # ロック中・権限不足。差分判定はサイズと更新時刻で代替する
                    $hash = 'UNREADABLE'
                }
            } else {
                $hash = 'SKIP_LARGE'
            }
        }

        $entries.Add([PSCustomObject]@{
            key      = "$Name|$relative"
            area     = $Name
            path     = $relative
            dir      = $isDir
            size     = $size
            mtime    = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            hash     = $hash
        })
    }

    Write-Host ("  {0,-8} : {1} 件" -f $Name, $entries.Count) -ForegroundColor Gray
    return $entries.ToArray()
}

function Get-RegistrySnapshot {
    $entries = New-Object System.Collections.Generic.List[object]

    # Windows に登録済みの Microsoft アカウント一覧（キー名のみ、値は取らない）
    $identityKey = 'HKCU:\SOFTWARE\Microsoft\IdentityCRL\UserExtendedProperties'
    if (Test-Path $identityKey) {
        foreach ($sub in Get-ChildItem $identityKey -ErrorAction SilentlyContinue) {
            $entries.Add([PSCustomObject]@{
                key   = "reg|IdentityCRL\$($sub.PSChildName)"
                area  = 'reg'
                path  = "IdentityCRL\$($sub.PSChildName)"
                dir   = $false
                size  = $null
                mtime = $null
                hash  = 'EXISTS'
            })
        }
    }

    # Xbox Live のサインイン状態が載る可能性があるキー
    foreach ($root in @('HKCU:\SOFTWARE\Microsoft\XboxLive', 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.XboxIdentityProvider_8wekyb3d8bbwe')) {
        if (-not (Test-Path $root)) { continue }
        $keys = @($root) + (Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.PSPath })
        foreach ($k in $keys) {
            $props = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
            if ($null -eq $props) { continue }
            $shortKey = $k -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                # 値そのものではなくハッシュを記録する（トークンが含まれ得るため）
                $text = [string]$p.Value
                $sha = [System.BitConverter]::ToString(
                    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                        [System.Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '')
                $entries.Add([PSCustomObject]@{
                    key   = "reg|$shortKey\$($p.Name)"
                    area  = 'reg'
                    path  = "$shortKey\$($p.Name)"
                    dir   = $false
                    size  = $text.Length
                    mtime = $null
                    hash  = $sha
                })
            }
        }
    }

    Write-Host ("  {0,-8} : {1} 件" -f 'reg', $entries.Count) -ForegroundColor Gray
    return $entries.ToArray()
}

# --- 実行 ---

$outDir = Join-Path $PSScriptRoot 'snapshots'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

Write-Host "スナップショット採取: $Label" -ForegroundColor Cyan

$all = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $all.AddRange([object[]](Get-Snapshot -Name $t.Name -Root $t.Path))
}
$all.AddRange([object[]](Get-RegistrySnapshot))

# Minecraft が起動中だとファイルが書き換わる途中の状態を拾うので警告する
$running = Get-Process -Name 'Minecraft.Windows' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "警告: Minecraft が起動中です。終了してから採取し直すことを推奨します。" -ForegroundColor Yellow
}

$snapshot = [PSCustomObject]@{
    label     = $Label
    takenAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    mcRunning = [bool]$running
    files     = $all.ToArray()
}

$outFile = Join-Path $outDir "$Label.json"
$snapshot | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $outFile -Encoding utf8

Write-Host ""
Write-Host "合計 $($all.Count) 件を保存しました:" -ForegroundColor Green
Write-Host "  $outFile"
