# Current deployment: free demo

The user selected Render Free. This service has no persistent disk; accounts, messages and uploads can be lost on restart/redeploy. Do not store important data. The instance can sleep when idle. The previous paid storage instructions below describe an optional future upgrade, not an active subscription.

# Render deployment

This blueprint defines one Docker web service with a persistent 1 GB disk. Both the Starter service and disk incur charges; review Render's quoted price before provisioning. No local accounts, messages or uploads are included in Git. A new deployment starts with an empty database.

Create a Blueprint from this repository using render.yaml. Use /health to verify version 2.0.0 and storage sqlite. Root directory is backend. Runtime listens on Render's PORT and 0.0.0.0. Data and uploads reside under /app/data on the persistent disk; run one instance only. Free ephemeral storage is unsuitable for preserving this SQLite application.

STU_ADMIN_EMAILS is an operator-only setting. If the admin account is created after initial startup, restart the service after account creation so the configured admin email receives its role. Do not put credentials or service account JSON into Git. Mail defaults to private on-disk outbox and does not deliver email. Set SMTP/FCM separately when available.

Use the assigned HTTPS API URL to build or configure the Android client; the old APK defaults to the local server. Existing local data is not transferred automatically. Export and restore it privately with the server stopped if migration is explicitly desired. Use the included consistent SQLite backup tool for regular backups and export backup directories off the service.

References: https://render.com/docs/blueprint-spec and https://render.com/docs/disks

