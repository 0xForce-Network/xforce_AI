#!/usr/bin/env bash
set -Eeuo pipefail

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/fake-bin" "$tmp/state" "$tmp/caddy" "$tmp/etc-caddy"

cat > "$tmp/fake-bin/cloudflared" <<'EOF_CLOUDFLARED'
#!/usr/bin/env bash
printf 'cloudflared %s\n' "$*" >> "${XFORCE_FAKE_CLOUDFLARED_LOG:?}"
case "$*" in
  *'tunnel --url'*)
    printf 'Your quick Tunnel has been created! Visit https://fixture.trycloudflare.com\n'
    ;;
  *'tunnel run --token'*)
    printf 'named tunnel running\n'
    ;;
esac
EOF_CLOUDFLARED
chmod 0755 "$tmp/fake-bin/cloudflared"
: > "$tmp/cloudflared.log"

PYTHONPATH=/opt/portal-aio:${PYTHONPATH:-} \
XFORCE_CADDY_ROUTES="${XFORCE_CADDY_ROUTES:-/etc/xforce-ai/caddy/routes.yaml}" \
XFORCE_CADDY_AUTH="${XFORCE_CADDY_AUTH:-/etc/xforce-ai/caddy/auth.yaml}" \
XFORCE_CADDY_GENERATED_CONFIG="$tmp/caddy/Caddyfile.generated" \
AUTH_EXCLUDE='/public,route:health,port:18080' \
/opt/xforce-ai/bin/xforce-caddy render --json | grep -q 'example-service'

grep -q 'forward_auth 127.0.0.1:8080' "$tmp/caddy/Caddyfile.generated"
grep -q 'route_id=health' "$tmp/caddy/Caddyfile.generated"
grep -q 'AUTH_EXCLUDE=/public,route:health,port:18080' "$tmp/caddy/Caddyfile.generated"

if command -v caddy >/dev/null 2>&1; then
  caddy validate --config "$tmp/caddy/Caddyfile.generated" --adapter caddyfile >/dev/null
fi

PYTHONPATH=/opt/portal-aio:${PYTHONPATH:-} python3 - <<'PY'
from caddy_manager.auth import AuthConfig, sign_cookie, verify_cookie, token_matches
cfg = AuthConfig(token="abc", cookie_secret="secret")
cookie = sign_cookie("abc", "secret", now=100)
assert verify_cookie(cookie, "abc", "secret", now=101)
assert token_matches("abc", cfg)
PY

XFORCE_FAKE_CLOUDFLARED_LOG="$tmp/cloudflared.log" \
XFORCE_CLOUDFLARED_BIN="$tmp/fake-bin/cloudflared" \
XFORCE_TUNNEL_STATE_DIR="$tmp/state" \
/opt/xforce-ai/bin/xforce-tunnel quick --dry-run --json | grep -q 'cloudflared'
grep -q 'dry_run' "$tmp/state/state.json"

CF_TUNNEL_TOKEN='super-secret-token' \
XFORCE_FAKE_CLOUDFLARED_LOG="$tmp/cloudflared.log" \
XFORCE_CLOUDFLARED_BIN="$tmp/fake-bin/cloudflared" \
XFORCE_TUNNEL_STATE_DIR="$tmp/state" \
/opt/xforce-ai/bin/xforce-tunnel named --dry-run --json | grep -q 'MASKED'
if grep -R 'super-secret-token' "$tmp/state"; then
  echo 'CF_TUNNEL_TOKEN leaked into state' >&2
  exit 1
fi

/opt/xforce-ai/bin/xforce-tunnel status --state-dir "$tmp/state" --json | grep -q 'named'

PYTHONPATH=/opt/portal-aio:${PYTHONPATH:-} python3 - <<'PY'
from caddy_manager.routes import load_routes
from pathlib import Path
routes = load_routes(Path('/etc/xforce-ai/caddy/routes.yaml'))
ids = {route.id for route in routes}
assert {'portal', 'portal-api', 'health', 'example-service'} <= ids
PY

grep -q 'name: caddy' /etc/xforce-ai/services.yaml
grep -q 'protected: true' /etc/xforce-ai/services.yaml
grep -q 'name: cloudflared' /etc/xforce-ai/services.yaml

echo "xforce_AI F010 caddy/tunnel smoke test passed"
