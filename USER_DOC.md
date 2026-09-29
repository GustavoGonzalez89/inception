# USER_DOC — Documentation utilisateur

## Services fournis

| Service | Rôle | Accès |
|---|---|---|
| `nginx` | serveur web HTTPS (TLS 1.2 / 1.3), seul point d'entrée | `https://gustgonz.42.fr` (port 443) |
| `wordpress` | site WordPress exécuté par PHP-FPM 8.2 | via Nginx uniquement |
| `mariadb` | base de données du site | interne, aucun port publié |

---

## Démarrer et arrêter

Depuis la racine du dépôt :

| Commande | Effet |
|---|---|
| `make` | construit les images, crée `/home/gustgonz/data/…`, démarre les 3 conteneurs |
| `make log` | affiche les journaux des 3 services |
| `make kill` | arrête immédiatement les conteneurs |
| `make down` | arrête et supprime conteneurs, réseau **et volumes Docker** (les fichiers dans `/home/gustgonz/data` restent) |

> ⚠️ `make fclean` et `make restart` lancent `docker system prune -a -f` : **toutes** les images et conteneurs arrêtés de la machine sont supprimés, pas seulement ceux du projet.

---

## Accéder au site

1. Le domaine doit pointer vers la machine : `127.0.0.1 gustgonz.42.fr` dans `/etc/hosts`.
2. Ouvrir <https://gustgonz.42.fr>.
3. Le certificat est autosigné : le navigateur affiche un avertissement, il faut l'accepter.

**Administration WordPress** : <https://gustgonz.42.fr/wp-admin>

- Administrateur : identifiant `WP_ADMIN_USER` (dans `srcs/.env`), mot de passe dans `secrets/wp_admin_password.txt`.
- Second utilisateur (rôle *author*) : identifiant `WP_NEW_USER`, mot de passe dans `secrets/wp_user_password.txt`.

---

## Identifiants

Ils ne sont jamais dans le dépôt Git (`.gitignore`).

| Fichier | Contenu |
|---|---|
| `secrets/mariadb_root_password.txt` | mot de passe root MariaDB |
| `secrets/mariadb_user_password.txt` | mot de passe de l'utilisateur MariaDB utilisé par WordPress |
| `secrets/wp_admin_password.txt` / `wp_admin_mail.txt` | administrateur WordPress |
| `secrets/wp_user_password.txt` / `wp_user_mail.txt` | second utilisateur WordPress |
| `srcs/.env` | valeurs non sensibles : domaine, nom de la base, noms d'utilisateurs |

Les secrets sont lus **uniquement à la première installation**. Pour les changer ensuite : `make down`, vider `/home/gustgonz/data/wordpress` et `/home/gustgonz/data/mariadb` (`sudo rm -rf …/*`), modifier les fichiers, puis `make`.

---

## Vérifier que tout fonctionne

```bash
docker ps                               # 3 conteneurs "Up"
curl -kI https://gustgonz.42.fr         # HTTP/1.1 200 OK
docker logs wordpress | tail            # "Starting PHP-FPM..."
docker logs mariadb   | tail            # "Starting MariaDB in production mode..."
docker network ls | grep inception
docker volume ls  | grep -E 'wordpress_data|mariadb_data'
```

---

## En cas de problème

| Symptôme | Piste |
|---|---|
| Page inaccessible | `docker ps` : les 3 conteneurs sont-ils lancés ? `/etc/hosts` contient-il le domaine ? |
| Port 443 déjà utilisé | `sudo ss -tlnp \| grep 443` |
| `502 Bad Gateway` | PHP-FPM ne répond pas : `docker logs wordpress` |
| WordPress en boucle sur « MariaDB is not available yet » | mot de passe utilisateur incohérent avec une base déjà initialisée : `docker logs mariadb`, puis réinitialiser les données (voir ci-dessus) |
