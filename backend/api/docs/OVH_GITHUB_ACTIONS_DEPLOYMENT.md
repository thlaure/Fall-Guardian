# Deploy the API to an OVH VPS with GitHub Actions

This is the complete setup and operating guide for a family real-world test.
It does not make the product medically certified or ready for public launch.

## How deployment works

A change under `backend/api/` merged into `main` starts
`.github/workflows/api-deploy.yaml`.

1. GitHub builds a production image and pushes it to GHCR.
2. After `production` environment approval, GitHub logs into the VPS.
3. The VPS pulls that exact commit image, runs migrations, and starts the API,
   Messenger worker, and alert reconciler.
4. It retries the API `/health` endpoint for up to 180 seconds. Workers do not
   need individual health checks to make the deployment succeed.

PostgreSQL, Redis, and all application secrets remain on the VPS.

## Names used below

Replace these examples: `203.0.113.10` is the VPS IPv4, `debian` is its
administrator account, `deploy` is the deployment-only account, and
`api.example.fr` is the public API hostname.

Never put a private key, password, or Firebase service-account JSON in Git,
GitHub issues, PRs, or a shared terminal.

## 1. Choose a public HTTPS hostname

Preferred: create this DNS record at the company managing your domain:

| Type | Name | Value |
| --- | --- | --- |
| `A` | `api` | VPS public IPv4 |

For `example.fr`, configure:

```dotenv
SERVER_NAME=https://api.example.fr
```

For a temporary family test, OVH's assigned hostname also works if it resolves
to the VPS, for example:

```dotenv
SERVER_NAME=https://vps-<identifier>.vps.ovh.net
```

Do not use an IP as `SERVER_NAME`. Caddy can obtain a trusted HTTPS certificate
only for a DNS name that resolves to the VPS while ports 80 and 443 are open.

## 2. Create the dedicated SSH account

### On the Mac: create a key pair

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/fall_guardian_github_actions -C "github-actions-fall-guardian"
pbcopy < ~/.ssh/fall_guardian_github_actions.pub
```

`ssh-keygen` creates the key pair. `ed25519` is the modern key algorithm;
`-a 100` makes attacks on the local key harder. The file without `.pub` is the
private key and must go only into GitHub. `pbcopy` copies the public key, which
is safe to paste on the VPS. Leave the passphrase empty because Actions cannot
enter one.

### On the VPS: create `deploy`

Connect as the existing administrator:

```bash
ssh debian@203.0.113.10
```

Then run:

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
sudo nano /home/deploy/.ssh/authorized_keys
```

`adduser --disabled-password` prevents password login for `deploy`.
`usermod -aG docker` allows Docker deployment; Docker access is powerful, so
do not use this account for anything else. `install -d` creates the protected
SSH folder. In `nano`, paste the public key, save with `Ctrl+O`, Enter, then
exit with `Ctrl+X`.

```bash
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo install -d -m 750 -o deploy -g deploy /opt/fall-guardian-api
```

`chown` assigns the key file to `deploy`; `chmod 600` makes it private. The
last command creates the folder where GitHub will upload `compose.prod.yaml`.

Test from the Mac:

```bash
ssh -i ~/.ssh/fall_guardian_github_actions deploy@203.0.113.10
```

`-i` selects the dedicated key. It must work without a password. `deploy`
intentionally has no `sudo` access.

## 3. Permit GHCR image pulls

Create a GitHub **classic personal access token** with only `read:packages`:
GitHub profile → **Settings** → **Developer settings** → **Personal access
tokens** → **Tokens (classic)**.

On the VPS, as `debian`:

```bash
sudo -iu deploy
read -s -p "GitHub token: " GHCR_TOKEN; echo
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u thlaure --password-stdin
unset GHCR_TOKEN
chmod 700 /home/deploy/.docker
chmod 600 /home/deploy/.docker/config.json
```

`sudo -iu deploy` opens a deployment-user shell without needing a deploy
password. `read -s` hides typed token characters. `docker login` saves GHCR
read access; expect `Login Succeeded`. `unset` removes only the temporary
shell variable, not Docker's saved login. The two `chmod` commands restrict
that saved credential to `deploy`.

## 4. Create the VPS secret file

Return to the administrator shell with `exit`, then run:

```bash
sudo install -d -m 750 -o root -g deploy /etc/fall-guardian
sudo install -m 640 -o root -g deploy /dev/null /etc/fall-guardian/api.env
sudo nano /etc/fall-guardian/api.env
```

The directory is owned by `root`; the `deploy` group can read the file. Mode
`640` prevents other accounts from reading it. `nano` opens the file as the
administrator. This file must exist only on the VPS.

Generate three independent values, running this command three times:

```bash
openssl rand -hex 32
```

It prints 64 random characters. Use a different result for the database
password, `APP_SECRET`, and `DEVICE_TOKEN_HASH_SECRET`.

Set `/etc/fall-guardian/api.env` to this form, replacing every placeholder:

