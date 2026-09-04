# CheckLinks

Lisez ce document dans d'autres langues : [Русский](README.md) · [English](README.en.md) · [Español](README.es.md)

---

## À propos du projet

**CheckLinks** est un utilitaire en ligne de commande (CLI) écrit en **Zig** pour vérifier les liens d'une page web.

L'utilitaire charge la page HTML à l'URL indiquée, collecte tous les liens (`<a href>`) et les images (`<img src>`), puis vérifie la disponibilité de chaque URL. Le résultat est affiché à l'écran sous forme de tableau ou exporté dans un fichier CSV.

> Le projet est une réécriture d'une [implémentation PHP](https://gitverse.ru/kvt/check-links) existante antérieurement.

## Fonctionnalités

- Chargement de pages via les schémas `http://`, `https://` et `file://` (lecture d'un fichier HTML local).
- Extraction des URL depuis les attributs `href` des balises `<a>` et `src` des balises `<img>`.
- Normalisation des liens relatifs en liens absolus à partir du domaine de base (y compris les liens relatifs au protocole `//`).
- Suppression des URL en double.
- Vérification concurrente de la disponibilité de chaque URL par la méthode `HEAD` (un thread par URL).
- Vérification des URL par lots d'une taille configurable : le nombre de requêtes parallèles est défini via `--parallels` (par défaut 5 ; de manière concurrente au sein d'un lot et séquentielle entre les lots).
- Client HTTP HEAD personnalisé avec prise en charge TLS et délai d'attente de la requête (15 secondes par défaut, configurable via `--timeout`).
- En-têtes HTTP personnalisés répétables pour les pages authentifiées et les liens du même origine.
- Regroupement des résultats par code de réponse HTTP.
- Affichage en terminal sous forme de tableau avec des codes colorés :
  - `2xx` — vert ;
  - `3xx` — jaune ;
  - `4xx`/`5xx` — rouge.
- Export des résultats dans un fichier CSV (délimiteur `;`).
- Mode « uniquement les erreurs » — affiche seulement les liens en échec.
- Barre de progression du processus de vérification.
- Internationalisation de l'interface : l'aide CLI, les messages d'erreur et d'avertissement, les en-têtes du tableau et du CSV, ainsi que le modèle de la barre de progression sont compilés en russe, anglais, espagnol ou français via l'option de compilation `-Dlocale` (par défaut `ru`).
- Génération d'un script de complétion automatique de la ligne de commande via la sous-commande `completion`. Les shells `bash`, `zsh`, `fish` et `nushell` sont pris en charge.
- Gestion explicite des erreurs de l'application dans la fonction `main` : les erreurs d'analyse des arguments, d'initialisation de l'analyseur, des en-têtes et de génération du script de complétion sont affichées comme un message localisé sur stderr, et le processus se termine avec un code de retour non nul.

## Prérequis

- **Zig 0.16.0** ou plus récent (voir `minimum_zig_version` dans [`build.zig.zon`](build.zig.zon)).

Dépendances externes du projet :

