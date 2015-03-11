Script to perform an off-site replication via rsync and EncFS
=============================================================

Description
-----------

This script aims to replicate data from server A to server B.

Because it was created for simple, low storage capacity servers, it uses AutoFS to automatically mount remote source and destination.
Because destination server might totally not be under our control, it uses a [EncFS](https://vgough.github.io/encfs/) volume for the destination.

At the moment:
* source is a FTP server
* destination a SSH server.
* using rsync via [my *one-way-mirror* rsync script](https://github.com/C-Duv/sysadmin-scripts/tree/master/rsync/one-way-mirror) to perform the data transfer.

TODO-list:
* Support local, already mounted path
* Support SSH as source
* Support FTP as destination
* Support EncFS volume as source

Installation
------------

Usage:
```Shell
encfs-rsync-from-autofs-mounted-path_installer.sh [-c config_file]
```

If option `-c` is not set, script will use `offsite_replication.cfg` as the name of the configuration file.

If _config_file_ does not exists, a blank configuration file will be created and script will exit.

Configuration file example:

    # Path where to install
    CFG_INSTALL_PATH="/root/scripts/offsite_replication"
    
    
    # Infos to access source server
    SOURCE_SERVER_TYPE="FTP" # (Script only supports FTP source)
    SOURCE_SERVER_NAME="source_server" # Friendly name
    SOURCE_SERVER_HOST="a.b.c.d" # IP or host or FQDN
    SOURCE_SERVER_PORT="21"
    SOURCE_SERVER_LOGIN="$(hostname)"
    SOURCE_SERVER_PASSWORD='secret'
    SOURCE_SERVER_PATH="/" # Path, on the remote server, where to fetch files
    
    # Infos to access destination server
    DESTINATION_SERVER_TYPE="SSH" # (Script only supports SSH destination)
    DESTINATION_SERVER_NAME="remote_site"
    DESTINATION_SERVER_HOST="destination_server.domain.tld" # IP or host or FQDN
    DESTINATION_SERVER_PORT="22"
    DESTINATION_SERVER_LOGIN="$(hostname)"
    DESTINATION_SERVER_PASSWORD='' # No password means SSH key will be used
    DESTINATION_SERVER_PATH="/mnt/replications/foobar" # Path, on the remote server, where to replicate files (from source)
    
    
    ## AutoFS
    
    # Path where AutoFS will mount the mounted
    CFG_AUTOFS_CONTAINER="/mnt/autofs"
    
    # Name of the AutoFS mount corresponding to the source (cannot contain spaces)
    CFG_AUTOFS_SOURCE_MOUNT_NAME="${SOURCE_SERVER_NAME}"
    CFG_AUTOFS_SOURCE_MOUNT_PATH="${CFG_AUTOFS_CONTAINER}/${CFG_AUTOFS_SOURCE_MOUNT_NAME}"
    
    # Name of the AutoFS mount corresponding to the destination (cannot contain spaces)
    CFG_AUTOFS_DESTINATION_MOUNT_NAME="offsite_replication"
    CFG_AUTOFS_DESTINATION_MOUNT_PATH="${CFG_AUTOFS_CONTAINER}/${CFG_AUTOFS_DESTINATION_MOUNT_NAME}"
    
    ## /AutoFS
    
    
    ## EncFS
    
    #NOTE: Left for future improvements: EncFS source volume:
    #CFG_ENCFS_SOURCE_ENCRYPTION_PASSWORD='secret'
    #CFG_ENCFS_SOURCE_ENCRYPTED_VOLUME_SUBPATH="backups"
    #CFG_ENCFS_SOURCE_MOUNT_POINT="/mnt/${SOURCE_SERVER_NAME}-encfs_access"
    
    # EncFS encrypted volume password
    CFG_ENCFS_DESTINATION_ENCRYPTION_PASSWORD='secret'
    
    # Path to EncFS encrypted volume (relative path, relative to $DESTINATION_SERVER_PATH)
    CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH="foobar"
    
    # Path where EncFS will mount the  directory
    CFG_ENCFS_DESTINATION_MOUNT_POINT="/mnt/offsite_replication-encfs_access"
    
    ## /EncFS
    
    
    ## Scripts
    
    CFG_SCRIPTS_PATH="${CFG_INSTALL_PATH}"
    CFG_SCRIPTS_LOGPATH="/var/log/offsite_replication"
    
    # one-way-mirror script : https://github.com/C-Duv/sysadmin-scripts/tree/master/rsync/one-way-mirror
    CFG_SCRIPTS_ONEWAYMIRROR_DOWNLOAD_URL="https://raw.githubusercontent.com/C-Duv/sysadmin-scripts/master/rsync/one-way-mirror/one-way-mirror-rsync.sh"
    
    # Schedule of replication
    CFG_SCRIPTS_TRANSFEROPERATOR_CRON_TIMESPEC="0    20      *       *       *"


Manual transfer
---------------

Main script file is `encfs+script_wrapper.sh`. It needs the configuration file (will look for `offsite_replication.cfg` if none specified):

```Shell
encfs+script_wrapper.sh [-c config_file] wrapped_script
```

This script is said to be a *wrapper* because it wraps any script (typically a script that does data transfer) with EncFS mounting and unmounting.

An effort is made by this script to support concurrent run: but `wrapped_script` must support it.

`wrapped_script` is run in the same context/scope as `encfs+script_wrapper.sh` so it has access to the same (configuration) variables.


Scheduled transfer
------------------

Installer adds a crontab entry in `/etc/cron.d` that runs `transfer.sh` (via `encfs+script_wrapper.sh`) according to `$CFG_SCRIPTS_TRANSFEROPERATOR_CRON_TIMESPEC`.


Transfer implementation
-----------------------

I am currently using [my *one-way-mirror* rsync script](https://github.com/C-Duv/sysadmin-scripts/tree/master/rsync/one-way-mirror) to perform the transfer.
It is called by `transfer.sh` which is itself wrapped around EncFS mounting/unmounting thanks to `encfs+script_wrapper.sh`.