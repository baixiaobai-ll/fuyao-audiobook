# Fuyao Backend Deployment

## Goal

Deploy the backend to an Aliyun ECS server for controlled integration testing before ICP filing is finished.

Current recommendation:

- Run the backend on ECS directly
- Bind the Python process to `127.0.0.1:8787`
- Expose only Nginx on public ports `80/443`
- Keep ECS security-group access to `8787` closed

## 1. Prepare Server

Assume the project is placed at `/opt/fuyao-backend/current`.

Required runtime:

- Linux
- Python 3.9+
- outbound HTTPS access to `https://dypnsapi.aliyuncs.com`

Suggested directories:

- code: `/opt/fuyao-backend/current`
- shared db/env/logs: `/opt/fuyao-backend/shared`

## 2. Upload Code

Example:

```bash
rsync -av --delete \
  --exclude 'backend/.env' \
  --exclude '.DS_Store' \
  <local-repo-path>/ \
  <deploy-user>@<ecs-ip>:/opt/fuyao-backend/current/
```

## 3. Create Env File

On the server:

```bash
mkdir -p /opt/fuyao-backend/shared
cp /opt/fuyao-backend/current/backend/.env.example /opt/fuyao-backend/shared/backend.env
nano /opt/fuyao-backend/shared/backend.env
```

Then fill in the one-click login and SMS verification fields and point `FUYAO_BACKEND_DB` at `/opt/fuyao-backend/shared/fuyao.sqlite3`.

Keep `FUYAO_ENVIRONMENT=production`. The backend deliberately refuses to start with mock authentication providers in staging or production.

Production runtime configuration should live in `/opt/fuyao-backend/shared/backend.env`, not in `/opt/fuyao-backend/current/backend/.env`. This keeps real ECS credentials outside the code directory, so later `rsync --delete` deploys will not overwrite Aliyun SMS / one-click login settings with local mock values.

For the current product rule, keep:

- `FUYAO_DAILY_QUOTA_ENABLED=false`
- `FUYAO_DAILY_CHAPTER_LIMIT=10` only as a legacy compatibility value; it is no longer the main unlock rule

Important for one-click login:

- `FUYAO_ONE_CLICK_PROVIDER` should be `aliyun`
- backend only needs `AccessKey ID` and `AccessKey Secret` to call `GetMobile`
- iOS SDK still needs the number-auth scheme info / SDK key from Aliyun console, but that is held on the client side

Important for SMS fallback login:

- `FUYAO_SMS_PROVIDER` should be `aliyun`
- `FUYAO_ALIYUN_SMS_SIGN_NAME` is required
- `FUYAO_ALIYUN_SMS_TEMPLATE_CODE` is required
- the Aliyun SMS verification template should include the verification code variable, usually `${code}`
- if the template also renders validity minutes, keep `FUYAO_ALIYUN_SMS_TEMPLATE_PARAM_MINUTES_KEY` aligned with the template variable, usually `min`

Server flow:

- iOS SDK performs one-click login and gets `accessToken`
- backend exchanges `accessToken` for phone number with `GetMobile`
- success then creates local session

SMS fallback flow:

- backend sends code with `SendSmsVerifyCode`
- backend verifies code with `CheckSmsVerifyCode`
- success then creates local session in the same user/session tables

Legacy usage compatibility:

- `POST /v1/usage/consume` and `POST /v1/usage/rollback` are still deployed
- with `FUYAO_DAILY_QUOTA_ENABLED=false`, activated users are no longer blocked by daily quota
- auth/status payloads still contain legacy quota fields, but clients should key product expression off `permissions` and `entitlement.dailyQuotaEnabled`

## 4. Bootstrap

```bash
cd /opt/fuyao-backend/current
export FUYAO_ENV_FILE=/opt/fuyao-backend/shared/backend.env
./backend/scripts/bootstrap_server.sh
python3 -m backend.main generate-codes --count 20 --batch-name beta-001
```

## 5. Start Service

Temporary foreground start:

```bash
cd /opt/fuyao-backend/current
./backend/scripts/start_server.sh
```

Recommended long-running mode:

```bash
cd /opt/fuyao-backend/current
sudo ./backend/scripts/install_systemd.sh
sudo systemctl status fuyao-backend
```

## 6. Verify

