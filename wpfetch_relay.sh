#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./wpfetch_relay.sh setup
#   ./wpfetch_relay.sh reset
#   ./wpfetch_relay.sh preview [page_path]
#   ./wpfetch_relay.sh [page_path]
#
# Example:
#   ./wpfetch_relay.sh setup
#   ./wpfetch_relay.sh
#   ./wpfetch_relay.sh about/
#   ./wpfetch_relay.sh preview
#   ./wpfetch_relay.sh preview about/

RELAY_HOST="${RELAY_HOST:-172.24.160.42}"
RELAY_USER="${RELAY_USER:-ihpc}"
RELAY_SSH_PORT="${RELAY_SSH_PORT:-20002}"

# Reverse tunnel endpoint on relay server (must match bastion's -R setting)
REMOTE_REVERSE_PORT="${REMOTE_REVERSE_PORT:-28081}"

# Local temporary forward port on each user's PC
LOCAL_FORWARD_PORT="${LOCAL_FORWARD_PORT:-18081}"

# WordPress base path
WP_BASE_PATH="${WP_BASE_PATH:-/lab_server/}"
# Original site origin used in WordPress-generated absolute URLs.
WP_UPSTREAM_ORIGIN="${WP_UPSTREAM_ORIGIN:-http://192.168.50.138}"

KEY_PREFIX="wpfetch"
SVC_SCOPE="${RELAY_USER}@${RELAY_HOST}:${RELAY_SSH_PORT}${WP_BASE_PATH}"
KC_WP_USER_SERVICE="${KEY_PREFIX}.wp_user.${SVC_SCOPE}"
KC_WP_PASS_SERVICE="${KEY_PREFIX}.wp_pass.${SVC_SCOPE}"
KC_RELAY_PASS_SERVICE="${KEY_PREFIX}.relay_pass.${SVC_SCOPE}"

CMD="${1:-fetch}"
PAGE_PATH=""
PREVIEW_MODE=0
if [[ "${CMD}" == "preview" ]]; then
  PREVIEW_MODE=1
  PAGE_PATH="${2:-}"
elif [[ "${CMD}" == "setup" || "${CMD}" == "reset" || "${CMD}" == "fetch" ]]; then
  PAGE_PATH="${2:-}"
else
  PAGE_PATH="${1:-}"
fi
CONTROL_SOCK="/tmp/wpfetch-relay-${USER}.sock"
COOKIE_FILE="$(mktemp)"
ASKPASS_SCRIPT=""
BACKEND=""

# Legacy credential files (removed on reset when using insecure old paths)
ENC_DIR="${HOME}/.config/wpfetch"
LEGACY_PLAIN_FILE="${ENC_DIR}/credentials.env"
LEGACY_ENC_FILE="${ENC_DIR}/credentials.enc"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_backend() {
  if [[ -n "${WPFETCH_CRED_BACKEND:-}" ]]; then
    BACKEND="${WPFETCH_CRED_BACKEND}"
    case "${BACKEND}" in
      plain_file | encrypted_file)
        BACKEND="none"
        ;;
    esac
    return
  fi

  case "${OSTYPE:-}" in
    darwin*) BACKEND="macos_keychain" ;;
    *)
      if has_cmd secret-tool; then
        BACKEND="linux_secret_tool"
      else
        BACKEND="none"
      fi
      ;;
  esac
}

kc_macos_get() {
  local service="$1"
  security find-generic-password -a "${USER}" -s "${service}" -w 2>/dev/null || return 1
}

kc_macos_set() {
  local service="$1"
  local value="$2"
  security add-generic-password -U -a "${USER}" -s "${service}" -w "${value}" >/dev/null
}

kc_macos_delete() {
  local service="$1"
  security delete-generic-password -a "${USER}" -s "${service}" >/dev/null 2>&1 || true
}

kc_linux_get() {
  local service="$1"
  secret-tool lookup service "${service}" account "${USER}" 2>/dev/null || return 1
}

kc_linux_set() {
  local service="$1"
  local value="$2"
  printf '%s' "${value}" | secret-tool store --label="${service}" service "${service}" account "${USER}" >/dev/null
}

kc_linux_delete() {
  local service="$1"
  if has_cmd secret-tool; then
    secret-tool clear service "${service}" account "${USER}" >/dev/null 2>&1 || true
  fi
}

