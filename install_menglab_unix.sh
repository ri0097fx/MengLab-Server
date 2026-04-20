#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CMD="${SCRIPT_DIR}/menglab"
SRC_CORE="${SCRIPT_DIR}/wpfetch_relay.sh"

if [[ ! -f "${SRC_CMD}" ]]; then
  echo "ERROR: ${SRC_CMD} が見つかりません。"
  exit 1
fi
if [[ ! -f "${SRC_CORE}" ]]; then
  echo "ERROR: ${SRC_CORE} が見つかりません。"
  exit 1
fi

chmod +x "${SRC_CORE}" "${SRC_CMD}"

TARGET_DIR="${HOME}/.local/bin"
TARGET_CMD="${TARGET_DIR}/menglab"
TARGET_CORE="${TARGET_DIR}/wpfetch_relay.sh"
mkdir -p "${TARGET_DIR}"

cp "${SRC_CMD}" "${TARGET_CMD}"
cp "${SRC_CORE}" "${TARGET_CORE}"
chmod +x "${TARGET_CMD}"
chmod +x "${TARGET_CORE}"

add_path_line='export PATH="$HOME/.local/bin:$PATH"'

read -r -p "PATH に ~/.local/bin を追加しますか? [y/N]: " add_path_answer
if [[ "${add_path_answer}" =~ ^[Yy]$ ]]; then
  for rc in "${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.profile"; do
    if [[ -f "${rc}" ]]; then
      if ! grep -Fq "${add_path_line}" "${rc}"; then
        printf '\n%s\n' "${add_path_line}" >> "${rc}"
      fi
    fi
  done
  echo "PATH へ追加しました。新しいシェルを開くか、以下を実行してください:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
else
  echo "PATH は変更していません。"
  echo "フルパス実行例:"
  echo "  ${TARGET_CMD}"
fi

echo "インストール完了:"
echo "  ${TARGET_CMD}"
echo "  ${TARGET_CORE}"
echo "実行例:"
echo "  menglab"
echo "  menglab about/"
echo "  menglab setup"
