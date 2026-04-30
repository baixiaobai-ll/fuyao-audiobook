# Fuyao Backend Deployment

## Goal

Deploy the backend to an Aliyun ECS server for controlled integration testing before ICP filing is finished.

Current recommendation:

- Run the backend on ECS directly
- Bind to `0.0.0.0`
- Access it with the ECS public IP and port, or via SSH tunnel / private network
- Limit access by security group source IP while the service is still in controlled testing

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
  /path/to/Desktop/fuyao-backend/ \
  root@<ecs-ip>:/opt/fuyao-backend/current/
```

## 3. Create Env File

On the server:

```bash
mkdir -p /opt/fuyao-backend/shared
cp /opt/fuyao-backend/current/backend/.env.example /opt/fuyao-backend/shared/backend.env
nano /opt/fuyao-backend/shared/backend.env
```

Then fill in the one-click login and SMS verification fields and point `FUYAO_BACKEND_DB` at `/opt/fuyao-backend/shared/fuyao.sqlite3`.

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
python3 -m backend.main seed-code [REMOVED_ACTIVATION_CODE] --batch-name initial
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
curl http://<ecs-public-ip>:8787/healthz
```

If ICP is not finished yet, prefer one of these controlled methods:

- security group allowlist only your office/home IP
- SSH tunnel to the ECS host
- VPN / private network access

## 7. Notes

- No formal domain is required at this stage.
- You can test iOS against `http://<ecs-public-ip>:8787` first, or through a tunnel/proxy if needed.
- If later adding Nginx, keep the backend process on an internal port like `8787`.

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
