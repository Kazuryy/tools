# tools

Scripts d'outillage pour la configuration de postes de développement.

---

## `setup-git.sh`

Configure une clé SSH, `~/.ssh/config`, le clone d'un dépôt et la signature de commits pour une instance **Gitea**.

### Prérequis

- `git`
- `ssh-keygen` (sauf si l'étape SSH est sautée)
- `gpg` (uniquement si vous choisissez la signature GPG)

### Usage

```bash
bash setup-git.sh
```

### Ce que fait le script

1. **SSH** (optionnel, sautez si déjà configuré)
   - Génère une clé ed25519 dans `~/.ssh/id_ed25519_gitea_<username>`
   - Ajoute une entrée dans `~/.ssh/config`
   - Guide l'ajout de la clé publique sur Gitea et teste la connexion

2. **Dépôt**
   - Clone le dépôt distant, ou configure le remote `origin` sur un dossier existant

3. **Signature des commits** (au choix)
   - **SSH** — réutilise la clé SSH générée (recommandé)
   - **GPG** — génère une clé GPG ed25519

4. **Config Git locale** — applique `user.name`, `user.email` et la méthode de signature dans le repo uniquement (la config globale n'est pas modifiée)

### Formats d'URL SSH acceptés

| Format | Exemple |
|--------|---------|
| scp-like | `git@gitea.mon-domaine.com:org/repo.git` |
| ssh:// avec port | `ssh://git@gitea.mon-domaine.com:2222/org/repo.git` |

Avec le format `ssh://`, le port est extrait automatiquement de l'URL — il ne sera pas demandé séparément.
