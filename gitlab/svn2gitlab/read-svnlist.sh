# Formats the "svnlist.txt" file for SVN to GitLab migration and creates "run-convert.sh" file
# 
# Reads the "svnlist.txt" file and computes the matching Git repository name
# Also creates "run-convert.sh" script
# Can be executed over and over without loosing changes

awk -F ' ' '{if($2=="")print $1 " " basename($1); else print $1 " " $2} function basename(pn) {
	sub(/^.*\//, "", pn)
	return pn
}' svnlist.txt | sort -u > svnlist.temp
cat svnlist.temp | sort -u > svnlist.txt
rm svnlist.temp

awk '{ print "./convert.sh " $1 " \"\" " $2 }' svnlist.txt > run-convert.sh
chmod +x convert.sh