```bash
curl http://127.0.0.1:8787/healthz
```

For controlled testing before HTTPS is ready, use an SSH tunnel or a private network. Do not expose port `8787` directly to the internet.

## 7. Notes

- No formal domain is required at this stage.
- Test through a tunnel or reverse proxy if needed.
- Keep the backend process on loopback and an internal port such as `8787`.

## 8. HTTPS Domain Setup

TestFlight builds should use HTTPS instead of the ECS public IP and development ATS exceptions.

Target endpoint:

- `https://api.fuyao.site`
- Backend process: `127.0.0.1:8787`
- Nginx: public `80/443` reverse proxy

### 8.1 DNS

In the domain console, add an A record:

| Type | Host | Value |
| --- | --- | --- |
| A | `api` | `<ecs-public-ip>` |

Wait until DNS resolves:

```bash
dig +short api.fuyao.site
```

The result should be the ECS public IP.

### 8.2 Install Nginx and Certbot

On ECS:

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

Make sure the cloud security group allows inbound `80` and `443`. Port `8787` can be restricted after Nginx is working.

### 8.3 Configure Nginx

Copy the example config:

```bash
sudo cp /opt/fuyao-backend/current/backend/deploy/nginx-api.fuyao.site.conf.example \
  /etc/nginx/sites-available/api.fuyao.site

sudo ln -sf /etc/nginx/sites-available/api.fuyao.site \
  /etc/nginx/sites-enabled/api.fuyao.site
```

Before the certificate exists, comment out the HTTPS `server` block or use certbot's automatic Nginx installer. The simplest path is:

```bash
sudo nginx -t
sudo certbot --nginx -d api.fuyao.site
sudo nginx -t
sudo systemctl reload nginx
```

### 8.4 Verify HTTPS

```bash
curl https://api.fuyao.site/healthz
```

Expected response includes:

- `"ok": true`
- `"smsProvider": "aliyun"`
- `"oneClickProvider": "aliyun"`

After this passes, switch the iOS app config:

- `AUTH_API_BASE_URL=https://api.fuyao.site`
- remove development-only ATS arbitrary loads

## 9. Public Legal Pages

TestFlight and App Store review need public URLs for the user service agreement and privacy policy.

Target URLs:

- `https://fuyao.site/legal/terms`
- `https://fuyao.site/legal/privacy`

These pages are static HTML files in:

- `/opt/fuyao-backend/current/backend/static/legal/terms.html`
- `/opt/fuyao-backend/current/backend/static/legal/privacy.html`

### 9.1 DNS

In the domain console, add A records:

| Type | Host | Value |
| --- | --- | --- |
| A | `@` | `<ecs-public-ip>` |
| A | `www` | `<ecs-public-ip>` |

Wait until DNS resolves:

```bash
dig +short fuyao.site
dig +short www.fuyao.site
```

Both should resolve to the ECS public IP.

### 9.2 Configure Nginx

The final HTTPS config is tracked at:

```bash
/opt/fuyao-backend/current/backend/deploy/nginx-fuyao.site.conf.example
```

Because the HTTPS block references a certificate that does not exist before the first certbot run, the safest first-time setup is:

```bash
sudo tee /etc/nginx/sites-available/fuyao.site > /dev/null <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name fuyao.site www.fuyao.site;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        root /opt/fuyao-backend/current/backend/static;
        try_files $uri $uri.html =404;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/fuyao.site \
  /etc/nginx/sites-enabled/fuyao.site

sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d fuyao.site -d www.fuyao.site
sudo nginx -t
sudo systemctl reload nginx
```

After certbot succeeds, compare `/etc/nginx/sites-available/fuyao.site` with `backend/deploy/nginx-fuyao.site.conf.example` and keep the `/legal/` alias:

```nginx
location /legal/ {
    alias /opt/fuyao-backend/current/backend/static/legal/;
    try_files $uri $uri.html =404;
}
```

### 9.3 Verify

```bash
curl -I https://fuyao.site/legal/privacy
curl -I https://fuyao.site/legal/terms
curl https://fuyao.site/legal/privacy
curl https://fuyao.site/legal/terms
```

Expected:

- HTTPS returns `200`
- HTTP redirects to HTTPS after certbot config is active
- the pages render Chinese legal text

The iOS login agreement links are expected to point to these same public URLs.
