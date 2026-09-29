#!  /bin/bash 

mkdir -p /etc/ssl

openssl req -newkey rsa:2048 \
            -x509 \
            -sha256 \
            -days 365 \
            -nodes \
            -out    /etc/ssl/certificat.crt \
            -keyout /etc/ssl/certificat.key \
            -subj "/C=FR/ST=Paris/L=Paris/O=42/OU=gustgonz/CN=gustgonz.42.fr"

