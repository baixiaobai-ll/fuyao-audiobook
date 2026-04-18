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
  /path/to/Desktop/fuyao-backend/ \
  root@<ecs-ip>:/opt/fuyao-backend/current/
```

## 3. Create Env File

On the server:

```bash
mkdir -p /opt/fuyao-backend/shared
cp /opt/fuyao-backend/current/backend/.env.example /opt/fuyao-backend/current/backend/.env
```

Then fill in the one-click login fields and point `FUYAO_BACKEND_DB` at `/opt/fuyao-backend/shared/fuyao.sqlite3`.

Important for one-click login:

- `FUYAO_ONE_CLICK_PROVIDER` should be `aliyun`
- backend only needs `AccessKey ID` and `AccessKey Secret` to call `GetMobile`
- iOS SDK still needs the number-auth scheme info / SDK key from Aliyun console, but that is held on the client side

Server flow:

- iOS SDK performs one-click login and gets `accessToken`
- backend exchanges `accessToken` for phone number with `GetMobile`
- success then creates local session

## 4. Bootstrap

```bash
cd /opt/fuyao-backend/current
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
