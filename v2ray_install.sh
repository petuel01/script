#!/bin/bash

echo "##########################
#......PETZEUSTECH.......#
##########################"

# Prompt user for domain and email
read -p "Enter your domain (e.g., example.com): " DOMAIN
read -p "Enter your email for Let's Encrypt SSL: " EMAIL

# Update system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo "Installing dependencies..."
sudo apt install curl wget gnupg2 ca-certificates lsb-release ufw nano nginx certbot python3-certbot-nginx -y

# Install Xray-core
echo "Installing Xray-core..."
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) install

# Generate UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "Generated UUID: $UUID"

# Ensure correct directory structure
mkdir -p /usr/local/etc/xray

# Remove any existing Nginx and Xray configuration
echo "Resetting configuration files..."
sudo rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
sudo rm -f /usr/local/etc/xray/config.json

# Create new Xray configuration
echo "Configuring Xray..."
cat <<EOF | sudo tee /usr/local/etc/xray/config.json > /dev/null
{
  "inbounds": [
    {
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ]
        },
        "wsSettings": {
          "path": "/v2ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# Configure Nginx
echo "Configuring Nginx..."
cat <<EOF | sudo tee /etc/nginx/sites-available/default > /dev/null
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        root /var/www/html;
        index index.html;
    }

    location /v2ray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Restart Nginx
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Obtain SSL certificate using Certbot
echo "Obtaining SSL certificate..."
sudo certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email $EMAIL -d $DOMAIN

# Restart Xray
echo "Restarting Xray..."
sudo systemctl restart xray
sudo systemctl enable xray
sudo systemctl enable nginx

# Open required ports
echo "Configuring firewall..."
sudo ufw allow 80
sudo ufw allow 443
ufw allow OpenSSH
sudo ufw allow 22/tcp
sudo ufw enable

# Output success message and client details
echo "Setup complete!"
echo "V2Ray Xray-core is running with WebSocket over TLS on port 443."
echo "Use the following details in your VPN client:"
echo "----------------------------------------------------"
echo "Address: $DOMAIN"
echo "Port: 443"
echo "UUID: $UUID"
echo "TLS: Enabled"
echo "WebSocket Path: /v2ray"
echo "----------------------------------------------------"
