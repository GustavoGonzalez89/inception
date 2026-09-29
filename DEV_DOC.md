# DEV_DOC — Documentation développeur

## Prérequis

- Linux (VM Debian dans le cadre du sujet)
- Docker Engine + plugin Docker Compose v2
- `make`, `openssl`, `sudo` (pour `/etc/hosts` et le nettoyage des données)

```bash
docker --version && docker compose version && make --version
```

---

## Installation depuis zéro

```bash
git clone https://github.com/GustavoGonzalez89/inception.git
cd inception

cp srcs/.env.example srcs/.env         # domaine, base, noms d'utilisateurs

mkdir -p secrets                        # un fichier par secret, sans retour à la ligne superflu
openssl rand -base64 18 > secrets/mariadb_root_password.txt
openssl rand -base64 18 > secrets/mariadb_user_password.txt
openssl rand -base64 18 > secrets/wp_admin_password.txt
openssl rand -base64 18 > secrets/wp_user_password.txt
echo "chef@example.com"   > secrets/wp_admin_mail.txt
echo "auteur@example.com" > secrets/wp_user_mail.txt

echo "127.0.0.1 gustgonz.42.fr" | sudo tee -a /etc/hosts
make
```

Sur une machine dont l'utilisateur n'est pas `gustgonz`, remplacer `/home/gustgonz/data` dans `Makefile` (cibles `build`) et dans `srcs/docker-compose.yml` (`volumes.*.driver_opts.device`).

---

## Arborescence

```
.
├── Makefile
├── README.md / USER_DOC.md / DEV_DOC.md
├── secrets/                     # ignoré par Git — à créer
│   └── *.txt
└── srcs/
    ├── .env.example             # à copier en .env (ignoré par Git)
    ├── docker-compose.yml
    └── requirements/
        ├── nginx/
        │   ├── Dockerfile       # debian:bookworm + nginx + openssl
        │   ├── conf/default.conf
        │   └── tools/ssl.sh     # certificat autosigné généré au build
        ├── wordpress/
        │   ├── Dockerfile       # debian:bookworm + php-fpm 8.2 + mariadb-client
        │   └── tools/init.sh    # téléchargement, wp-config, WP-CLI, utilisateurs
        └── mariadb/
            ├── Dockerfile       # debian:bookworm + mariadb-server
            └── tools/mariadb.sh # base, utilisateur, mot de passe root
```

Chaque dossier de service a un `.dockerignore` qui exclut `.env` et `secrets` du contexte de build : aucun secret ne peut se retrouver dans une couche d'image.

---

## Séquence de démarrage

```
make
 ├─ mkdir -p /home/gustgonz/data/{wordpress,mariadb}
 └─ docker compose up -d --build
      ├─ mariadb   : mysqld_safe temporaire → ALTER USER root, CREATE DATABASE/USER, GRANT
      │              → arrêt → exec mysqld_safe (PID 1)
      ├─ wordpress : secrets → téléchargement WP → wp-config.php
      │              → attente mysqladmin ping → WP-CLI : core install + user create
      │              → exec php-fpm8.2 -F (PID 1)
      └─ nginx     : nginx -g "daemon off;" sur 443, FastCGI → wordpress:9000
```

`depends_on` impose seulement l'ordre de création des conteneurs ; la disponibilité réelle de MariaDB est attendue dans `init.sh`.

---

## Cibles du Makefile

| Cible | Commande | Remarque |
|---|---|---|
| `all` / `build` | `mkdir` des données + `up -d --build` | |
| `down` / `clean` | `down -v` | supprime aussi les volumes Docker (pas les fichiers de l'hôte) |
| `kill` | `kill` | |
| `log` | `logs` | |
| `fclean` | `clean` + `docker system prune -a -f` + `volume prune` + `network prune` | ⚠️ nettoie **tout** Docker sur la machine |
| `restart` | `fclean` puis `all` | |

---

## Travailler sur un service

```bash
# reconstruire et relancer un seul service
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d nginx

# shell dans un conteneur
docker exec -it wordpress bash
docker exec -it mariadb mysql -u root -p

# tester la config Nginx / PHP-FPM
docker exec nginx nginx -t
docker exec wordpress php-fpm8.2 -t

# WP-CLI
docker exec wordpress wp user list --allow-root --path=/var/www/wordpress
```

---

## Données et persistance

| Volume | Monté dans | Stockage sur l'hôte |
|---|---|---|
| `wordpress_data` | `wordpress:/var/www/wordpress` (rw), `nginx:/var/www/wordpress` (ro) | `/home/gustgonz/data/wordpress` |
| `mariadb_data` | `mariadb:/var/lib/mysql` | `/home/gustgonz/data/mariadb` |

Ce sont des volumes nommés dont le pilote `local` fait un bind vers le dossier de l'hôte (`type: none`, `o: bind`). Les données survivent à `docker compose down`, `down -v` et à la reconstruction des images ; pour repartir de zéro, il faut vider ces deux dossiers.

Les scripts d'initialisation sont idempotents : au redémarrage, WordPress n'est ni retéléchargé ni réinstallé, et les `CREATE … IF NOT EXISTS` de MariaDB sont sans effet.

---

## Réseau

- Réseau bridge `inception` ; résolution DNS par nom de service (`mariadb`, `wordpress`).
- Flux autorisés par la configuration : hôte → `nginx:443` → `wordpress:9000` (FastCGI) → `mariadb:3306`.
- Seul `nginx` publie un port ; le `ports: 3306` de MariaDB est commenté.

---

## Changer le domaine

1. `DOMAIN_NAME` dans `srcs/.env`
2. `server_name` dans `srcs/requirements/nginx/conf/default.conf`
3. le `CN` dans `srcs/requirements/nginx/tools/ssl.sh`
4. `/etc/hosts`, puis `make` : `init.sh` remet à jour les options `home` et `siteurl` à chaque démarrage
