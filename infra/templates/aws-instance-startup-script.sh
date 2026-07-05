#!/bin/bash
# Script to install Cloudflare Tunnel/SSH and Vault
set -euo pipefail

# The OS is updated
sudo apt update -y && sudo apt upgrade -yq
sudo apt install -y software-properties-common jq unzip curl

### Install AWS CLI v2 (needed to fetch the tunnel credentials secret)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install

### Create unix users for vault_ssh_users
%{ for user in vault_ssh_users }
sudo adduser --gecos "" --force-badname --disabled-password ${split("@", user)[0]}
usermod -aG sudo ${split("@", user)[0]}
%{ endfor }

# Allow running sudo without a password
cat <<EOF >> /etc/sudoers
%{ for user in vault_ssh_users }
${split("@", user)[0]} ALL = (ALL) NOPASSWD: ALL
%{ endfor }
EOF

# Create ca.pub
cat <<EOF > /etc/ssh/ca.pub
${vault_ssh_ca_key}
EOF

# Add ca.pub as TrustedUserCAKeys
cat <<EOF >> /etc/ssh/sshd_config
PubkeyAuthentication yes
TrustedUserCAKeys /etc/ssh/ca.pub
EOF

# Restart ssh to apply changes
sudo systemctl restart ssh

### Install and configure Cloudflare Tunnel

# cloudflared is fetched from the official GitHub releases (replaces the old
# bin.equinox.io download link, which has since been retired).
curl -fsSL -o /tmp/cloudflared.deb \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
sudo dpkg -i /tmp/cloudflared.deb

# Create /etc/cloudflared and fetch cloudflare tunnel credentials from AWS Secrets Manager
mkdir -p /etc/cloudflared
aws secretsmanager get-secret-value \
  --region "${aws_region}" \
  --secret-id "${tunnel_secret_name}" \
  --query SecretString --output text > /etc/cloudflared/creds.json

# Create cloudflared config
# Ingress rules are managed remotely (config_src = "cloudflare" on the tunnel
# resource), so the local config only needs the tunnel ID and credentials.
cat <<EOF > /etc/cloudflared/config.yml
tunnel: ${cf_tunnel_id}
credentials-file: /etc/cloudflared/creds.json
logfile: /var/log/cloudflared.log
loglevel: info
EOF

# Install cloudflared as a systemd service
sudo cloudflared service install
sudo service cloudflared start

### Install and configure Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y vault

cat <<EOF > /etc/systemd/system/vault.service
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# Full configuration options can be found at https://www.vaultproject.io/docs/configuration
cat <<EOF > /etc/vault.d/vault.hcl
ui = true
mlock = true

storage "s3" {
  bucket = "${vault_s3_bucket_name}"
  region = "${aws_region}"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true # tls is terminated at the local cloudflared tunnel
}

%{ if vault_kms_auto_unseal }
seal "awskms" {
  region     = "${aws_kms_region}"
  kms_key_id = "${vault_kms_key_id}"
}
%{ endif }
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
