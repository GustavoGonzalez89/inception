#!/bin/bash

#secrets
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/mariadb_root_password)
MYSQL_USER_PASSWORD=$(cat /run/secrets/mariadb_user_password)

#socket setting for the connection temporary
mkdir -p /run/mysqld
#Grant directory user and group ownership to the mysql user and mysql group
chown mysql:mysql   /run/mysqld
chmod 750 /run/mysqld 

# check if this is the 1st run (no mysql system db)
DATABASE_EXITS=false
if [ -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "Custom database ${MYSQL_DATABASE} already exists"
    DATABASE_EXITS=true
else
    echo "Custom database ${MYSQL_DATABASE} does not exist, will create"
fi

# start mariadb temporarily to set up the database
echo "Starting MariaDB temporarily to set up the database..."
mysqld_safe --user=mysql &

# wait for mariadb to start
until mysqladmin ping --silent; do
    sleep 1
done
echo "MariaDB is ready!"

# set root password and create database and users
echo "Setting up root password, database and users..."
mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

echo "Database and users set up successfully!"

# stop temporary server
echo "Shutting down temporary MariaDB server..."
mysqladmin -u root -p$MYSQL_ROOT_PASSWORD shutdown

# launch mariadb in safe mode
echo "Starting MariaDB in production mode..."
# exec replaces the current shell with the command, making mysqld_safe PID 1
exec mysqld_safe --user=mysql