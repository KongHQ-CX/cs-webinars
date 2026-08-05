# Konnect data plane certificates

`docker-compose.yml` runs Kong as a Konnect data plane and mounts two files from
this folder:

- `tls.crt` — the client **certificate** from Konnect
- `tls.key` — the client **private key** from Konnect

Get them from Konnect: **Gateway Manager → your control plane → + New Data Plane
Node → Docker**. Konnect generates the cert/key pair and shows the control-plane
and telemetry endpoints. Paste the certificate into `tls.crt`, the key into
`tls.key`, and put the endpoints in the repo's `.env` (`KONNECT_CP_*`,
`KONNECT_TP_*`).

These files are secrets — don't commit real ones.
