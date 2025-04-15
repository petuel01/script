#!/bin/bash

# WordPress Installer with Confirmation, Error Handling, and Final Summary
# By ChatGPT - Made for Production Use

prompt_step() {
    echo -e "\n\e[36m$1\e[0m"
    read -p "Do you want to continue this step? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo -e "\e[33mSkipping: $1\e[0m"
        return 1
    fi
    return 0
}

handle_error() {
    echo -e "\e[31mError in step: $1. Exiting...\e[0m"
    exit 1
}

# === USER INPUTS ===
read -p "Enter your full domain (e.g., petueltech.duckdns.org): " DOMAIN
DOMAIN_BASE=$(echo "$DOMAIN" | cut -d '.' -f1)
WEB_ROOT="/var/www/$DOMAIN_BASE"
PHP_VERSION=$(php -v | head -n1 | cut -d" " -f2 | cut -d"." -f1-2)

read -p "Enter MySQL root password: " DB_ROOT_PASS
read -p "Enter database name to create: " DB_NAME
read -p "Enter MySQL username: " DB_USER
read -s -p "Enter MySQL password for $DB_USER: " DB_PASS
echo
read -p "WordPress admin username: " WP_ADMIN
read -s -p "WordPress admin password: " WP_ADMIN_PASS
echo
read -p "WordPress admin email: " WP_EMAIL

# === 1. Install Dependencies ===
prompt_step "1. Install Dependencies (Nginx, PHP, MySQL, etc.)" && {
    sudo apt update && sudo apt install -y nginx mysql-server php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip unzip curl wget
} || handle_error "Dependency Installation"

# === 2. Setup MySQL ===
prompt_step "2. Create MySQL Database and User" && {
    sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
} || handle_error "MySQL Setup"

# === 3. Download & Configure WordPress ===
prompt_step "3. Download and Configure WordPress in $WEB_ROOT" && {
    sudo mkdir -p "$WEB_ROOT" && cd "$WEB_ROOT" || exit 1
    sudo wget -q https://wordpress.org/latest.tar.gz && sudo tar -xzf latest.tar.gz --strip-components=1 && sudo rm latest.tar.gz
    sudo chown -R www-data:www-data "$WEB_ROOT"
    sudo find "$WEB_ROOT" -type d -exec chmod 755 {} \;
    sudo find "$WEB_ROOT" -type f -exec chmod 644 {} \;
} || handle_error "WordPress Setup"

# === 4. Configure Nginx ===
prompt_step "4. Create Nginx Config for $DOMAIN" && {
    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
    sudo bash -c "cat > $NGINX_CONF" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX
    sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
} || handle_error "Nginx Configuration"

# === 5. Install WP-CLI and Run Setup ===
prompt_step "5. Configure WordPress Using WP-CLI" && {
    if ! command -v wp &> /dev/null; then
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
    fi
    cd "$WEB_ROOT"
    sudo -u www-data wp core config --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="localhost" --dbprefix="wp_"
    sudo -u www-data wp core install --url="https://$DOMAIN" --title="$DOMAIN_BASE" --admin_user="$WP_ADMIN" --admin_password="$WP_ADMIN_PASS" --admin_email="$WP_EMAIL"
} || handle_error "WP-CLI Setup"

# === 6. Certbot SSL ===
prompt_step "6. Install Certbot and Secure Domain with HTTPS" && {
    if ! command -v certbot &> /dev/null; then
        sudo apt install -y certbot python3-certbot-nginx
    fi
    sudo certbot --nginx -d "$DOMAIN"
} || handle_error "Certbot SSL Setup"

# === 7. Final Firewall Rules ===
prompt_step "7. Enable UFW Firewall and Allow Nginx + SSH" && {
    sudo ufw allow 'Nginx Full'
    sudo ufw allow OpenSSH
    sudo ufw --force enable
} || handle_error "UFW Firewall Setup"

# === 8. Final Summary ===
echo -e "\n\e[1;32m================= INSTALLATION COMPLETE =================\e[0m"
echo -e "\e[36mWebsite:\e[0m       https://$DOMAIN"
echo -e "\e[36mAdmin URL:\e[0m     https://$DOMAIN/wp-admin"
echo -e "\e[36mWordPress User:\e[0m  $WP_ADMIN"
echo -e "\e[36mWordPress Pass:\e[0m  $WP_ADMIN_PASS"
echo -e "\e[36mWP Email:\e[0m       $WP_EMAIL"
echo -e "\e[36mDatabase:\e[0m       $DB_NAME"
echo -e "\e[36mDB User:\e[0m        $DB_USER"
echo -e "\e[36mDB Pass:\e[0m        $DB_PASS"
echo -e "\e[36mSite Folder:\e[0m    $WEB_ROOT"
echo -e "\e[1;32m=========================================================\e[0m"
