#!/bin/bash

# Auto Deploy PHP App with MySQL + Nginx + SSL
# Run as root: sudo bash host_php.sh

echo "🔧 Enter your subdomain (e.g. app.example.com): "
read SUBDOMAIN

echo "🔧 Enter your GitHub repo URL (e.g. https://github.com/user/repo.git): "
read GIT_URL

echo "🔧 Enter database name: "
read DB_NAME

echo "🔧 Enter database user: "
read DB_USER

echo "🔧 Enter database password: "
read -s DB_PASS

WEBROOT="/var/www/$SUBDOMAIN"

echo "📦 Installing required packages..."
apt update && apt install -y nginx git certbot python3-certbot-nginx mysql-server php-fpm php-mysql unzip php-cli php-curl php-zip php-mbstring php-xml

# Install phpMyAdmin if not already
if [ ! -d "/usr/share/phpmyadmin" ]; then
    echo "📦 Installing phpMyAdmin..."
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password $DB_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $DB_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password $DB_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect nginx" | debconf-set-selections
    apt install -y phpmyadmin
fi

# Secure MySQL if first install
mysql_secure_installation <<EOF

y
n
y
y
y
EOF

# Create database and user
echo "🛠️ Creating MySQL database and user..."
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Clone or update repo
mkdir -p $WEBROOT
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

# Detect PHP-FPM version
PHP_FPM_SOCK=$(find /var/run/php -name "php*-fpm.sock" | head -n 1)

# Create Nginx config
NGINX_CONF="/etc/nginx/sites-available/$SUBDOMAIN"

cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name $SUBDOMAIN;

    root $WEBROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable site
ln -s $NGINX_CONF /etc/nginx/sites-enabled/ 2>/dev/null

# Test & reload Nginx
nginx -t && systemctl reload nginx

# Issue SSL cert
echo "🔐 Setting up SSL certificate..."
certbot --nginx -d $SUBDOMAIN --non-interactive --agree-tos -m admin@$SUBDOMAIN

echo "✅ PHP App deployed successfully!"
echo "🌍 Visit: https://$SUBDOMAIN"
echo "🛢️ Database: $DB_NAME, User: $DB_USER"