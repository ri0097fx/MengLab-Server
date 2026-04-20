#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "${SCRIPT_DIR}/install_menglab_unix.sh"
"${SCRIPT_DIR}/install_menglab_unix.sh"

echo
read -r -p "続けて資格情報セットアップを実行しますか? [Y/n]: " run_setup
if [[ -z "${run_setup}" || "${run_setup}" =~ ^[Yy]$ ]]; then
  "${HOME}/.local/bin/wpfetch_relay.sh" setup
fi

echo
echo "完了。利用例:"
echo "  menglab"
echo "  menglab about/"
