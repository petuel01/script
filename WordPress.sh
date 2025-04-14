#!/bin/bash
# Ultimate WordPress Multi-Site Installer
# Handles all steps: domains, databases, Nginx, SSL, and permissions

# ===== COLOR SETUP =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== INITIAL CHECKS =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root!${NC}"
  exit 1
fi

# ===== USER INPUT =====
read -p "Enter base domain (e.g., duckdns.org): " BASE_DOMAIN
read -p "How many WordPress sites to install? " SITE_COUNT

DOMAINS=()
for ((i=1; i<=$SITE_COUNT; i++)); do
  read -p "Enter subdomain #$i (without .$BASE_DOMAIN): " SUBDOMAIN
  DOMAINS+=("$SUBDOMAIN.$BASE_DOMAIN")
done

read -p "MySQL root password: " MYSQL_ROOT_PASS
read -p "Email for Let's Encrypt certificates: " EMAIL

# ===== SYSTEM CONFIG =====
WEB_ROOT="/var/www"
PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)

# ===== FUNCTIONS =====
create_db_user() {
  local DB_NAME=$1
  local DB_USER=$2
  
  # Generate random password
  local DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
  
  mysql -u root -p"$MYSQL_ROOT_PASS" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  echo "$DB_PASS"
}

setup_wordpress() {
  local DOMAIN=$1
  local DIR_NAME="${DOMAIN%%.*}"
  local SITE_PATH="$WEB_ROOT/$DIR_NAME"
  
  echo -e "\n${YELLOW}=== Setting up $DOMAIN ===${NC}"
  
  # 1. Create directory structure
  mkdir -p "$SITE_PATH"
  cd "$SITE_PATH" || exit
  
  # 2. Download and extract WordPress
  echo -e "${GREEN}Downloading WordPress...${NC}"
  wget -q https://wordpress.org/latest.tar.gz
  tar -xzf latest.tar.gz --strip-components=1
  rm latest.tar.gz
  
  # 3. Set permissions
  chown -R www-data:www-data "$SITE_PATH"
  find "$SITE_PATH" -type d -exec chmod 755 {} \;
  find "$SITE_PATH" -type f -exec chmod 644 {} \;
  
  # 4. Database setup
  local DB_NAME="wp_${DIR_NAME}"
  local DB_USER="user_${DIR_NAME}"
  local DB_PASS=$(create_db_user "$DB_NAME" "$DB_USER")
  
  # 5. Configure wp-config.php
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/$DB_NAME/" wp-config.php
  sed -i "s/username_here/$DB_USER/" wp-config.php
  sed -i "s/password_here/$DB_PASS/" wp-config.php
  
  # 6. Secure table prefix
  local TABLE_PREFIX="wp_$(openssl rand -hex 3)_"
  sed -i "s/\$table_prefix = 'wp_';/\$table_prefix = '$TABLE_PREFIX';/" wp-config.php
  
  # 7. Add security keys
  curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php
  
  # 8. Create Nginx config
  cat > "/etc/nginx/sites-available/$DOMAIN" <<NGINX_CONFIG
server {
    listen 80;
    server_name $DOMAIN;
    root $SITE_PATH;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX_CONFIG

  # 9. Enable site
  ln -s "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/"
  
  echo -e "${GREEN}Created database: ${DB_NAME} with user ${DB_USER}${NC}"
}

# ===== MAIN SCRIPT =====
clear
echo -e "${YELLOW}=== WordPress Multi-Site Setup ===${NC}"

# 1. System updates
echo -e "\n${YELLOW}Updating system...${NC}"
apt update && apt upgrade -y

# 2. Install required packages
echo -e "\n${YELLOW}Installing dependencies...${NC}"
apt install -y nginx mysql-server php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip certbot python3-certbot-nginx

# 3. Secure MySQL
echo -e "\n${YELLOW}Securing MySQL...${NC}"
mysql -u root <<MYSQL_SECURE
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SECURE

# 4. Setup each WordPress site
for DOMAIN in "${DOMAINS[@]}"; do
  setup_wordpress "$DOMAIN"
done

# 5. Test and restart Nginx
echo -e "\n${YELLOW}Configuring Nginx...${NC}"
nginx -t && systemctl restart nginx

# 6. Install SSL certificates
echo -e "\n${YELLOW}Setting up SSL certificates...${NC}"
for DOMAIN in "${DOMAINS[@]}"; do
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect
done

# 7. Setup automatic renewal
echo -e "\n${YELLOW}Configuring automatic certificate renewal...${NC}"
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"systemctl reload nginx\"") | crontab -

# ===== COMPLETION =====
echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "\n${YELLOW}WordPress sites installed:${NC}"
for DOMAIN in "${DOMAINS[@]}"; do
  echo -e "${GREEN}https://$DOMAIN${NC}"
  echo -e "Admin URL: ${GREEN}https://$DOMAIN/wp-admin${NC}"
done

echo -e "\n${YELLOW}MySQL root password:${NC} $MYSQL_ROOT_PASS"
echo -e "\n${YELLOW}Backup these credentials!${NC}"

# Save credentials to file
cat > "$WEB_ROOT/wordpress_credentials.txt" <<CREDS
=== WordPress Installation Details ===
$(date)

MySQL Root Password: $MYSQL_ROOT_PASS

Sites:
$(for DOMAIN in "${DOMAINS[@]}"; do
  DIR_NAME="${DOMAIN%%.*}"
  echo "Domain: https://$DOMAIN"
  echo "Path: $WEB_ROOT/$DIR_NAME"
  echo "DB Name: wp_${DIR_NAME}"
  echo "DB User: user_${DIR_NAME}"
  grep "define.*'DB_PASSWORD'" "$WEB_ROOT/$DIR_NAME/wp-config.php" | awk -F"'" '{print "DB Password: " $4}'
  echo "Table Prefix: $(grep '$table_prefix' "$WEB_ROOT/$DIR_NAME/wp-config.php" | cut -d"'" -f2)"
  echo ""
done)
CREDS

echo -e "\nCredentials saved to: ${GREEN}$WEB_ROOT/wordpress_credentials.txt${NC}"
