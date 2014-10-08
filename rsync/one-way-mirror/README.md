Script to perform a one-way mirroring of files via rsync
========================================================

Usage:
```Shell
one-way-mirror-rsync.sh [-c config_file]
```

If option `-c` is not set, script will use script name to determine a config filename (= `<name of the script>.cfg`).

If _config_file_ does not exists, a blank configuration file will be created and script will exit.

Configuration file example:

    # Configuration
    
    rsyncExecutable="/usr/bin/rsync"
    #rsyncIncludeList="$(dirname "$0")/rsync-include-list"
    rsyncLogFilepath="$0.log"
    #rsyncOtherOptions="--cvs-exclude"
    
    sshExecutable="/usr/bin/ssh"
    
    lockFilepath="$0.lock"
    
    # Source:
    #sourceUser="jbaz"
    #sourceUserPrivateKeyFilepath="$(dirname "$0")/jbaz.key"
    #sourceHost="192.168.0.5"
    #sourceSshPort="22"
    sourceDirpath="/home/user-foo-bar"
    
    # Destination:
    destinationUser="jdoe"
    destinationUserPrivateKeyFilepath="$(dirname "$0")/jdoe.key"
    destinationHost="192.168.0.8"
    destinationSshPort="22"
    destinationDirpath="/mnt/replication"
    
    dryRun=""
    verbose=""
    
    # Uncomment the following to do either a dryRun, a verbose run or both:
    #dryRun=" --dry-run"
    #verbose=" --verbose"

Include list example:
    
    # To replicate:
    + Documents/
    + Documents/***
    + Various stuff/
    + Various stuff/important/
    + Various stuff/important/***
    + Various stuff/private/
    + Various stuff/private/***
    + backups/
    + backups/***
    
    # Exclude anything else:
    - *