cred_get() {
  local key="$1"
  case "${BACKEND}" in
    macos_keychain)
      case "${key}" in
        WP_USER) kc_macos_get "${KC_WP_USER_SERVICE}" ;;
        WP_PASS) kc_macos_get "${KC_WP_PASS_SERVICE}" ;;
        RELAY_PASS) kc_macos_get "${KC_RELAY_PASS_SERVICE}" ;;
      esac
      ;;
    linux_secret_tool)
      case "${key}" in
        WP_USER) kc_linux_get "${KC_WP_USER_SERVICE}" ;;
        WP_PASS) kc_linux_get "${KC_WP_PASS_SERVICE}" ;;
        RELAY_PASS) kc_linux_get "${KC_RELAY_PASS_SERVICE}" ;;
      esac
      ;;
    none)
      return 1
      ;;
  esac
}

cred_set_all() {
  local wp_user="$1"
  local wp_pass="$2"
  local relay_pass="$3"

  case "${BACKEND}" in
    macos_keychain)
      kc_macos_set "${KC_WP_USER_SERVICE}" "${wp_user}"
      kc_macos_set "${KC_WP_PASS_SERVICE}" "${wp_pass}"
      kc_macos_set "${KC_RELAY_PASS_SERVICE}" "${relay_pass}"
      ;;
    linux_secret_tool)
      kc_linux_set "${KC_WP_USER_SERVICE}" "${wp_user}"
      kc_linux_set "${KC_WP_PASS_SERVICE}" "${wp_pass}"
      kc_linux_set "${KC_RELAY_PASS_SERVICE}" "${relay_pass}"
      ;;
    none)
      echo "ERROR: No secure credential store (macOS Keychain or Linux secret-tool)." >&2
      echo "  Debian/Ubuntu: sudo apt install libsecret-tools" >&2
      echo "  Or omit setup: credentials are prompted each run." >&2
      exit 1
      ;;
  esac
}

cred_reset() {
  case "${BACKEND}" in
    macos_keychain)
      kc_macos_delete "${KC_WP_USER_SERVICE}"
      kc_macos_delete "${KC_WP_PASS_SERVICE}"
      kc_macos_delete "${KC_RELAY_PASS_SERVICE}"
      ;;
    linux_secret_tool)
      kc_linux_delete "${KC_WP_USER_SERVICE}"
      kc_linux_delete "${KC_WP_PASS_SERVICE}"
      kc_linux_delete "${KC_RELAY_PASS_SERVICE}"
      ;;
    none)
      rm -f "${LEGACY_PLAIN_FILE}" "${LEGACY_ENC_FILE}"
      ;;
  esac
}

setup_credentials() {
  local wp_user wp_pass relay_pass

  read -r -p "WordPress username to save: " wp_user
  read -r -s -p "WordPress password to save: " wp_pass
  echo
  read -r -s -p "Relay SSH password to save: " relay_pass
  echo

  cred_set_all "${wp_user}" "${wp_pass}" "${relay_pass}"
  echo "Saved credentials via backend: ${BACKEND}"
}

cleanup() {
  ssh -S "${CONTROL_SOCK}" -O exit -p "${RELAY_SSH_PORT}" "${RELAY_USER}@${RELAY_HOST}" >/dev/null 2>&1 || true
  rm -f "${COOKIE_FILE}"
  if [[ -n "${ASKPASS_SCRIPT}" ]]; then
    rm -f "${ASKPASS_SCRIPT}"
  fi
}
trap cleanup EXIT

detect_backend

if [[ "${CMD}" == "setup" ]]; then
  setup_credentials
  exit 0
fi

if [[ "${CMD}" == "reset" ]]; then
  cred_reset
  echo "Reset saved credentials for backend: ${BACKEND}"
  exit 0
fi

WP_USER="$(cred_get "WP_USER" || true)"
WP_PASS="$(cred_get "WP_PASS" || true)"
RELAY_PASS="$(cred_get "RELAY_PASS" || true)"

if [[ -z "${WP_USER}" ]]; then
  read -r -p "WordPress username: " WP_USER
fi
if [[ -z "${WP_PASS}" ]]; then
  read -r -s -p "WordPress password: " WP_PASS
  echo
fi
if [[ -z "${RELAY_PASS}" ]]; then
  read -r -s -p "Relay SSH password (${RELAY_USER}@${RELAY_HOST}): " RELAY_PASS
  echo
fi

echo "[1/3] Opening tunnel to relay..."
if [[ -n "${RELAY_PASS}" ]]; then
  ASKPASS_SCRIPT="$(mktemp)"
  chmod 700 "${ASKPASS_SCRIPT}"
  cat > "${ASKPASS_SCRIPT}" <<EOF
