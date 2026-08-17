# Minecraft アカウント切り替えツール（統合版 / Windows）

Minecraft for Windows（統合版）のアカウントを、**ゲーム内のサインアウト・再サインインなしで**切り替える Windows 用ツールです。

登録したアカウントをクリックするだけで切り替わり、そのまま Minecraft が起動します。パスワードや 2 段階認証の入力も不要です。

普段遊ぶアカウントと検証用アカウントを行き来する場合や、1 台の PC を家族で共有している場合に使えます。

## 動作環境

- Windows 10 / 11
- Minecraft for Windows（統合版）
- Windows PowerShell 5.1（Windows に標準搭載）

追加のインストールは不要です。Java 版には対応していません。

## インストール

[Releases](../../releases) から `mc-account-switcher-setup-x.y.z.exe` をダウンロードして実行してください。

インストーラーが次を行います。

- インストール先の選択（既定は `%LOCALAPPDATA%\Programs\MinecraftAccountSwitcher`）
- **デスクトップにアイコンを作成**（チェックボックスで選択可能）
- スタートメニューへの登録
- アンインストーラーの登録（「アプリと機能」から削除できます）

管理者権限は不要です。インストール後はデスクトップのアイコンから起動します。

### ZIP 版

インストールせずに使いたい場合は ZIP をダウンロードし、展開して `setup.cmd` を実行してください。ファイルのブロック解除とショートカット作成のみを行います。

### アンインストール

「設定 → アプリ → インストールされているアプリ」から削除できます。削除時に、登録したアカウント情報も消すかどうかを確認します。

## 使い方

### アカウントを登録する

初回は使いたいアカウントを登録します。「＋ アカウントを追加」を押すと登録ダイアログが開きます。

現在サインイン中のアカウントがそのまま表示されるので、登録名を入れて「登録」を押すだけです。

**まだサインインしたことがないアカウント**を追加する場合は、一度だけゲーム内でのサインインが必要です。ダイアログ内に手順があり、そこから直接 Minecraft を起動できます。

1. ダイアログの「Minecraft を起動」を押す
2. ゲーム内で 設定 → アカウント → サインアウト
3. 追加したいアカウントでサインインする
4. Minecraft を終了し、ダイアログの「再確認」を押す
5. 検出されたアカウントに登録名を付けて「登録」

この手間が必要なのは新規登録の 1 回だけです。

### 切り替える

一覧からアカウントのカードをクリックするだけです。切り替わって Minecraft が起動します。

カードの右クリックから、登録名の変更と削除ができます。

### メールアドレスを削除する

画面に映したくない場合や、フォルダを他人に渡す場合は「メールアドレスを削除」を押します。登録済みすべてのアカウントから表示用のメールアドレスが削除され、以後に登録するアカウントにも保存されなくなります。

なお、切り替え時にレジストリへ書き戻す内部データ（`xboxLive` 配列内の `UserName`）にはメールアドレスが残ります。こちらを消すと切り替えが正しく動作しなくなる可能性があるため、意図的に残しています。

### コマンドラインから使う

自動化したい場合は `mc-profile.ps1` を使います。

```powershell
.\mc-profile.ps1 current               # 今どのアカウントか表示
.\mc-profile.ps1 list                  # 登録済み一覧（* が現在）
.\mc-profile.ps1 save 検証用           # 現在の状態を登録
.\mc-profile.ps1 switch 普段用 -Launch  # 切り替えて Minecraft 起動
.\mc-profile.ps1 remove 検証用         # 登録を削除
.\mc-profile.ps1 restore               # 直前の状態に戻す
```

## 仕組み

切り替え前後のファイルとレジストリを実測して特定した結果、次のことが分かりました。

- **アカウント切り替えの実体は `HKCU:\SOFTWARE\Microsoft\XboxLive` の値**
  （AccountId / Xuid / Gamertag / UserName / AgeGroup など）
