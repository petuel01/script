#!/bin/bash

# Auto Deploy Static HTML from GitHub with Nginx + SSL
# Run as root: sudo bash host_static.sh

echo "🔧 Enter your subdomain (e.g. site.example.com): "
read SUBDOMAIN

echo "🔧 Enter your GitHub repo URL (e.g. https://github.com/user/repo.git): "
read GIT_URL

WEBROOT="/var/www/$SUBDOMAIN"

echo "🔧 Installing required packages..."
apt update && apt install -y nginx git certbot python3-certbot-nginx

# Create web root if not exists
mkdir -p $WEBROOT

# Clone or pull repo
if [ -d "$WEBROOT/.git" ]; then
    echo "🔄 Updating existing repo..."
    git -C $WEBROOT pull
else
    echo "📥 Cloning new repo..."
    git clone $GIT_URL $WEBROOT
fi

# Set permissions
chown -R www-data:www-data $WEBROOT
chmod -R 755 $WEBROOT

# Create Nginx config
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name $SUBDOMAIN;

    root $WEBROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Enable site
ln -s $NGINX_CONF /etc/nginx/sites-enabled/ 2>/dev/null

# Test & reload nginx
nginx -t && systemctl reload nginx

# Issue SSL cert
echo "🔐 Setting up SSL certificate..."
certbot --nginx -d $SUBDOMAIN --non-interactive --agree-tos -m admin@$SUBDOMAIN

echo "✅ Deployment complete!"
echo "🌍 Visit: https://$SUBDOMAIN"