```dotenv
SERVER_NAME=https://api.example.fr
TRUSTED_PROXIES=127.0.0.1
CORS_ALLOW_ORIGIN=^$

POSTGRES_DB=fall_guardian
POSTGRES_USER=fall_guardian
POSTGRES_PASSWORD=your-random-database-secret
POSTGRES_VERSION=16

APP_SECRET=your-second-random-secret
DEVICE_TOKEN_HASH_SECRET=your-third-random-secret

PUSH_PROVIDER=fcm
FCM_PROJECT_ID=your-firebase-project-id
FCM_SERVICE_ACCOUNT_JSON={"complete":"one-line-service-account-json"}
```

`CORS_ALLOW_ORIGIN=^$` blocks browsers; native iOS/Android apps do not need
CORS. Do not change `DEVICE_TOKEN_HASH_SECRET` without a token-rotation plan:
existing device tokens would stop working. Do not add `API_IMAGE`; GitHub
Actions supplies the exact image for each deployment.

## 5. Configure FCM for real alerts

In Firebase Console, open the project used by the mobile apps:

1. Gear icon → **Project settings** → **General** → copy **Project ID** to
   `FCM_PROJECT_ID`.
2. **Service accounts** → **Generate new private key** → download the JSON.

On the Mac:

```bash
jq -c . ~/Downloads/service-account-file.json | pbcopy
```

`jq -c` turns the JSON into one line; `pbcopy` avoids displaying the secret.
Paste it after `FCM_SERVICE_ACCOUNT_JSON=`. Do not use Android
`google-services.json`, iOS `GoogleService-Info.plist`, a web API key, or a
legacy FCM server key. Delete the downloaded JSON after securely storing it.

## 6. Configure GitHub Actions secrets

GitHub repository → **Settings** → **Environments** → `production`.
Enable **Required reviewers** to require your approval before every VPS update.

Create these **Environment secrets** (not variables):

| Secret | Value |
| --- | --- |
| `OVH_SSH_HOST` | VPS public IP or hostname |
| `OVH_SSH_USER` | `deploy` |
| `OVH_SSH_PRIVATE_KEY` | complete private-key file content |
| `OVH_KNOWN_HOSTS` | verified `ssh-keyscan -H <VPS_IP>` output |
| `OVH_DEPLOY_PATH` | `/opt/fall-guardian-api` |
| `OVH_ENV_FILE` | `/etc/fall-guardian/api.env` |

The workflow reads `secrets.OVH_*`; variables with the same names are ignored.
Get host keys from the Mac:

```bash
ssh-keyscan -H 203.0.113.10
```

This retrieves SSH public keys. Verify the fingerprint with OVH console/KVM or
another trusted source before storing it: `ssh-keyscan` alone does not prove
server identity.

Copy the private key only for the GitHub secret:

```bash
pbcopy < ~/.ssh/fall_guardian_github_actions
```

Never put this key on the VPS or in Git.

## 7. Configure the firewall

Keep the current SSH session open. On the VPS as administrator:

```bash
sudo apt update
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw enable
sudo ufw status numbered
```

The first two commands install UFW. Allow SSH before enabling it so you do not
lose access. Port 80 issues/renews HTTPS certificates; 443 TCP serves HTTPS;
443 UDP enables HTTP/3. `status numbered` confirms active rules. Never open
PostgreSQL or Redis: production Compose exposes neither.

## 8. First and later deployments

Merge a green PR into `main`. The **Deploy API** workflow starts automatically
(or may be run from GitHub **Actions**). If protected, after the build completes
click **Review deployments** → select `production` → **Approve and deploy**.

The job pulls the image, migrates, starts services, then retries the API health
endpoint for up to 180 seconds. Then
verify:

```text
https://api.example.fr/health
```

It returns a small health JSON response, not a website. Before the first
deployment, `ERR_CONNECTION_REFUSED` is normal because nothing is listening on
443 yet.

Every later release is: CI-green PR → merge to `main` → approve `production`
→ check `/health` and a real FCM notification. The image tag is the commit SHA,
so a mutable `latest` image is never deployed.

## Troubleshooting and operations

| Symptom | Check |
| --- | --- |
| SSH job fails | Six `OVH_*` secrets, public key, and known-host keys |
| Image pull denied | GHCR login as `deploy`, token has `read:packages` |
| Certificate fails | `SERVER_NAME` DNS resolves to VPS; ports 80/443 open |
| Workflow waits | Approve the `production` environment |
| Alerts fail | Same Firebase project on app/server; service-account JSON |

On the VPS, show state and API logs without printing secrets:

```bash
sudo -iu deploy
cd /opt/fall-guardian-api
docker compose --env-file /etc/fall-guardian/api.env -f compose.prod.yaml ps
docker compose --env-file /etc/fall-guardian/api.env -f compose.prod.yaml logs --tail=100 app
```

`ps` shows service status. `logs --tail=100 app` shows the last 100 API log
lines.

Enable OVH backups, test PostgreSQL restore before relying on an emergency
flow, monitor `/health`, 5xx errors, FCM failures, and failed Messenger
messages. Update the OS, Docker, and API dependencies through CI-validated PRs.