- **トークンキャッシュ（`%LOCALAPPDATA%\Microsoft\TokenBroker\Cache\*.tbres`）は切り替えても削除されない**
  追加・更新のみで、過去にサインインしたアカウントの認証情報が共存し続けます。
  そのため上記レジストリ値を書き戻すだけで、再認証なしに切り替わります
- **セーブデータはもともとアカウント別に自動分離されている**
  `%APPDATA%\Minecraft Bedrock\Users\<内部ID>\games\com.mojang\`
  options.txt・ワールド・スキンがアカウントごとに独立しているため、データの入れ替えは不要です

本ツールは XboxLive キーの値をプロファイルとして保存・復元しているだけで、**トークンやセーブデータには一切触れません**。

## 安全策

- 切り替え前に XboxLive キーを `profiles\_backup\` へ自動バックアップします
- Minecraft の起動中は切り替えを拒否します
- おかしくなったら「直前の状態に戻す」（CLI では `restore`）で復旧できます。
  それでも直らない場合は、ゲーム内から手動でサインインし直せば元に戻ります

## 注意

- 非公式ツールです。Mojang / Microsoft とは関係ありません
- Windows のレジストリ（`HKCU:\SOFTWARE\Microsoft\XboxLive`）を書き換えます。
  自動バックアップと復元機能はありますが、利用は自己責任でお願いします
- Minecraft のアップデートによって動作しなくなる可能性があります。
  その場合は下記の調査用スクリプトで原因を追えます
- `profiles\` には登録したアカウントのメールアドレスとゲーマータグが含まれます。
  トークンや認証情報は含みませんが、このフォルダは共有しないでください

## ファイル構成

| ファイル | 役割 |
|---|---|
| `mc-switcher.ps1` | GUI 本体 |
| `mc-switcher.cmd` | GUI をダブルクリックで起動するランチャー |
| `mc-profile.ps1` | CLI |
| `lib.ps1` | 共通ロジック（GUI・CLI 両方から読み込む） |
| `setup.ps1` / `setup.cmd` | 初回セットアップ |
| `create-shortcut.ps1` | デスクトップにショートカットを作成 |
| `snapshot.ps1` / `compare.ps1` | 調査用。切り替え前後の差分を採取・比較する |
| `assets\app.ico` | ショートカット・インストーラー用のアイコン |
| `tools\make-icon.ps1` | アイコンの生成（開発者向け） |
| `installer\*.iss` | Inno Setup のインストーラー定義（開発者向け） |
| `build-package.ps1` | 配布用 ZIP を作成する（開発者向け） |
| `build-installer.ps1` | インストーラーを作成する（開発者向け） |
| `profiles\` | 登録したアカウント（`_backup\` に自動バックアップ） |
| `settings.json` | メールアドレスの表示設定。「メールアドレスを削除」を実行すると作られる |

## 動作しなくなったときの調査

Minecraft のアップデートで切り替えが効かなくなった場合、仕組みを特定したときと同じ手順で再調査できます。

```powershell
.\snapshot.ps1 -Label before   # 切り替え前（Minecraft は終了しておく）
# ここでゲーム内から手動でアカウントを切り替える
.\snapshot.ps1 -Label after    # 切り替え後
.\compare.ps1 -Before before -After after
```

ファイルの内容は保存せず、一覧・サイズ・更新時刻・ハッシュだけを記録します。

## 開発

スクリプトを編集する場合、`.ps1` は **BOM 付き UTF-8** で保存してください。BOM なしだと Windows PowerShell 5.1 が Shift-JIS として読み、日本語コメントで構文エラーになります。

配布物は次で作成します。ZIP には個人情報（`profiles\` / `settings.json` / `snapshots\`）が含まれないよう除外し、出力後に混入がないか検査します。

```powershell
.\build-package.ps1      # 配布用 ZIP
.\build-installer.ps1    # インストーラー（要 Inno Setup 6）
```

Inno Setup が無い場合は `winget install --id JRSoftware.InnoSetup` で導入できます。

アイコンのデザインを変えたい場合は `tools\make-icon.ps1` を編集して実行すると `assets\app.ico` が再生成されます。

## ライセンス

[MIT License](LICENSE)
