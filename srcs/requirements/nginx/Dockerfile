FROM    debian:bookworm

RUN     apt-get update \
        && apt-get install -y nginx openssl \
        && rm -rf /var/lib/apt/lists/* 


#configuration ssl 
COPY    tools/ssl.sh    /ssl.sh
RUN     chmod +x /ssl.sh \
        && /ssl.sh 
# Clé privée lisible uniquement par root
RUN     chmod 600 /etc/ssl/certificat.key

        
#configuration nginx 
COPY    conf/default.conf   /etc/nginx/conf.d/default.conf

# listen on port 
EXPOSE 443

#commande to run nginx
CMD ["nginx", "-g", "daemon off;"]