- [`args.zig`](https://github.com/ktarasov/args.zig) (0.0.9) — analyse des arguments de la ligne de commande ; fournit les sous-commandes et la génération de scripts de complétion.
- `zigquery` (0.2.0) — analyseur HTML pour extraire `href`/`src`.

## Installation et compilation

Clonez le dépôt et compilez le projet :

```sh
zig build
```

Le fichier binaire apparaîtra dans `zig-out/bin/`.

### Commandes de compilation

| Commande | Description |
| --- | --- |
| `zig build` | Compile l'exécutable (`check_links`). |
| `zig build run -- <arguments>` | Compile et exécute l'utilitaire. |
| `zig build test` | Exécute tous les tests. |
| `zig build release` | Compile les binaires de version (archives compressées) pour plusieurs plateformes. |
| `zig build -Dlocale=ru` | Compile avec l'interface en russe (par défaut). |
| `zig build -Dlocale=en` | Compile avec l'interface en anglais. |
| `zig build -Dlocale=es` | Compile avec l'interface en espagnol. |
| `zig build -Dlocale=fr` | Compile avec l'interface en français. |

### Plateformes prises en charge pour la compilation de version

`zig build release` compile et empaquette des binaires pour :

- `x86_64-linux`
- `x86_64-windows` (archive `.zip`)
- `x86_64-macos`
- `aarch64-macos`

### Localisation

L'interface de l'utilitaire (aide CLI, messages d'erreur et d'avertissement, en-têtes du tableau et du CSV, modèle de la barre de progression) peut être compilée en russe, anglais, espagnol ou français. La langue est définie au moment de la compilation via l'option `-Dlocale` (par défaut — le russe) :

```sh
zig build -Dlocale=ru   # interface en russe (par défaut)
zig build -Dlocale=en   # interface en anglais
zig build -Dlocale=es   # interface en espagnol
zig build -Dlocale=fr   # interface en français
```

Les textes de localisation sont stockés dans le catalogue typé [`src/i18n.zig`](src/i18n.zig) ; l'exhaustivité des clés pour chaque langue est garantie par le compilateur.

## Utilisation

```sh
check_links <URL> [options]
```

### Paramètres

| Argument | Description |
| --- | --- |
| `<URL>` | URL de la page dont il faut vérifier les liens (obligatoire). |
| `-f`, `--fail` | Afficher uniquement les liens en erreur. |
| `-e`, `--export <fichier>` | Exporter les résultats dans un fichier CSV. |
| `-t`, `--timeout <secondes>` | Délai d'attente de la requête en secondes (par défaut 15 ; `0` — sans délai). |
| `-H`, `--header <NAME: VALUE>` | Ajouter un en-tête HTTP ; l'option peut être répétée. |
| `-p`, `--parallels <nombre>` | Nombre de requêtes parallèles (par défaut 5 ; de 1 à 100). |

### Sous-commande `completion`

Génère un script de complétion pour l'environnement dans lequel l'utilitaire est exécuté. Le type de shell est détecté automatiquement à partir de la variable d'environnement `$SHELL`. Les shells `bash`, `zsh`, `fish` et `nushell` sont pris en charge.

```sh
check_links completion
```

Le script est écrit sur le flux de sortie standard, vous pouvez donc le rediriger vers le fichier de chargement automatique de votre shell :

```sh
# bash
check_links completion > ~/.bash_completion

# zsh
check_links completion > ${fpath[1]}/_check_links

# fish
check_links completion > ~/.config/fish/completions/check_links.fish

# nushell
check_links completion > check_links-completions.nu
```

Si le type de shell ne peut pas être déterminé ou si une erreur se produit lors de la génération, l'utilitaire affiche un message d'erreur sur stderr et se termine avec un code de retour non nul.

### Exemples

```sh
# Vérifier tous les liens d'une page et afficher le tableau dans le terminal
check_links https://example.com/

# Générer un script de complétion pour le shell actuel
check_links completion

# Afficher uniquement les liens en erreur
check_links --fail https://example.com/

# Augmenter le délai d'attente de la requête à 60 secondes
check_links --timeout 60 https://example.com/

# Augmenter le nombre de requêtes parallèles (par exemple, à 20)
check_links --parallels 20 https://example.com/

# Exporter les résultats dans un fichier CSV
check_links --export result.csv https://example.com/

# Exporter uniquement les liens en erreur au format CSV
check_links --fail --export errors.csv https://example.com/

# Vérifier une page authentifiée avec plusieurs en-têtes
check_links -H 'Authorization: Bearer token' \
  --header 'X-Tenant-ID: 42' \
  https://example.com/private
```

Les en-têtes sont envoyés lors du chargement de la page source et lors des requêtes `HEAD` vers des liens du même origine (schéma, hôte et port effectif). Ils ne sont pas envoyés lors d'une redirection vers un origine externe ni lors de sa vérification. Les formes `--header 'NAME: VALUE'` et `--header='NAME: VALUE'` sont prises en charge.

> Les valeurs des en-têtes passées sur la ligne de commande peuvent être conservées dans l'historique du shell ou être visibles par d'autres processus locaux. Tenez-en compte lorsque vous transmettez des jetons et autres secrets.

### Exemple de sortie (tableau)

```
--------------------------------------------------------------------------
 №      | URL de la page          | URL vérifiée              | Code HTTP
--------------------------------------------------------------------------
     1. | https://example.com     | https://example.com/page1  |   200
     2. | https://example.com     | https://example.com/page2  |   404
     3. | https://example.com     | https://example.com/page3  |   200
--------------------------------------------------------------------------
```

Les codes HTTP du tableau sont colorés selon le plage :
- **2xx** — vert ;
- **3xx** — jaune ;
- **4xx/5xx** — rouge.

## Cas d'utilisation typiques de l'utilitaire

### 1. Vérification des liens cassés sur votre site après une refonte ou une migration

Après un changement de design, de structure des URL ou un déménagement vers un nouveau domaine, il faut s'assurer qu'il ne reste pas de liens vers d'anciennes sections (supprimées) ou fichiers.

```sh
check_links --fail https://mon-site.fr/page/
```

L'utilitaire n'affichera que les liens qui mènent à des pages inexistantes (404, 410) ou à des erreurs serveur (500).

### 2. Audit SEO : recherche de liens vers des ressources externes qui ont cessé de fonctionner

Les liens externes cassés nuisent aux facteurs comportementaux et à la confiance des moteurs de recherche envers votre site. Vérifier régulièrement les liens externes est une partie obligatoire du maintien SEO.

```sh
check_links --export broken-links.csv https://mon-site.fr/
```

Le fichier CSV peut être ouvert dans Excel/Google Sheets et confié au responsable de contenu pour correction.

### 3. Vérification des liens dans un article ou une landing page avant publication

Avant de publier un contenu avec de nombreuses sources externes, il est utile de s'assurer que tous les liens fonctionnent et ne mènent pas à une 404.

```sh
check_links https://blog.mon-site.fr/brouillon-article/
```

Codes verts 200 — tout va bien, jaunes 3xx — redirections (il vaut mieux mettre à jour les liens vers les actuels), rouges 4xx/5xx — liens cassés.

### 4. Surveillance des liens dans la documentation ou une base de connaissances

Pour les sites avec une documentation volumineuse (wikis, bases de connaissances, manuels), il est utile de configurer une vérification régulière des liens pour que la documentation reste toujours à jour.

```sh
# Vérification hebdomadaire via cron
0 6 * * 1 /usr/local/bin/check_links --fail --export /var/log/links-check/docs-errors.csv https://docs.company.ru/
```

### 5. Vérification des liens sur la page d'un produit d'une boutique en ligne

Dans les fiches produits, il y a souvent des liens vers des produits associés, des catégories et des avis. Si ces liens ne mènent nulle part, ce sont des pertes de ventes directes.

```sh
check_links --fail https://boutique.mon-site.fr/catalogue/produit-123/
```

### 6. Audit de la masse de liens avant d'acheter des liens

Lors de l'optimisation SEO, avant d'acheter des liens à un site donateur, il convient de vérifier s'il ne contient pas de pages cassées qui pourraient réduire l'effet de l'achat.

```sh
check_links --fail https://site-donateur.mon-site.fr/
```

### 7. Recherche d'images qui ne se chargent pas

L'utilitaire collecte non seulement les liens (`<a href>`), mais aussi les images (`<img src>`). Cela permet de trouver des images cassées sur une page — une cause fréquente de la dégradation de la perception visuelle du site.

```sh
check_links --fail https://mon-site.fr/galerie/
```

### 8. Vérification des redirections (chaînes de redirection)

Bien que l'utilitaire ne suive pas les chaînes de redirection étape par étape, il affiche le code HTTP 3xx pour les URL qui redirigent. Cela aide à identifier les redirections intermédiaires inutiles qui ralentissent le chargement de la page.

```sh
check_links https://example.com/
```

Faites attention aux lignes jaunes — ce sont des URL qui renvoient 301, 302, etc.

### 9. Export de la carte complète des liens de la page pour une analyse ultérieure

L'export CSV permet de transmettre les résultats à des systèmes BI, Google Sheets ou Excel pour élaborer des rapports et des tableaux de bord.

```sh
check_links --export full-links-report.csv https://mon-site.fr/
```

### 10. Vérification rapide du site d'un client avant une présentation

Pour les agences et les freelances : avant de montrer un site à un client, il vaut la peine de faire passer la page d'accueil et les pages types par l'utilitaire pour éviter une situation gênante avec des liens cassés lors de la démo.

```sh
check_links --fail https://site-du-client.mon-site.fr/
```

## Structure du projet

| Module | Fonction |
| --- | --- |
| [`src/main.zig`](src/main.zig) | Point d'entrée CLI : analyse des arguments (y compris le délai d'attente, le nombre de requêtes parallèles et la sous-commande `completion`), ainsi que la gestion explicite des erreurs avec des messages localisés et des codes de retour corrects. |
| [`src/i18n.zig`](src/i18n.zig) | Catalogue typé de messages localisés (`ru`/`en`/`es`/`fr`) et sélection de la localisation active via `-Dlocale`. |
| [`src/lang.zig`](src/lang.zig) | Énumération des langues d'interface prises en charge (utilisée par la compilation). |
| [`src/check_links_by_page.zig`](src/check_links_by_page.zig) | Orchestration de la vérification des liens d'une page. |
| [`src/collect_urls.zig`](src/collect_urls.zig) | Chargement de la page et collecte des URL depuis le HTML. |
| [`src/html_parser.zig`](src/html_parser.zig) | Analyseur HTML (basé sur la bibliothèque `zigquery`) pour extraire `href`/`src`. |
| [`src/url_normalize.zig`](src/url_normalize.zig) | Normalisation et construction d'URL absolues. |
| [`src/check_link_list.zig`](src/check_link_list.zig) | Vérification par lots de la liste d'URL (chunks) et regroupement par code. |
| [`src/check_http.zig`](src/check_http.zig) | Vérification concurrente des codes HTTP. |
| [`src/http_head_client.zig`](src/http_head_client.zig) | Client HTTP HEAD personnalisé avec TLS et délai d'attente. |
| [`src/request_headers.zig`](src/request_headers.zig) | Analyse des en-têtes HTTP personnalisés et politique de même origine. |
| [`src/table_view.zig`](src/table_view.zig) | Affichage des résultats sous forme de tableau dans le terminal. |
| [`src/export_csv.zig`](src/export_csv.zig) | Export des résultats au format CSV. |
| [`src/TableFormatter.zig`](src/TableFormatter.zig) | Formatage du tableau selon la largeur du terminal. |
| [`src/bar.zig`](src/bar.zig) | Barre de progression du processus de vérification. |
| [`src/tests.zig`](src/tests.zig) | Fichier racine des tests. |
| [`src/http_integration_test.zig`](src/http_integration_test.zig) | Tests d'intégration HTTP sur un serveur local. |

