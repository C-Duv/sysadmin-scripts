# Creates the "authors.txt" file for SVN-to-GitLab migration from a CSV file
# 
# Reads a CSV file contained login, name and e-mail infos separated by ";" and fills the authors.txt with it
# 
# Usage:
# authors-from-csv.sh <CSV file>
# 
# Based on https://gist.github.com/NathanSweet/7327535#file-authors-sh

cp authors.txt authors.temp
awk --field-separator ';' '{ print $1 " = " $2 " <" $3 ">" }' $1 | sort -u >> authors.temp
cat authors.temp | sort -u > authors.txt
rm authors.temp
