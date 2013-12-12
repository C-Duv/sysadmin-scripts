#!/bin/bash

# Converts a SVN repository into a bare Git repository and optionally push it to GitHub
# 
# Usage:
# convert.sh <SVN URL> <GitHub user's space URL> <Repository name>
# 
#   SVN URL:
#     URL of the SVN repository
#   GitHub user's space URL:
#     URL of GitHub's user where to push repository to(eg. https://github.com/foobar/)
#   Repository name:
#     Name to give to repository
# 
# Based on https://gist.github.com/NathanSweet/7327535#file-convert-sh
# 
# Adapted to:
# * Use "trunk" branch when creating .gitignore file with `git svn show-ignore`
# * Add ".gitkeep" files into empty directories
# * Make sure the script commits gets into the Git repository (thanks http://dtek.net/blog/migrating-projects-subversion-git)
# * Create a "develop" branch from "master"
# * Conditionally avoid pushing to GitHub (push skipped if argument <GitHub URL> is an empty string)

svn_url=$1;
github_url=$2;
name=$3;

echo "Cloning SVN repository to $name.svn... $svn_url"
rm -rf $name.svn
git svn clone $svn_url --no-metadata --authors-file=authors.txt --stdlayout $name.svn
cd $name.svn

echo "Creating .gitignore file..."
git svn show-ignore --id trunk > .gitignore
git add .gitignore
git commit -m 'Convert svn:ignore properties to .gitignore.'

echo "Adding .gitkeep files..."
find . -type d -empty -not -path "./.git/*" -print0 | while read -d $'\0' emptyDir
do
	echo "Adding .gitkeep into $emptyDir"
	#echo ".gitkeep" > "$emptyDir/.gitkeep"
	touch "$emptyDir/.gitkeep"
	git add "$emptyDir/.gitkeep"
done
git commit -m 'Adding empty directories with .gitkeep files'

echo "Initializing git repository... $name.git"
cd ..
rm -rf $name.git
git init --bare $name.git
cd $name.git
git symbolic-ref HEAD refs/heads/trunk

echo "Pushing to git repository... $name.git"
cd ../$name.svn
git remote add bare ../$name.git
git config remote.bare.push 'refs/remotes/*:refs/heads/*'
git push bare

echo "Renaming trunk to master..."
cd ../$name.git
git branch -m trunk master

echo "Pushing our script commits to git repository... $name.git"
cd ../$name.svn
git pull bare master
git push bare master

echo "Creating develop from master..."
cd ../$name.git
git branch develop

echo "Converting SVN tag branches to git tags..."
git for-each-ref --format='%(refname)' refs/heads/tags | cut -d / -f 4 |
while read ref
do
	git tag -a "$ref" -m "Tag: $ref" "refs/heads/tags/$ref";
	git branch -D "tags/$ref";
done

if [ -z "$github_url" ]; then
	echo "Not pushing to GitHub"
else
	echo "Pushing to github... $github_url$name"
	git push --mirror --follow-tags $github_url$name
fi

echo "Done!"
