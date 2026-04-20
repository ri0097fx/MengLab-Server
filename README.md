# menglab-toolkit

ローカルネットワーク内の WordPress (`192.168.50.138/lab_server/`) に対して、  
逆トンネル経由で取得・プレビューするためのツールセットです。

## 構成

- `wpfetch_relay.sh` / `wpfetch_relay.ps1`  
  取得本体。認証情報保存、fetch、preview、reset を提供。
- `keep_reverse_tunnel.sh`  
  踏み台PC側で逆トンネルを維持。
- `menglab` / `menglab.ps1`  
  ランチャー（`menglab` で preview 実行）。
- `.vscode/`  
  Run and Debug / Tasks 用設定。
- `install_menglab_unix.sh` / `install_menglab_windows.ps1`  
  `menglab` コマンド導入スクリプト。

## 前提

- 中継サーバーと踏み台PCの接続が構築済み
- 踏み台PCで逆トンネルが起動済み
- 中継先デフォルト:
  - `RELAY_HOST=172.24.160.42`
  - `RELAY_USER=ihpc`
  - `RELAY_SSH_PORT=20002`
  - `REMOTE_REVERSE_PORT=28081`

## 使い方

### 1. 資格情報セットアップ

```bash
./wpfetch_relay.sh setup
```

Windows:

```powershell
.\wpfetch_relay.ps1 setup
```

### 2. 取得

```bash
./wpfetch_relay.sh fetch
./wpfetch_relay.sh preview
./wpfetch_relay.sh preview about/
```

Windows:

```powershell
.\wpfetch_relay.ps1 fetch
.\wpfetch_relay.ps1 preview
.\wpfetch_relay.ps1 preview about/
```

### 3. 保存情報削除

```bash
./wpfetch_relay.sh reset
```

Windows:

```powershell
.\wpfetch_relay.ps1 reset
```

## `menglab` コマンド化

macOS / Linux:

```bash
chmod +x ./install_menglab_unix.sh
./install_menglab_unix.sh
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File ".\install_menglab_windows.ps1"
```

インストーラは PATH 追加を確認します（デフォルト No）。

## VSCode / Cursor

- Run and Debug: `WPFetch: ...`
- Tasks: `Tasks: Run Task` -> `WPFetch: ...`

## セキュリティ

- 踏み台PCの逆トンネルは `127.0.0.1` 待受を維持
- 中継サーバの `authorized_keys` で `permitlisten` / `permitopen` を制限
- 詳細は `bastion_hardening.md` を参照

## 補足ドキュメント

- `WPFETCH_QUICKSTART.md`
- `MENGLAB_COMMAND_SETUP.md`
- `bastion_hardening.md`
