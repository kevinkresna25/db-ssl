#!/usr/bin/env bash
# init.sh - Initialize Postgres (alpine) with TLS
# - Generate a self-signed certificate if not present
# - Prepare data & cert directories with secure permissions
# - Configurable via environment variables
#
# Note: this script aims to be safe and easy to read.

set -o errexit
set -o pipefail
set -o nounset

# ===== Konfigurasi (override via ENV) =====
POSTGRES_UID="${POSTGRES_UID:-70}"
POSTGRES_GID="${POSTGRES_GID:-70}"
CERT_SUBJECT="${CERT_SUBJECT:-/CN=db}"
CERT_DAYS="${CERT_DAYS:-36500}"      # ~100 tahun
CERTS_DIR="${CERTS_DIR:-certs}"
DATA_DIR="${DATA_DIR:-data}"
CERT_PEM="$CERTS_DIR/cert.pem"
KEY_PEM="$CERTS_DIR/key.pem"
SAN="${CERT_SAN:-DNS:localhost,IP:127.0.0.1}"

# ===== Utilities =====
info() { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[OK]\033[0m   %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR]\033[0m  %s\n" "$*" >&2; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Command '$1' not found. Please install it."; exit 1
  fi
}

run_maybe_sudo() {
  # Use sudo when not running as root; useful for host development.
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

on_error() {
  local rc=${1:-$?}
  err "Script exited with code: $rc"
  exit "$rc"
}
trap 'on_error $?' ERR

# ===== Dependency checks =====
info "Checking dependencies..."
need_cmd openssl
need_cmd mkdir
need_cmd chown
need_cmd chmod
ok "Dependencies OK"

# ===== Bantuan / usage =====
show_help() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

Environment overrides:
  POSTGRES_UID, POSTGRES_GID   - numeric UID/GID for file ownership (default: 70)
  CERT_SUBJECT                 - certificate subject (default: /CN=db)
  CERT_DAYS                    - certificate validity days (default: 36500)
  CERTS_DIR, DATA_DIR          - directories for certs & data (default: certs, data)
  CERT_SAN                     - additional subjectAltName (default: DNS:localhost,IP:127.0.0.1)

This script will create directories if missing, generate a self-signed
certificate if absent, and set secure permissions and ownership.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  show_help
  exit 0
fi

# ===== Buat folder dengan permission aman =====
info "Preparing directories: '$CERTS_DIR' and '$DATA_DIR'"
mkdir -p -- "$CERTS_DIR"
mkdir -p -- "$DATA_DIR"

# Set secure base permissions (data: owner read/write/execute only)
chmod 700 "$DATA_DIR"
chmod 755 "$CERTS_DIR" || true
ok "Directories ready"

# ===== Generate cert =====
if [ -f "$CERT_PEM" ] && [ -f "$KEY_PEM" ]; then
  ok "Sertifikat sudah ada: $CERT_PEM & $KEY_PEM (skip generate)"
else
  info "Creating self-signed certificate (subject: '$CERT_SUBJECT', SAN: '$SAN')"
  # Ensure temporary files are created with secure permissions
  umask 077
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
    -keyout "$KEY_PEM" -out "$CERT_PEM" \
    -days "$CERT_DAYS" -subj "$CERT_SUBJECT" -addext "subjectAltName=$SAN"

  # Ensure openssl actually created non-empty files
  if [ ! -s "$KEY_PEM" ] || [ ! -s "$CERT_PEM" ]; then
    err "Failed to create certificate or key (empty file)."; exit 1
  fi

  ok "Certificate and key created"
fi

# ===== Set ownership & permission =====
info "Setting ownership & permissions for certs & data"

# Set permissions first, then ownership (safer when moving between users)
chmod 644 "$CERT_PEM"
chmod 600 "$KEY_PEM"
run_maybe_sudo chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "$CERTS_DIR"

run_maybe_sudo chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "$DATA_DIR"
chmod 700 "$DATA_DIR"

ok "Initialization complete."


cat <<'TIP'

Tips:
- For the postgres:alpine image the default 'postgres' UID is 70.
  If you switch to a Debian-based image (e.g. postgres:16), the UID is often 999.
  Run with: POSTGRES_UID=999 POSTGRES_GID=999 ./init.sh

- Example docker-compose bind mounts:
    ./data/db  -> /var/lib/postgresql
    ./certs/cert.pem -> /var/lib/postgresql/cert.pem:ro
    ./certs/key.pem  -> /var/lib/postgresql/key.pem:ro
  And in postgresql.conf:
    ssl = on
    ssl_cert_file = 'cert.pem'
    ssl_key_file  = 'key.pem'

- For Npgsql/.NET development, add:
    SSL Mode=Require;Trust Server Certificate=true
  to the connection string if you want to bypass validation for a self-signed certificate.

TIP