## Comment ça fonctionne

1. L'utilitaire charge le contenu HTML de la page depuis l'URL indiquée.
2. L'analyseur HTML extrait toutes les URL des attributs `href` et `src`.
3. Les liens relatifs sont normalisés en liens absolus ; les doublons sont supprimés.
4. Chaque URL est vérifiée par la méthode `HEAD` de manière concurrente ; un client HTTP HEAD personnalisé avec délai d'attente est utilisé pour la vérification.
5. Les résultats sont regroupés par code de réponse HTTP et affichés sous forme de tableau ou de fichier CSV.

## Format CSV

À l'export, le délimiteur `;` est utilisé. Structure du fichier :

```
№;URL de la page;URL vérifiée;Code HTTP
1;https://example.com;https://example.com/page1;200
2;https://example.com;https://example.com/page2;404
```

Si le fichier existe déjà, il est renommé en `<nom>.bak` avant d'être écrasé.

## Tests

Exécution de tous les tests :

```sh
zig build test
```

Les tests couvrent : l'analyse HTML (basée sur `zigquery`), la normalisation des URL, la collecte des liens d'une page, l'analyse des en-têtes HTTP personnalisés et la politique de même origine, la vérification des codes HTTP sur un serveur de test local (y compris les délais d'attente et les redirections), le formatage du tableau et l'export CSV.

## Licence

Le projet est distribué sous la **Vaslex Free Software License (version 2.0, datée du 11 mars 2025)**. Le texte complet de la licence est disponible dans le fichier [`LICENSE`](LICENSE).