#!/usr/bin/env bash
printf '%s\n' '${RELAY_PASS}'
EOF

  env SSH_ASKPASS="${ASKPASS_SCRIPT}" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-wpfetch}" ssh -fN -M -S "${CONTROL_SOCK}" \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 \
    -p "${RELAY_SSH_PORT}" \
    -L "127.0.0.1:${LOCAL_FORWARD_PORT}:127.0.0.1:${REMOTE_REVERSE_PORT}" \
    "${RELAY_USER}@${RELAY_HOST}" < /dev/null
else
  echo "SSH password for ${RELAY_USER}@${RELAY_HOST} will be prompted."
  ssh -fN -M -S "${CONTROL_SOCK}" \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  -p "${RELAY_SSH_PORT}" \
  -L "127.0.0.1:${LOCAL_FORWARD_PORT}:127.0.0.1:${REMOTE_REVERSE_PORT}" \
    "${RELAY_USER}@${RELAY_HOST}"
fi

BASE_URL="http://127.0.0.1:${LOCAL_FORWARD_PORT}${WP_BASE_PATH}"
LOGIN_URL="${BASE_URL}wp-login.php"
TARGET_URL="${BASE_URL}${PAGE_PATH}"

echo "Checking reverse tunnel endpoint..."
if ! curl -sS --max-time 5 -I "${BASE_URL}" >/dev/null; then
  echo "ERROR: Reverse tunnel endpoint is not reachable: ${BASE_URL}"
  echo "Likely causes:"
  echo "  1) Bastion PC reverse tunnel is down"
  echo "  2) REMOTE_REVERSE_PORT (${REMOTE_REVERSE_PORT}) mismatch"
  echo "  3) Bastion PC cannot reach target server (192.168.50.138:80)"
  echo "Check on bastion PC:"
  echo "  ssh -N -R 127.0.0.1:${REMOTE_REVERSE_PORT}:192.168.50.138:80 <relay_user>@<relay_host>"
  exit 1
fi

echo "[2/3] Logging in to WordPress..."
if ! curl -sS --fail \
  -c "${COOKIE_FILE}" -b "${COOKIE_FILE}" \
  "${LOGIN_URL}" >/dev/null; then
  echo "ERROR: Failed to initialize WordPress login page: ${LOGIN_URL}"
  exit 1
fi

LOGIN_EFFECTIVE_URL="$(curl -sS --fail --location \
  -c "${COOKIE_FILE}" -b "${COOKIE_FILE}" \
  -d "log=${WP_USER}&pwd=${WP_PASS}&rememberme=forever&wp-submit=Log+In&testcookie=1&redirect_to=${BASE_URL}" \
  -o /dev/null -w '%{url_effective}' \
  "${LOGIN_URL}")" || {
  echo "ERROR: WordPress login request failed: ${LOGIN_URL}"
  echo "If you see 'connection reset', the reverse tunnel path is unstable or disconnected."
  exit 1
}

if [[ "${LOGIN_EFFECTIVE_URL}" == *"wp-login.php"* ]] || ! grep -q "wordpress_logged_in" "${COOKIE_FILE}"; then
  echo "ERROR: WordPress login failed (still on login page or no auth cookie)."
  echo "Check saved credentials with: ./wpfetch_relay.sh setup (or: menglab setup)"
  exit 1
fi

COOKIE_HEADER="$(awk '
  BEGIN { first=1 }
  # curl cookie jar can store HttpOnly cookies as "#HttpOnly_<domain>".
  # Treat them as valid cookie lines instead of comments.
  ($0 ~ /^#HttpOnly_/ || $0 !~ /^#/) && NF >= 7 {
    if (!first) printf "; "
    printf "%s=%s", $6, $7
    first=0
  }
  END { print "" }
' "${COOKIE_FILE}")"

if [[ -z "${COOKIE_HEADER}" ]]; then
  echo "WARN: No cookies extracted from cookie jar. Preview may redirect to login."
fi

echo "[3/3] Fetching page..."
HTML="$(curl -sS --fail -c "${COOKIE_FILE}" -b "${COOKIE_FILE}" "${TARGET_URL}")"

TITLE="$(printf '%s' "${HTML}" | sed -n 's:.*<title>\(.*\)</title>.*:\1:p' | head -n1)"

if [[ -n "${TITLE}" ]]; then
  echo "Title: ${TITLE}"
else
  echo "Title not found. URL fetched: ${TARGET_URL}"
fi

if [[ "${PREVIEW_MODE}" -eq 1 ]]; then
  PREVIEW_PORT="${WPFETCH_PREVIEW_PORT:-18781}"
  if [[ -n "${PAGE_PATH}" ]]; then
    PREVIEW_PATH="/${PAGE_PATH}"
    PREVIEW_PATH="${PREVIEW_PATH#//}"
  else
    PREVIEW_PATH="${WP_BASE_PATH}"
  fi
  PY_PROXY_FILE="$(mktemp)"

  cat > "${PY_PROXY_FILE}" <<'PYEOF'
