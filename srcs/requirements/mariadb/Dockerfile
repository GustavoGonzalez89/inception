FROM    debian:bookworm

RUN     apt-get update \
        && apt-get install -y mariadb-server \
        && rm -rf /var/lib/apt/lists/* 

#copy script into the container
copy    /tools/mariadb.sh   /mariadb.sh
RUN     chmod +x /mariadb.sh 

# config mariadb to listen on all interfaces
RUN sed -i 's/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/' \
        /etc/mysql/mariadb.conf.d/50-server.cnf

# listen on port 
EXPOSE 3306

#Container set up commande 
ENTRYPOINT ["/mariadb.sh"]