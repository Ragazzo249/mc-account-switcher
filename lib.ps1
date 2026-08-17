# Minecraft 統合版 アカウント切り替え - 共通ロジック
# 作者: Ragazzo249
#
# アカウント切り替えの実体は HKCU:\SOFTWARE\Microsoft\XboxLive の値。
# トークンキャッシュ（TokenBroker）は切り替えでも削除されず両アカウント分が
# 共存するため、このレジストリ値を入れ替えるだけで再認証なしに切り替わる。
#
# CLI (mc-profile.ps1) と GUI (mc-switcher.ps1) の両方から dot-source して使う。

$script:XboxKey = 'HKCU:\SOFTWARE\Microsoft\XboxLive'
$script:BedrockRoot = "$env:APPDATA\Minecraft Bedrock"
$script:ProfileDir = Join-Path $PSScriptRoot 'profiles'
$script:BackupDir = Join-Path $script:ProfileDir '_backup'
$script:SettingsPath = Join-Path $PSScriptRoot 'settings.json'

function Initialize-Storage {
    foreach ($d in @($script:ProfileDir, $script:BackupDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    }
}

function Test-MinecraftRunning {
    return [bool](Get-Process -Name 'Minecraft.Windows' -ErrorAction SilentlyContinue)
}

function Start-MinecraftBedrock {
    Start-Process 'minecraft://'
}

function Get-XboxLiveState {
    if (-not (Test-Path $script:XboxKey)) {
        throw "XboxLive キーが見つかりません。一度 Minecraft か Xbox アプリでサインインしてください。"
    }
    $item = Get-Item $script:XboxKey
    $values = @()
    foreach ($p in $item.Property) {
        $values += [PSCustomObject]@{
            name = $p
            kind = $item.GetValueKind($p).ToString()
            data = (Get-ItemProperty -LiteralPath $script:XboxKey -Name $p).$p
        }
    }
    return $values
}

function Set-XboxLiveState {
    param([Parameter(Mandatory = $true)]$Values)

    # プロファイルに存在しない値は消す。
    # ModernGamertagSuffix のようにアカウントによって有無が変わる値があるため
    $wanted = @($Values | ForEach-Object { $_.name })
    foreach ($existing in (Get-Item $script:XboxKey).Property) {
        if ($wanted -notcontains $existing) {
            Remove-ItemProperty -LiteralPath $script:XboxKey -Name $existing -ErrorAction SilentlyContinue
        }
    }

    foreach ($v in $Values) {
        Set-ItemProperty -LiteralPath $script:XboxKey -Name $v.name -Value $v.data -Type $v.kind
    }
}

# 内部ユーザーID（Users\<ID>）と XUID の対応表。
# Screenshots 配下のフォルダ名が XUID になっているのを利用する
function Get-BedrockUserMap {
    $map = @{}
    $usersDir = Join-Path $script:BedrockRoot 'Users'
    if (-not (Test-Path $usersDir)) { return $map }

    foreach ($dir in Get-ChildItem $usersDir -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -eq 'Shared') { continue }
        $shots = Join-Path $dir.FullName 'games\com.mojang\Screenshots'
        if (-not (Test-Path $shots)) { continue }
        foreach ($x in Get-ChildItem $shots -Directory -ErrorAction SilentlyContinue) {
            if ($x.Name -match '^\d+$') { $map[$x.Name] = $dir.Name }
        }
    }
    return $map
}

function Get-CurrentAccount {
    $state = Get-XboxLiveState
    $pick = {
        param($n)
        $hit = $state | Where-Object { $_.name -eq $n } | Select-Object -First 1
        if ($hit) { return $hit.data } else { return $null }
    }

    $xuid = & $pick 'Xuid'
    $map = Get-BedrockUserMap
    $internalId = if ($xuid -and $map.ContainsKey([string]$xuid)) { $map[[string]$xuid] } else { $null }

    return [PSCustomObject]@{
        Gamertag   = & $pick 'Gamertag'
        UserName   = & $pick 'UserName'
        Xuid       = $xuid
        AccountId  = & $pick 'AccountId'
        InternalId = $internalId
        DataPath   = if ($internalId) { Join-Path $script:BedrockRoot "Users\$internalId\games\com.mojang" } else { $null }
        State      = $state
    }
}

function Save-XboxLiveBackup {
    Initialize-Storage
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $path = Join-Path $script:BackupDir "xboxlive-$stamp.json"
    Get-XboxLiveState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Test-ProfileName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "プロファイル名を指定してください。"
    }
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        if ($Name.Contains($c)) {
            throw "プロファイル名にファイル名として使えない文字が含まれています: $Name"
        }
    }
}