#!/usr/bin/env python3
import http.server
import os
import socketserver
import sys
import urllib.parse
import urllib.error
import urllib.request
import http.cookiejar

PREVIEW_PORT = int(os.environ["WPFETCH_PREVIEW_PORT"])
FORWARD_ORIGIN = os.environ["WPFETCH_FORWARD_ORIGIN"]
UPSTREAM_ORIGIN = os.environ["WPFETCH_UPSTREAM_ORIGIN"]
PREVIEW_ORIGIN = os.environ["WPFETCH_PREVIEW_ORIGIN"]
INITIAL_PATH = os.environ.get("WPFETCH_INITIAL_PATH", "")
COOKIE_FILE = os.environ["WPFETCH_COOKIE_FILE"]
EXTRA_COOKIE_HEADER = os.environ.get("WPFETCH_COOKIE_HEADER", "")
WP_USER = os.environ.get("WPFETCH_WP_USER", "")
WP_PASS = os.environ.get("WPFETCH_WP_PASS", "")
BASE_PATH = os.environ.get("WPFETCH_BASE_PATH", "/")

jar = http.cookiejar.MozillaCookieJar(COOKIE_FILE)
try:
    jar.load(ignore_discard=True, ignore_expires=True)
except Exception:
    pass

opener = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(jar),
    urllib.request.HTTPRedirectHandler(),
)

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}
LOGIN_PATH = urllib.parse.urljoin(BASE_PATH if BASE_PATH.endswith("/") else BASE_PATH + "/", "wp-login.php")


def rewrite_url(value: str) -> str:
    return value.replace(UPSTREAM_ORIGIN, PREVIEW_ORIGIN).replace(FORWARD_ORIGIN, PREVIEW_ORIGIN)


class Handler(http.server.BaseHTTPRequestHandler):
    def _perform_wp_login(self) -> bool:
        if not WP_USER or not WP_PASS:
            return False
        login_url = FORWARD_ORIGIN.rstrip("/") + LOGIN_PATH
        redirect_to = FORWARD_ORIGIN.rstrip("/") + (BASE_PATH if BASE_PATH.startswith("/") else "/" + BASE_PATH)
        # Initialize test cookie expected by WordPress.
        try:
            opener.open(urllib.request.Request(login_url, headers={"User-Agent": "wpfetch-preview"}, method="GET"), timeout=20).close()
        except Exception:
            pass
        payload = urllib.parse.urlencode(
            {
                "log": WP_USER,
                "pwd": WP_PASS,
                "rememberme": "forever",
                "wp-submit": "Log In",
                "testcookie": "1",
                "redirect_to": redirect_to,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            login_url,
            data=payload,
            headers={"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "wpfetch-preview"},
            method="POST",
        )
        try:
            with opener.open(req, timeout=20) as resp:
                final_url = resp.geturl() or ""
            if "wp-login.php" in final_url:
                return False
            try:
                jar.save(ignore_discard=True, ignore_expires=True)
            except Exception:
                pass
            return True
        except Exception:
            return False

    def _proxy(self, method: str):
        path = self.path or "/"
        if method in {"GET", "HEAD"} and path == "/":
            if INITIAL_PATH:
                path = "/" + INITIAL_PATH.lstrip("/")
            else:
                path = BASE_PATH if BASE_PATH.startswith("/") else "/" + BASE_PATH
        target = FORWARD_ORIGIN.rstrip("/") + path

        data = None
        if method in {"POST", "PUT", "PATCH", "DELETE"}:
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length > 0:
                data = self.rfile.read(length)

        forward_headers = {}
        for k, v in self.headers.items():
            kl = k.lower()
            if kl in HOP_BY_HOP or kl in {"host", "content-length"}:
                continue
            forward_headers[k] = v
        forward_headers.setdefault("User-Agent", "wpfetch-preview")
        # Keep upstream response uncompressed to simplify safe passthrough.
        forward_headers["Accept-Encoding"] = "identity"
        if EXTRA_COOKIE_HEADER:
            existing_cookie = forward_headers.get("Cookie", "")
            if existing_cookie:
                forward_headers["Cookie"] = existing_cookie + "; " + EXTRA_COOKIE_HEADER
            else:
                forward_headers["Cookie"] = EXTRA_COOKIE_HEADER

        autologin_tried = False
        while True:
            req = urllib.request.Request(target, data=data, headers=forward_headers, method=method)
            try:
                with opener.open(req, timeout=20) as resp:
                    status = resp.getcode()
                    headers = resp.headers
                    final_url = resp.geturl() or target
                    body = resp.read()
            except urllib.error.HTTPError as e:
                status = e.code
                headers = e.headers
                final_url = e.geturl() or target
                body = e.read()
            except Exception as e:
                msg = f"proxy error: {e}\n"
                self.send_response(502)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(msg.encode("utf-8"))))
                self.end_headers()
                self.wfile.write(msg.encode("utf-8"))
                return

            location = headers.get("Location", "")
            body_head = body[:4096].lower()
            needs_login = (
                ("wp-login.php" in path)
                or ("wp-login.php" in location)
                or ("wp-login.php" in final_url)
                or (b"name=\"log\"" in body_head and b"wp-submit" in body_head)
            )
            if (
                not autologin_tried
                and method in {"GET", "HEAD"}
                and needs_login
                and WP_USER
                and WP_PASS
                and self._perform_wp_login()
            ):
                autologin_tried = True
                continue
            break

        content_type = headers.get("Content-Type", "")
        if "text/html" in content_type.lower():
            # Avoid charset conversion (prevents mojibake). Replace only ASCII URL bytes.
            body = body.replace(UPSTREAM_ORIGIN.encode("utf-8"), PREVIEW_ORIGIN.encode("utf-8"))
            body = body.replace(FORWARD_ORIGIN.encode("utf-8"), PREVIEW_ORIGIN.encode("utf-8"))

        self.send_response(status)
        for k, v in headers.items():
            kl = k.lower()
            if kl in HOP_BY_HOP or kl in {"content-length"}:
                continue
            if kl == "location":
                v = rewrite_url(v)
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if method != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        self._proxy("GET")

    def do_HEAD(self):
        self._proxy("HEAD")

    def do_POST(self):
        self._proxy("POST")

    def log_message(self, format, *args):
        return


