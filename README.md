*Projet réalisé dans le cadre du cursus de l'École 42 Paris par gustgonz.*

# Inception — infrastructure web conteneurisée (Nginx · WordPress · MariaDB)

## Description

Inception est un projet d'administration système : déployer une petite infrastructure web **sans aucune image toute faite** (pas d'image `nginx`, `wordpress` ou `mariadb` de Docker Hub). Chaque service est construit depuis `debian:bookworm` avec son propre Dockerfile et son script d'initialisation, puis orchestré avec Docker Compose.

- **Nginx** : seul point d'entrée, HTTPS uniquement (TLS 1.2 / 1.3), port 443
- **WordPress + PHP-FPM 8.2** : installé et configuré automatiquement avec WP-CLI
- **MariaDB** : base et utilisateur créés au premier démarrage

Les mots de passe passent par des **Docker secrets**, les données sont persistées sur l'hôte dans `/home/gustgonz/data`.

Documentation complémentaire : [USER_DOC.md](USER_DOC.md) (utilisation) et [DEV_DOC.md](DEV_DOC.md) (installation, développement).

---

## Architecture

```
                      Hôte (VM Debian)
  ┌─────────────────────────────────────────────────────────────────┐
  │  :443                                                           │
  │    │            réseau bridge « inception »                     │
  │  ┌─▼──────────────┐  FastCGI   ┌──────────────────┐  SQL        │
  │  │ nginx          │──────────▶│ wordpress        │──────────┐  │
  │  │ TLS 1.2 / 1.3  │  :9000     │ PHP-FPM 8.2      │  :3306   │  │
  │  │ cert autosigné │            │ WP-CLI           │  ┌───────▼┐ │
  │  └───────┬────────┘            └────────┬─────────┘  │mariadb │ │
  │          │ lecture seule                │            └───┬────┘ │
  │          ▼                              ▼                ▼      │
  │   volume wordpress_data ──▶ /home/gustgonz/data/wordpress        │
  │                        volume mariadb_data ──▶ /home/gustgonz/data/mariadb
  │                                                                 │
  │   secrets/*.txt ──▶ /run/secrets/* (mariadb, wordpress)         │
  └─────────────────────────────────────────────────────────────────┘
```

Seul `nginx` publie un port (443). `mariadb` et `wordpress` ne sont joignables que par leur nom de service sur le réseau `inception`.

---

## Ce que j'ai mis en place

### Nginx (`srcs/requirements/nginx/`)
- Certificat autosigné RSA 2048 généré **au build** par `tools/ssl.sh` (openssl, CN `gustgonz.42.fr`, 365 jours) ; clé privée en `chmod 600`.
- `conf/default.conf` : `listen 443 ssl`, `ssl_protocols TLSv1.2 TLSv1.3`, `ssl_ciphers HIGH:!aNULL:!MD5`.
- Les requêtes `.php` sont transmises en **FastCGI** à `wordpress:9000` ; `try_files` pour les permaliens WordPress ; accès aux fichiers cachés (`/\.`) refusé.
- Le volume WordPress est monté **en lecture seule** dans ce conteneur.

### WordPress + PHP-FPM (`srcs/requirements/wordpress/`)
- PHP-FPM 8.2 configuré pour écouter sur le port 9000 (`sed` sur `www.conf`).
- `tools/init.sh`, idempotent (chaque étape vérifie si elle est déjà faite) :
  1. lit les secrets dans `/run/secrets/` (en supprimant `\n` / `\r`) ;
  2. télécharge WordPress si `wp-settings.php` est absent ;
  3. génère `wp-config.php` depuis l'exemple (`sed`), avec `WP_HOME` / `WP_SITEURL` dynamiques ;
  4. **attend MariaDB** (`mysqladmin ping` en boucle) — `depends_on` ne garantit que l'ordre de démarrage, pas la disponibilité ;
  5. installe WP-CLI, puis `wp core install` + création d'un second utilisateur (rôle *author*) ;
  6. `chown www-data`, puis `exec php-fpm8.2 -F` : PHP-FPM devient **PID 1** et reçoit les signaux de Docker.

### MariaDB (`srcs/requirements/mariadb/`)
- `bind-address = 0.0.0.0` pour accepter les connexions du conteneur WordPress (le port n'est pas publié sur l'hôte).
- `tools/mariadb.sh` : démarre un serveur temporaire, attend `mysqladmin ping`, définit le mot de passe root, crée la base et l'utilisateur applicatif (droits limités à cette base), arrête le serveur temporaire puis relance `mysqld_safe` en `exec`.
- `init: true` dans le compose : un mini-init récupère les processus zombies.

