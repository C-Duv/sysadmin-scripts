Importing SVN repository into GitLab
====================================

Procedure detailed here and corresponding used scripts are based on [_svn-to-git_ Gist from Nathan Sweet](https://gist.github.com/NathanSweet/7327535 "Migrates multiple SVN repos to GitHub, without anything fancy (no Ruby, no dependencies, no issues with Cygwin paths).")

0. Prepare
----------

* Make sure `svn`, `git svn` and a version of `read` supporting `-d` option (such as Bash's) are installed.
* It is advised to make SVN tools aware of your credentials if any (username and password) to avoid continuous password prompt during bulk processing (once per `svn` invocation).
See [credentials caching paragraph in _Version Control with Subversion_ book](http://svnbook.red-bean.com/nightly/en/svn.serverconfig.netmodel.html#svn.serverconfig.netmodel.credcache "Caching credentials"))
* Configure `git`:
    
        git config --global user.name "git-maintenance"
        git config --global user.email "gitlab@example.com"

1. Repository list
------------------

Create a _svnlist.txt_ file and fill it with SVN repository's URL and desired Git-name (if empty, _basename_'s URL will be used) separated by a space (" ").

Example:

    http://svn.example.com/foobar_v3 foobar
    http://www.example.com/svn/baz
    http://reflectasm.googlecode.com/svn reflect-asm
    http://kryo.googlecode.com/svn

Execute list clean/read script:

    sh read-svnlist.sh

It will compute omitted names and create _run-convert.sh_ (cf. step 3). If any correction were to be made on file _svnlist.txt_, just re-execute _read-svnlist.sh_ to take them into account.

2. Authors file
---------------

Goal here is to have a SVN-Git mapping file (here named _authors.txt_) to supply to `--authors-file` option of `git svn clone`.

Content example:

    loginname = Joe User <user@example.com>
    john-doe = John Doe <jdoe@example.com>
    foo-bar = Foo Bar <fbar@example.com>

### Method 1: SVN log

This method uses _authors.sh_ script to fetch and parse SVN repositories' log to find authors.

Create a script _run-authors.sh_ to execute _authors.sh_ on every repository:

    echo "rm authors.txt" > run-authors.sh
    awk '{ print "sh authors.sh " $1 }' svnlist.txt >> run-authors.sh

Executer obtained script:

    sh run-authors.sh

Open and adapt _authors.txt_ file to put names and e-mail addresses that GitLab will recognize.

### Method 2: Existing list

This methode uses a CSV file (separator is ";") containing, in this order, SVN usernames, name and e-mail address.
It's faster than first method when such information are in a directory or a database because there is no need to parse entire log of every repository.

Create _authors.txt_ file with entries of SVN users that are not present in CSV file (special maintenance/deployment users):

    cat > authors.txt <<'EOT'
svn-maintenance = git-maintenance <gitlab@example.com>
USVN = git-maintenance <gitlab@example.com>
EOT

Import the CSV file (here named _uid-to-name+mail.csv_):

    sh authors-from-csv.sh uid-to-name+mail.csv

To re-sort the file (after any manual change):

    cat authors.txt | sort -u > authors.tmp
    mv authors.tmp authors.txt

3. Conversion
-------------

Execute _run-convert.sh_ script (created by _read-svnlist.sh_ during step 1.):

    ./run-convert.sh

4. Import into GitLab
---------------------

_to-gitlab.sh_ script moves every _*.git_ folders from _svnlist.txt_ into designated GitLab's namespace and asks GitLab to take them into account.

If previous steps were not executed on the computer hosting GitLab, firstly copy every _*.git_ folders and the two following files on the GitLab server before running the command below (on GitLab server):

* svnlist.txt
* to-gitlab.sh

Executer the bare git repositories GitLab import:

    ./to-gitlab.sh git git /home/git/repositories/foobar_namespace/

Here arguments are respectively:

1. GitLab's user
2. GitLab's group
3. Path to the namespace where repositories are to be imported (can be moved afterwards directly via GitLab UI)

5. Appendix: Working files list
-------------------------------

1. _svnlist.txt_: Contains the list of SVN repositories to process.
2. _authors.txt_: Contains the list of SVN users having worked on theses repositories.
3. _run-convert.sh_: Executes SVN to GIT conversion of every repository (created by _read-svnlist.sh_)
4. _run-authors.sh_: Executes author lookup (_authors.sh_) on every repository (created manually)