def main():
    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    with ReusableTCPServer(("127.0.0.1", PREVIEW_PORT), Handler) as httpd:
        print(f"Preview proxy listening: http://127.0.0.1:{PREVIEW_PORT}")
        httpd.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
PYEOF

  if ! has_cmd python3; then
    echo "ERROR: preview navigation requires python3."
    echo "Install python3 or run without preview mode."
    rm -f "${PY_PROXY_FILE}"
    exit 1
  fi

  PREVIEW_PORT="$(python3 - "${PREVIEW_PORT}" <<'PY'
import socket
import sys

start = int(sys.argv[1])
chosen = None
for p in range(start, start + 30):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", p))
        chosen = p
        break
    except OSError:
        pass
    finally:
        s.close()

if chosen is None:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    chosen = s.getsockname()[1]
    s.close()

print(chosen)
PY
)"
  PREVIEW_ORIGIN="http://127.0.0.1:${PREVIEW_PORT}"
  PREVIEW_URL="${PREVIEW_ORIGIN}${PREVIEW_PATH}"

  echo "Starting local preview proxy: ${PREVIEW_ORIGIN}"
  if has_cmd open; then
    open "${PREVIEW_URL}" >/dev/null 2>&1 || true
  elif has_cmd xdg-open; then
    xdg-open "${PREVIEW_URL}" >/dev/null 2>&1 || true
  elif has_cmd cmd.exe; then
    cmd.exe /C start "" "${PREVIEW_URL}" >/dev/null 2>&1 || true
  else
    echo "Open this URL manually: ${PREVIEW_URL}"
  fi

  export WPFETCH_PREVIEW_PORT="${PREVIEW_PORT}"
  export WPFETCH_FORWARD_ORIGIN="http://127.0.0.1:${LOCAL_FORWARD_PORT}"
  export WPFETCH_UPSTREAM_ORIGIN="${WP_UPSTREAM_ORIGIN}"
  export WPFETCH_PREVIEW_ORIGIN="${PREVIEW_ORIGIN}"
  export WPFETCH_INITIAL_PATH="${PAGE_PATH}"
  export WPFETCH_COOKIE_FILE="${COOKIE_FILE}"
  export WPFETCH_COOKIE_HEADER="${COOKIE_HEADER}"
  export WPFETCH_WP_USER="${WP_USER}"
  export WPFETCH_WP_PASS="${WP_PASS}"
  export WPFETCH_BASE_PATH="${WP_BASE_PATH}"

  echo "Preview mode with click navigation is running."
  echo "Press Ctrl+C to stop preview and close tunnel."
  python3 "${PY_PROXY_FILE}"
  rm -f "${PY_PROXY_FILE}"
fi