function Get-ProfilePath {
    param([string]$Name)
    Test-ProfileName $Name
    return Join-Path $script:ProfileDir "$Name.json"
}

function Get-AccountProfiles {
    Initialize-Storage
    $result = @()
    $files = Get-ChildItem -LiteralPath $script:ProfileDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
             Sort-Object Name
    foreach ($f in $files) {
        try {
            $result += Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        } catch {
            Write-Warning "プロファイルを読めませんでした: $($f.Name)"
        }
    }
    return $result
}

# 同じアカウント（XUID）が別名で登録済みかを調べる。二重登録の警告に使う
function Get-ProfileByXuid {
    param([string]$Xuid)
    if ([string]::IsNullOrWhiteSpace([string]$Xuid)) { return $null }
    return @(Get-AccountProfiles) | Where-Object { [string]$_.xuid -eq [string]$Xuid } | Select-Object -First 1
}

function Test-ProfileExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    Test-ProfileName $Name
    return Test-Path -LiteralPath (Join-Path $script:ProfileDir "$Name.json")
}

function Get-AccountProfile {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = Get-ProfilePath $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "プロファイル '$Name' が見つかりません。"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
}

function Save-AccountProfile {
    param([Parameter(Mandatory = $true)][string]$Name)
    Initialize-Storage
    $path = Get-ProfilePath $Name
    $info = Get-CurrentAccount

    if (-not $info.Xuid) {
        throw "サインイン中のアカウントを特定できませんでした。一度 Minecraft でサインインしてください。"
    }

    $profile = [PSCustomObject]@{
        name       = $Name
        savedAt    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        gamertag   = $info.Gamertag
        userName   = $info.UserName
        xuid       = $info.Xuid
        internalId = $info.InternalId
        xboxLive   = $info.State
    }
    $profile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8
    return $profile
}

function Remove-AccountProfile {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = Get-ProfilePath $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "プロファイル '$Name' が見つかりません。"
    }
    Remove-Item -LiteralPath $path -Force
}

# --- メールアドレスの表示・保存に関する設定 ---

function Get-AppSettings {
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            return Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding utf8 | ConvertFrom-Json
        } catch {
            Write-Warning "設定ファイルを読めませんでした。既定値を使います。"
        }
    }
    return [PSCustomObject]@{ hideEmail = $false }
}

function Set-AppSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)]$Value
    )
    $s = Get-AppSettings
    if ($s.PSObject.Properties.Name -contains $Key) {
        $s.$Key = $Value
    } else {
        $s | Add-Member -NotePropertyName $Key -NotePropertyValue $Value
    }
    $s | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $script:SettingsPath -Encoding utf8
}

# プロファイルから表示用のメールアドレスを消す。
# 切り替えに使う xboxLive 配列内の UserName は残す。
# こちらを消すと復元時にレジストリの値が欠けるため
function Clear-ProfileEmail {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Get-ProfilePath $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "プロファイル '$Name' が見つかりません。"
    }

    $data = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]::IsNullOrEmpty([string]$data.userName)) { return $false }

    $data.userName = ''
    $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8
    return $true
}

function Clear-AllProfileEmails {
    $count = 0
    foreach ($p in @(Get-AccountProfiles)) {
        if (Clear-ProfileEmail -Name $p.name) { $count++ }
    }
    return $count
}

function Switch-Account {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Test-MinecraftRunning) {
        throw "Minecraft が起動中です。終了してから切り替えてください。"
    }

    $target = Get-AccountProfile -Name $Name
    $before = Get-CurrentAccount

    if ([string]$before.Xuid -eq [string]$target.xuid) {
        return [PSCustomObject]@{ Changed = $false; From = $before.Gamertag; To = $target.gamertag; Backup = $null }
    }

    $backup = Save-XboxLiveBackup
    Set-XboxLiveState $target.xboxLive
    return [PSCustomObject]@{ Changed = $true; From = $before.Gamertag; To = $target.gamertag; Backup = $backup }
}

function Restore-LatestBackup {
    if (Test-MinecraftRunning) {
        throw "Minecraft が起動中です。終了してから実行してください。"
    }
    $latest = Get-ChildItem -LiteralPath $script:BackupDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw "バックアップがありません。" }

    $values = Get-Content -LiteralPath $latest.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    Set-XboxLiveState $values
    return $latest.Name
}
