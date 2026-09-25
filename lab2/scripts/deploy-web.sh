#!/usr/bin/env bash
set -euo pipefail

# 1. Create service user if it doesn't exist
if ! id "webapp" &>/dev/null; then
  sudo useradd -r -s /sbin/nologin webapp
fi

# 2. Install packages with dnf
sudo dnf install -y python3

# 3. Setup web directory and static files with correct permissions
sudo mkdir -p /var/www/html
sudo bash -c 'echo "<h1>Welcome to ACS730 Lab 2 Web App</h1>" > /var/www/html/index.html'
sudo chown -R webapp:webapp /var/www/html
sudo chmod -R 755 /var/www/html

# 4. Copy systemd unit file and reload daemon
sudo cp acs730-web.service /etc/systemd/system/acs730-web.service || true
sudo systemctl daemon-reload

# 5. Enable and start service
sudo systemctl enable --now acs730-web.service

echo "Deployment complete. Web service status:"
sudo systemctl status acs730-web.service --no-pager
