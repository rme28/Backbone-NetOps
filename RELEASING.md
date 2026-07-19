# Processus de release

Ce projet utilise **SemVer** avec canal de pré-version tant qu'on est avant la
`1.0.0` : `vMAJEUR.MINEUR.CORRECTIF-canal`.

## Quand incrémenter quoi (avant 1.0)

| Type de changement | Exemple | Bump |
|---|---|---|
| Nouveau lot de fonctionnalités | palette d'équipements, câblage souris | `MINEUR` → `v0.2.0-alpha` |
| Correctif sur l'existant | bug de config, warning corrigé | `CORRECTIF` → `v0.1.1-alpha` |
| Passage en phase plus stable | fin des grosses features, on fiabilise | canal → `v0.9.0-beta` |
| Sortie stable | prêt pour le public | `v1.0.0` |

Le canal se lit : `alpha` (instable, features en cours) → `beta` (features gelées,
on chasse les bugs) → `rc` (release candidate) → version finale sans suffixe.

## Étapes pour publier une release

1. **Mettre à jour le CHANGELOG.md** : déplacer les entrées de `[Non publié]`
   vers une nouvelle section `[X.Y.Z-canal] — AAAA-MM-JJ`, et mettre à jour les
   deux liens en bas de fichier.
2. **Commit** : `git commit -am "Release vX.Y.Z-canal"`.
3. **Tag annoté** (le message devient le corps de la release) :
   ```bash
   git tag -a vX.Y.Z-canal -m "Titre de la release" -m "Détails..."
   ```
4. **Pousser le commit et le tag** :
   ```bash
   git push origin master
   git push origin vX.Y.Z-canal
   ```
5. **Créer la Release GitHub** à partir du tag :
   - **Option web** (aucun outil requis) : sur
     `https://github.com/rme28/Backbone-NetOps/releases` → *Draft a new release*
     → choisir le tag `vX.Y.Z-canal` → GitHub pré-remplit avec le message du tag
     → cocher *Set as a pre-release* pour les `-alpha`/`-beta` → *Publish release*.
   - **Option CLI** (si `gh` est installé et authentifié) :
     ```bash
     gh release create vX.Y.Z-canal --title "Titre" --notes-file notes.md --prerelease
     ```

## Voir les releases existantes

```bash
git tag --list --sort=-v:refname          # tags locaux, du plus récent au plus ancien
git ls-remote --tags origin               # tags présents sur GitHub
```
