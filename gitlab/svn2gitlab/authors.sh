# Creates the "authors.txt" file for SVN to GitLab migration from SVN history
# 
# Query SVN for log and parses it
# 
# From: https://gist.github.com/NathanSweet/7327535#file-authors-sh

cp authors.txt authors.temp
svn log -q $1 | awk -F '|' '/^r/ {sub("^ ", "", $2); sub(" $", "", $2); print $2" = "$2" <"$2">"}' | sort -u >> authors.temp
cat authors.temp | sort -u > authors.txt
rm authors.temp
