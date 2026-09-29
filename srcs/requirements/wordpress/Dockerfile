FROM    debian:bookworm

RUN     apt-get update \
        && apt-get install -y \
            php \
            curl \
            wget \
            mariadb-client \
            php-mysqli \ 
            php-fpm \
            php-redis \
            php-curl  \
            tar \
        && rm -rf /var/lib/apt/lists/*

#config php-fpm to listen port 9000
RUN sed -i 's/listen =.*/listen = 9000/g' /etc/php/8.2/fpm/pool.d/www.conf 

#create directory for wordpress
RUN mkdir -p /var/www/wordpress


#copy entrypoint script
COPY    ./tools/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE  9000

ENTRYPOINT ["/init.sh"]

CMD ["php-fpm8.2", "-F"]