# menglab-toolkit

## OS ごとの使い分け

| OS | セットアップ | 実行（推奨） | 本体スクリプト |
|----|--------------|--------------|----------------|
| macOS / Linux | `setup_unix.sh` | `menglab` | `wpfetch_relay.sh` |
| Windows | `setup_windows.ps1` | `menglab`（PATH 通し後）または `menglab.ps1` | `wpfetch_relay.ps1` |

macOS と Linux は同じ手順（bash）です。Windows は PowerShell 用の `.ps1` を使います。

## セットアップ

```bash
chmod +x ./setup_unix.sh
./setup_unix.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup_windows.ps1"
```

## 実行

```bash
menglab
```

## 直接実行

```bash
./wpfetch_relay.sh preview
./wpfetch_relay.sh fetch
./wpfetch_relay.sh reset
```

```powershell
.\wpfetch_relay.ps1 preview
.\wpfetch_relay.ps1 fetch
.\wpfetch_relay.ps1 reset
```