### Docker Compose (`srcs/docker-compose.yml`)
- 3 services, `restart: always`, réseau bridge dédié `inception`.
- **Secrets** : 6 fichiers `secrets/*.txt` montés dans `/run/secrets/` — ils n'apparaissent ni dans `docker inspect`, ni dans l'environnement.
- **Volumes nommés** `wordpress_data` et `mariadb_data`, adossés à `/home/gustgonz/data/…` (`driver_opts: type none, o bind`), comme l'exige le sujet.
- Variables non sensibles (domaine, noms d'utilisateurs, nom de la base) dans `srcs/.env`.

---

## Lancer / tester

```bash
# 1. Variables non sensibles
cp srcs/.env.example srcs/.env

# 2. Secrets (un fichier par valeur)
mkdir -p secrets
openssl rand -base64 18 > secrets/mariadb_root_password.txt
openssl rand -base64 18 > secrets/mariadb_user_password.txt
openssl rand -base64 18 > secrets/wp_admin_password.txt
openssl rand -base64 18 > secrets/wp_user_password.txt
echo "chef@example.com"   > secrets/wp_admin_mail.txt
echo "auteur@example.com" > secrets/wp_user_mail.txt

# 3. Domaine local
echo "127.0.0.1 gustgonz.42.fr" | sudo tee -a /etc/hosts

# 4. Build + démarrage (crée /home/gustgonz/data/{wordpress,mariadb})
make
```

Le chemin `/home/gustgonz/data` est imposé par le sujet (login 42) : sur une autre machine, adapter `Makefile` et les `device:` de `srcs/docker-compose.yml`.

**Vérifications** :

```bash
docker ps                                         # nginx, wordpress, mariadb "Up"
curl -kI https://gustgonz.42.fr                   # HTTP/1.1 200 OK
curl -I  http://gustgonz.42.fr                    # échec : aucun port 80
openssl s_client -connect gustgonz.42.fr:443 -tls1_1 </dev/null  # refusé
openssl s_client -connect gustgonz.42.fr:443 -tls1_2 </dev/null  # accepté
docker exec -it mariadb mysql -u root -p          # mot de passe : secrets/mariadb_root_password.txt
```

Persistance : créer un article dans `https://gustgonz.42.fr/wp-admin`, puis `docker compose -f srcs/docker-compose.yml restart` → l'article est toujours là.

---

## Difficultés rencontrées

- **Disponibilité de MariaDB** : WordPress démarrait avant que la base accepte les connexions. `depends_on` ne suffit pas, d'où la boucle `mysqladmin ping` dans `init.sh`.
- **Initialisation de MariaDB** : impossible de créer utilisateurs et base sans serveur lancé. Solution : un serveur temporaire pour la configuration, arrêté ensuite, puis le vrai serveur en `exec` pour qu'il soit PID 1.
- **Secrets avec retour à la ligne** : un fichier créé avec `echo` finit par `\n`, qui se retrouvait dans les mots de passe. Nettoyage avec `tr -d '\n\r'`.
- **URL de WordPress** : WordPress enregistre son URL en base et redirige dessus. Pour accéder au site à la fois depuis la VM (`gustgonz.42.fr`) et depuis l'hôte via une redirection de port, `WP_HOME` / `WP_SITEURL` sont calculés à partir du `Host` de la requête.
- **PID 1 et signaux** : sans `exec`, le script shell reste PID 1 et `docker stop` attend le timeout. Tous les points d'entrée finissent par `exec`.

### Points que j'améliorerais

- Le mot de passe root de MariaDB est passé en argument (`mysqladmin -p…`) à l'arrêt du serveur temporaire : visible dans la liste des processus pendant l'exécution.
- `mariadb.sh` détecte si la base existe déjà (`DATABASE_EXITS`) mais n'utilise pas cette information : la configuration SQL est retentée à chaque démarrage (sans effet grâce aux `IF NOT EXISTS`).
- Pas de `healthcheck` dans le compose : l'attente se fait dans les scripts.
- `php-redis` est installé alors qu'aucun service Redis n'est déployé (bonus non réalisé).

---

## Compétences mobilisées

- Docker : Dockerfile depuis Debian (aucune image de service toute faite), PID 1 et signaux, `init`
- Docker Compose : réseau bridge, volumes nommés adossés à l'hôte, secrets, politiques de redémarrage
- Nginx : terminaison TLS, FastCGI vers PHP-FPM, restrictions d'accès
- TLS / PKI : génération de certificat avec openssl, choix des protocoles et suites
- MariaDB : initialisation, gestion des utilisateurs et des droits
- PHP-FPM, WordPress, WP-CLI
- Bash : scripts d'initialisation idempotents
- Administration Linux : `/etc/hosts`, permissions, diagnostic avec `docker logs` / `docker exec`

---

## Utilisation de l'IA

Une IA (ChatGPT) a servi à expliquer des notions (réseaux Docker, volumes, sécurité), à aider au débogage de configurations et à relire la documentation. Les configurations et la validation finale ont été faites à la main.
