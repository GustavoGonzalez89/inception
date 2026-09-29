#!/bin/bash

# ============================================
# Load secrets
# ============================================
MYSQL_USER_PASSWORD=$(cat /run/secrets/mariadb_user_password | tr -d '\n\r')
WP_ADMIN_PASSWORD=$(cat /run/secrets/wp_admin_password | tr -d '\n\r')
WP_ADMIN_MAIL=$(cat /run/secrets/wp_admin_mail | tr -d '\n\r')
WP_USER_MAIL=$(cat /run/secrets/wp_user_mail | tr -d '\n\r')
WP_USER_PASSWORD=$(cat /run/secrets/wp_user_password | tr -d '\n\r')
MYSQL_USER=${MYSQL_USER}
MYSQL_DATABASE=${MYSQL_DATABASE}

# ============================================
# Validate critical variables
# ============================================
if [ -z "${DOMAIN_NAME}" ]; then
    echo "ERROR: DOMAIN_NAME is not set. Check .env file."
    exit 1
fi

echo "DOMAIN_NAME is: ${DOMAIN_NAME}"

# ============================================
# Download WordPress if not present
# ============================================
if [ ! -f "/var/www/wordpress/wp-settings.php" ]; then
    echo "WordPress not found, downloading..."
    wget -O /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    tar -xzf /tmp/wordpress.tar.gz -C /tmp
    cp -r /tmp/wordpress/* /var/www/wordpress/
    rm -rf /tmp/wordpress.tar.gz /tmp/wordpress/
    echo "WordPress downloaded and extracted."
else
    echo "WordPress files already present."
fi

# ============================================
# Create wp-config.php if not present
# ============================================
if [ ! -f "/var/www/wordpress/wp-config.php" ]; then
    echo "Creating wp-config.php..."
    cp /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php

    sed -i "s/database_name_here/${MYSQL_DATABASE}/" /var/www/wordpress/wp-config.php
    sed -i "s/username_here/${MYSQL_USER}/" /var/www/wordpress/wp-config.php
    sed -i "s/password_here/${MYSQL_USER_PASSWORD}/" /var/www/wordpress/wp-config.php
    sed -i "s/localhost/mariadb/" /var/www/wordpress/wp-config.php

    # URLs dynamiques : WordPress reprend le Host envoyé par le navigateur
    # (accès depuis la VM via gustgonz.42.fr et depuis l'hôte via redirection de port)
    sed -i "/\/\* That's all, stop editing/i\\
define('WP_HOME', 'https://' . \$_SERVER['HTTP_HOST']);\\
define('WP_SITEURL', 'https://' . \$_SERVER['HTTP_HOST']);" /var/www/wordpress/wp-config.php

    echo "wp-config.php created."
fi

# ============================================
# Wait for MariaDB
# ============================================
echo "Waiting for MariaDB..."
until mysqladmin -h mariadb -u"${MYSQL_USER}" --password="${MYSQL_USER_PASSWORD}" ping --silent; do
    echo "MariaDB is not available yet..."
    sleep 2
done
echo "MariaDB ready!"

# ============================================
# Install WP-CLI if not present
# ============================================
if [ ! -f "/usr/local/bin/wp" ]; then
    echo "Downloading WP-CLI..."
    wget -O /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp
fi

cd /var/www/wordpress

# ============================================
# Install WordPress if not already installed
# ============================================
if ! wp core is-installed --allow-root --path=/var/www/wordpress 2>/dev/null; then
    echo "Installing WordPress..."
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="42 inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_MAIL}" \
        --allow-root

    echo "Creating additional user..."
    wp user create \
        "${WP_NEW_USER}" \
        "${WP_USER_MAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --allow-root

    echo "WordPress installed successfully."
else
    echo "WordPress is already installed."
fi

# ============================================
# ALWAYS ensure correct URLs in database
# ============================================
echo "Setting WordPress URLs to https://${DOMAIN_NAME}..."
wp option update home "https://${DOMAIN_NAME}" --allow-root --path=/var/www/wordpress
wp option update siteurl "https://${DOMAIN_NAME}" --allow-root --path=/var/www/wordpress

# ============================================
# Set permissions and start PHP-FPM
# ============================================
chown -R www-data:www-data /var/www/wordpress

echo "Testing PHP-FPM configuration..."
php-fpm8.2 -t

echo "Starting PHP-FPM..."
exec php-fpm8.2 -F
