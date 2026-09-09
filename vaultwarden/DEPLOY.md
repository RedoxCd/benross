# Déploiement Vaultwarden — vault.benross.ch

Runbook à exécuter en SSH sur le VPS. Les fichiers `docker-compose.yml` et
`nginx/vault` de ce repo sont les sources de vérité — copie-les tels quels
sur le serveur (ou clone le repo directement dessus).

## 0. Pré-requis DNS (Infomaniak)

Avant tout, crée l'enregistrement A dans la zone DNS `benross.ch` :

```
vault.benross.ch.   A   <IP_DU_VPS>
```

Vérifie la propagation avant de lancer Certbot :

```bash
dig +short vault.benross.ch
```

## 1. Installer Docker + Docker Compose (si absent)

```bash
# Vérifier si Docker est déjà installé
docker --version || true

# Installation officielle (script get-docker)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Ajouter ton user au groupe docker (évite le sudo à chaque commande)
sudo usermod -aG docker "$USER"
# déconnecte-toi / reconnecte-toi (ou `newgrp docker`) pour que ça prenne effet

# Docker Compose v2 est inclus en plugin avec get-docker.sh — vérifier :
docker compose version
```

## 2. Lancer Vaultwarden

```bash
mkdir -p /home/ubuntu/vaultwarden
cd /home/ubuntu/vaultwarden
mkdir -p data

# Copier le docker-compose.yml de ce repo ici (scp, git clone, ou coller le contenu)
# puis :
docker compose up -d
```

Vérifie que le conteneur écoute bien en local uniquement :

```bash
docker ps
curl -I http://127.0.0.1:8080
```

## 3. Config Nginx

```bash
# Copier nginx/vault de ce repo vers :
sudo cp nginx/vault /etc/nginx/sites-available/vault

# Tester la conf
sudo nginx -t
```

## 4. Activer le site + reload

```bash
sudo ln -s /etc/nginx/sites-available/vault /etc/nginx/sites-enabled/vault
sudo nginx -t
sudo systemctl reload nginx
```

## 5. Certificat HTTPS via Certbot

```bash
# Si certbot n'est pas déjà installé (probable, vu que tu l'utilises déjà pour d'autres sous-domaines)
sudo certbot --nginx -d vault.benross.ch

# Certbot va automatiquement :
# - obtenir le certificat Let's Encrypt
# - modifier /etc/nginx/sites-available/vault pour ajouter le bloc HTTPS
#   (listen 443 ssl, redirection HTTP->HTTPS, chemins des certs)
sudo systemctl reload nginx
```

Vérifie ensuite :

```bash
curl -I https://vault.benross.ch
```

Le renouvellement auto est déjà géré par le timer certbot systemd habituel
(`systemctl status certbot.timer`), rien à faire de plus.

## 6. Créer ton premier compte (SIGNUPS_ALLOWED)

Le `docker-compose.yml` a `SIGNUPS_ALLOWED: "false"` par défaut. Pour créer
ton compte :

```bash
cd /home/ubuntu/vaultwarden
# Éditer docker-compose.yml : SIGNUPS_ALLOWED: "true"
docker compose up -d
```

Va sur https://vault.benross.ch, crée ton compte, puis :

```bash
# Remettre SIGNUPS_ALLOWED: "false"
docker compose up -d
```

## 7. Vérification & logs

```bash
# État du conteneur
docker ps --filter name=vaultwarden

# Logs en direct
docker logs -f vaultwarden

# Dernières 100 lignes seulement
docker logs --tail 100 vaultwarden

# En cas de doute sur la conf Nginx / cert
sudo nginx -t
sudo systemctl status nginx
sudo certbot certificates
```

## 8. Backup

Voir `scripts/vaultwarden-backup.sh` dans ce repo. Le principe :
- snapshot cohérent de la base SQLite via `sqlite3 .backup` (pas besoin
  d'arrêter le conteneur),
- puis une archive tar du reste du dossier `data/` (pièces jointes, sends,
  clés RSA, `config.json`, icônes en cache),
- rétention 14 jours par défaut.

Pour l'intégrer à ton `/home/ubuntu/backup.sh` existant, deux options :

**Option A — source le fichier** (le plus simple, rien à dupliquer) :

```bash
# à ajouter dans backup.sh
source /home/ubuntu/scripts/vaultwarden-backup.sh
```

**Option B — copier la fonction `backup_vaultwarden()` directement** dans
`backup.sh` et l'appeler au même endroit que tes autres backups.

Pense à vérifier que le user qui exécute `backup.sh` (souvent root via cron)
a bien accès à Docker (`docker exec`, `docker cp`).

### Restauration

```bash
# Arrêter le conteneur
cd /home/ubuntu/vaultwarden && docker compose down

# Restaurer la DB
cp /home/ubuntu/backups/vaultwarden/db_<DATE>.sqlite3 \
   /home/ubuntu/vaultwarden/data/db.sqlite3

# Restaurer le reste (écrase data/, à faire sur un dossier vide si besoin)
tar xzf /home/ubuntu/backups/vaultwarden/vaultwarden_full_<DATE>.tar.gz \
    -C /home/ubuntu/vaultwarden/data

docker compose up -d
```
