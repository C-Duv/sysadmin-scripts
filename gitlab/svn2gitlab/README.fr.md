Import de dépôts SVN dans GitLab
=================================

La procédure et les scripts utilisés sont en grande partie basés sur le Gist [_svn-to-git_ de Nathan Sweet](https://gist.github.com/NathanSweet/7327535 "Migrates multiple SVN repos to GitHub, without anything fancy (no Ruby, no dependencies, no issues with Cygwin paths).")

0. Préparatifs
--------------

* Avoir les clients `svn`, `git svn` et une version de `read` acceptant le paramètre `-d` (telle celle de Bash).
* Il est recommandé de faire en sorte que les outils SVN aient vos identifiants si nécessaires (nom d'utilisateur et mot de passe) en tête cela évite qu'ils vous soient demandés à chaque appel à `svn`.
Voir [le paragraphe sur le cache d'authentification dans le livre _Gestion de versions avec Subversion_](http://svnbook.red-bean.com/nightly/fr/svn.serverconfig.netmodel.html#svn.serverconfig.netmodel.credcache "Mise en cache des éléments d'authentification du client"))
* Configurer `git` :
    
        git config --global user.name "git-maintenance"
        git config --global user.email "gitlab@example.com"

1. Liste des dépôts
-------------------

Créer un fichier _svnlist.txt_ et y rentrer les URL des dépôts SVN ainsi que leur nom Git désiré (si vide le _basename_ de l'URL sera utilisé) séparés par un espace (" ").

Exemple :

    http://svn.example.com/foobar_v3 foobar
    http://www.example.com/svn/baz
    http://reflectasm.googlecode.com/svn reflect-asm
    http://kryo.googlecode.com/svn

Exécuter le script de nettoyage/lecture de la liste :

    sh read-svnlist.sh

Il va calculer les noms omis et créer _run-convert.sh_ (cf. étape 3). Si d'éventuelles corrections sont apportées au fichier _svnlist.txt_ il suffit de re-exécuter _read-svnlist.sh_ pour les prendre en compte.

2. Fichier des auteurs
----------------------

Le but est d'avoir un fichier (ici nommé _authors.txt_) de mapping SVN-Git à fournir à l'argument `--authors-file` de la commande `git svn clone`.

Exemple de contenu attendu :

    loginname = Joe User <user@example.com>
    john-doe = John Doe <jdoe@example.com>
    foo-bar = Foo Bar <fbar@example.com>

### Méthode 1 : Historique SVN

Cette méthode utilise le script _authors.sh_ pour lire l'historique des dépôts SVN et y trouver les auteurs.

Créer un script _run-authors.sh_ qui va exécuter _authors.sh_ sur tous les dépôts :

    echo "rm authors.txt" > run-authors.sh
    awk '{ print "sh authors.sh " $1 }' svnlist.txt >> run-authors.sh

Exécuter le script ainsi créé :

    sh run-authors.sh

Ouvrir et adapter le fichier _authors.txt_ pour y placer les noms et adresses e-mails que GitLab reconnaitra.

### Méthode 2 : Liste existante

Cette méthode utilise un fichier CSV (séparateur ";") contenant, dans l'ordre, les noms d'utilisateurs SVN, le nom et l'adresse e-mail.
Elle est plus rapide que la première méthode pour les architectures où ces informations sont dans un annuaire ou une base de données car il n'est pas nécessaire de parcourir l'ensemble de l'historique de chaque dépôt.

Créer le fichier _authors.txt_ avec les entrées des utilisateurs SVN absents du CSV (utilisateurs particuliers de maintenance/déploiement) :

    cat > authors.txt <<'EOT'
svn-maintenance = git-maintenance <gitlab@example.com>
USVN = git-maintenance <gitlab@example.com>
EOT

Y importer le CSV (ici _uid-to-name+mail.csv_) :

    sh authors-from-csv.sh uid-to-name+mail.csv

Pour retrier le fichier (après de potentiels changements manuels) :

    cat authors.txt | sort -u > authors.tmp
    mv authors.tmp authors.txt

3. Conversion
-------------

Exécuter le script _run-convert.sh_ (créé par _read-svnlist.sh_ lors de l'étape 1.) :

    ./run-convert.sh

4. Import dans GitLab
---------------------

Le script _to-gitlab.sh_ déplace chaque dossier _*.git_ de _svnlist.txt_ dans le _namespace_ GitLab indiqué et demande à GitLab de les prendre en compte.

Si vous n'avez pas exécuté les étapes précédentes sur la machine hébergeant GitLab, copier premièrement tous les dossiers _*.git_ ainsi que les deux fichiers suivants sur votre machine GitLab avant d'exécuter la commande ci-dessous (directement sur la machine GitLab) :

* svnlist.txt
* to-gitlab.sh

Exécuter l'import des dépôts Git nus (_bare_) dans GitLab :

    ./to-gitlab.sh git git /home/git/repositories/foobar_namespace/

Ici les paramètres correspondent respectivement à :

1. L'utilisateur de GitLab
2. Le groupe de GitLab
3. L'emplacement du _namespace_ où doivent être importés les dépôts (ils pourront être déplacés après-coup directement via l'interface de GitLab)

5. Appendice : Liste des fichiers de travail
-------------------------------------------

1. _svnlist.txt_ : Contient la liste des dépôts SVN à traiter.
2. _authors.txt_ : Contient la liste des utilisateurs ayant travaillé sur ces dépôts.
3. _run-convert.sh_ : Exécute la conversion de chaque dépôt (créé par _read-svnlist.sh_)
4. _run-authors.sh_ : Exécute la recherche d'auteur (_authors.sh_) sur chaque dépôt (créé manuellement)
