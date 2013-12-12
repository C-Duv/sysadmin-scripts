# Moves created Git repositories to GitLab
# 
# For each existing Git repository of svnlist.txt, change owner and group, move it to designated namespace.
# Then run GitLab "gitlab:import:repos" command to take them into account.
# 
# Usage:
# to-gitlab.sh <GitLab's user> <GitLab's group> <Repository namespace path>[ <GitLab install path>]
# 
#   GitLab's user:
#     User GitLab is running as (usually "git")
#   GitLab's group:
#     Group GitLab is running as (usually "git")
#   Repository namespace path:
#     Path of repository namespace where to place Git repositories (eg. /home/git/repositories/foobar_namespace)
#   GitLab install path:
#     Path on which GitLab is installed (usually "/home/git/gitlab")

GITLAB_USER=$1
GITLAB_GROUP=$2
REP_NS_PATH="$3"
GITLAB_PATH="$4"

if [ $# -lt 3 ]; then
	echo "Usage: $0 <GitLab's user> <GitLab's group> <GitLab namespace path>[ <GitLab install path>]"
	exit 1
fi

# No GitLab path given, use default
if [ $# -eq 3 ]; then
	GITLAB_PATH="/home/$GITLAB_USER/gitlab"
fi

awk '{ print $2 }' svnlist.txt | while read gitRep
do
	if [ -d "$gitRep.git" ]; then
		
		sudo chown -R $GITLAB_USER:$GITLAB_GROUP "$gitRep.git"
		sudo mv "$gitRep.git" "$REP_NS_PATH"
	fi
done

cd $GITLAB_PATH
sudo -u $GITLAB_USER -H bundle exec rake gitlab:import:repos RAILS_ENV=production
