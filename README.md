# menglab-toolkit

## 目的

中継サーバーと SSH トンネルを経由して、学内ネットワークから研究室内部のネットワークに接続し、ページ取得・プレビューするためのツールです。

## OS ごとの使い分け

| OS | セットアップ | 実行（推奨） | 本体スクリプト |
|----|--------------|--------------|----------------|
| macOS / Linux | `setup_unix.sh` | `menglab` | `wpfetch_relay.sh` |
| Windows | `setup_windows.ps1` | `menglab`（PATH 通し後）または `menglab.ps1` | `wpfetch_relay.ps1` |

macOS と Linux は同じ手順（bash）です。Windows は PowerShell 用の `.ps1` を使います。

## セットアップ
macOS / Linux
```bash
chmod +x ./setup_unix.sh
./setup_unix.sh
```

Windows
```powershell
powershell -ExecutionPolicy Bypass -File ".\setup_windows.ps1"
```

## 実行

```bash
menglab
```