# Postgres (one-way TLS)

## Overview

This folder contains a small initialization helper script (`init.sh`) intended
for development and lightweight production testing of PostgreSQL with TLS.

The script performs the following tasks:

- Creates the `certs` and `data` directories (configurable via environment
  variables).
- Generates a self-signed X.509 certificate and private key when they are
  missing.
- Applies secure permissions to the data directory and certificate files.
- Sets ownership of created files to the configured UID/GID (so they can be
  used inside containers).

## Location

- Script: `postgres/one-way/init.sh`
- Default certs dir: `postgres/one-way/certs`
- Default data dir: `postgres/one-way/data`

## Quick start (local)

1. Make the script executable and run it locally (you may need `sudo` to set
   ownership when running as non-root):

```bash
cd postgres/one-way
chmod +x init.sh
./init.sh
```

2. The script will create `certs/cert.pem` and `certs/key.pem` if they do not
   exist and will set permissions so that `cert.pem` is world-readable and
   `key.pem` is readable only by the owner.

## Environment variables (overrides)

- `POSTGRES_UID` (default: `70`) — numeric UID used for file ownership.
- `POSTGRES_GID` (default: `70`) — numeric GID used for file ownership.
- `CERT_SUBJECT` (default: `/CN=db`) — subject used when creating the
  self-signed certificate.
- `CERT_DAYS` (default: `36500`) — certificate validity period in days.
- `CERTS_DIR` (default: `certs`) — path to certificate directory.
- `DATA_DIR` (default: `data`) — path to Postgres data directory.
- `CERT_SAN` (default: `DNS:localhost,IP:127.0.0.1`) — subjectAltName value added
  to the certificate.

## Docker / docker-compose example

When running PostgreSQL in a container, bind the generated files into the
container and point Postgres to the certificate files. A minimal example in
`docker-compose.yml`:

```yaml
services:
  db:
    image: postgres:alpine
    volumes:
      - ./data:/var/lib/postgresql/data
      - ./certs/cert.pem:/var/lib/postgresql/cert.pem:ro
      - ./certs/key.pem:/var/lib/postgresql/key.pem:ro
    environment:
      POSTGRES_PASSWORD: example
    command: ["-c", "ssl=on", "-c", "ssl_cert_file=cert.pem", "-c", "ssl_key_file=key.pem"]
    user: "70:70" # optional: run as UID:GID 70 (postgres:alpine)

# If you run a Debian-based Postgres image, the postgres UID/GID is commonly 999.
# You can override ownership using: POSTGRES_UID=999 POSTGRES_GID=999 ./init.sh
```

## PostgreSQL configuration

In your `postgresql.conf` you should enable TLS and reference the certificate
and key file names (paths inside the container):

```conf
ssl = on
ssl_cert_file = 'cert.pem'
ssl_key_file = 'key.pem'
```

## Security notes and best practices

- Do not commit private keys or certificates to source control. Add
  `certs/` to `.gitignore` if you plan to keep generated artifacts locally.
- The provided `init.sh` creates a self-signed certificate intended for
  development and testing. For production deployments use certificates from a
  trusted CA (or an internal PKI) and properly protect private keys.
- Ensure `key.pem` has restrictive permissions (owner-only) and is mounted
  read-only into containers.
- Consider using a proper secrets manager or Docker secrets for private keys
  in production environments.

## Troubleshooting

- If Postgres fails to start due to SSL errors, check the container's log
  messages, verify the mounted paths, and ensure `ssl_cert_file` and
  `ssl_key_file` values match the mounted filenames.
- To regenerate certificates, remove the `certs/cert.pem` and
  `certs/key.pem` files and re-run `./init.sh`.

## Linting and quality

- For additional safety, run `shellcheck` against `init.sh` and address any
  recommendations (not included in this repo by default).

## Reference

This README and the `init.sh` behavior were informed by the following
reference:

- "Setting up TLS connection for containerized PostgreSQL database" by
  whchi — https://dev.to/whchi/setting-up-tls-connection-for-containerized-postgresql-database-1kmh
