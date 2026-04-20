#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="${SCRIPT_DIR}/wpfetch_relay.sh"

if [[ ! -x "${CORE}" ]]; then
  echo "ERROR: ${CORE} が見つからないか、実行権限がありません。"
  exit 1
fi

run_core() {
  echo
  echo ">>> $*"
  "$@"
  echo
}

while true; do
  cat <<'EOF'
==========================
 WPFetch かんたんメニュー
==========================
1) 初期設定 (資格情報を保存)
2) トップページ取得 (title表示)
3) トップページをプレビュー
4) 任意パスをプレビュー
5) 保存した資格情報を削除
0) 終了
EOF
  read -r -p "番号を選んでください: " choice

  case "${choice}" in
    1) run_core "${CORE}" setup ;;
    2) run_core "${CORE}" fetch ;;
    3) run_core "${CORE}" preview ;;
    4)
      read -r -p "パス (例: about/): " custom_path
      run_core "${CORE}" preview "${custom_path}"
      ;;
    5) run_core "${CORE}" reset ;;
    0) echo "終了します。"; exit 0 ;;
    *) echo "無効な番号です。もう一度選んでください。" ;;
  esac
done
