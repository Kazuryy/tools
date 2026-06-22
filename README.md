# Tools — Scripts de configuration

> Scripts d'outillage pour la configuration de postes de développement.

---

## `setup-git.sh`

Configure en une commande une clé SSH, `~/.ssh/config`, le clone d'un dépôt Gitea et la signature de commits.

---

### Prérequis

| Outil | Requis |
|-------|--------|
| `git` | toujours |
| `ssh-keygen` | sauf si l'étape SSH est sautée |
| `gpg` | uniquement si signature GPG choisie |

---

### Téléchargement rapide

**curl**
```bash
curl -fsSL https://raw.githubusercontent.com/Kazuryy/tools/develop/setup-git.sh -o setup-git.sh
```

**wget**
```bash
wget -q https://raw.githubusercontent.com/Kazuryy/tools/develop/setup-git.sh
```

---

### Usage

```bash
bash setup-git.sh
```

---

### Étapes

| # | Étape | Optionnel |
|---|-------|-----------|
| 1 | Génération clé SSH ed25519 + `~/.ssh/config` | oui — sautez si déjà configuré |
| 2 | Ajout de la clé sur Gitea + test de connexion | oui — lié à l'étape 1 |
| 3 | Clone du dépôt ou configuration du remote `origin` | |
| 4 | Choix de la méthode de signature (SSH recommandé / GPG) | |
| 5 | Config Git locale (`user.name`, `user.email`, signature) | |

> La config Git **globale** n'est jamais modifiée.

---

### Formats d'URL SSH acceptés

| Format | Exemple |
|--------|---------|
| scp-like | `git@gitea.mon-domaine.com:org/repo.git` |
| `ssh://` avec port | `ssh://git@gitea.mon-domaine.com:2222/org/repo.git` |

Avec le format `ssh://`, le port est extrait automatiquement — il ne sera pas demandé séparément.
