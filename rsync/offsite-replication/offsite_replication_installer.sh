#!/bin/bash

# Script to install and setup a replication from FTP $SOURCE_SERVER_* to SSH $DESTINATION_SERVER_*
#
# I call it offsite_replication because it's main goal is to replicate data on an other server/location
# using SSH as a protection during transfer and EncFS as a protection on the remote server (might not
# totally be under our control).
#
# Replication is done using a one-way-mirror rsync script (see https://github.com/C-Duv/sysadmin-scripts/tree/master/rsync/one-way-mirror)
# The computer running the script accesses FTP source via curlftpfs and SSH destination via SSH.
# External path are automatically mounted via AutoFS
# Destination path is a EncFS encrypted volume (source is not, at the moment)
#
# References:
# * https://wiki.archlinux.org/index.php/autofs#Remote_FTP
# * http://lukaszproszek.blogspot.fr/2008/05/automounting-ftpfs-using-curlftpfs-and.html

if [ `id -u` -ne 0 ]; then
    >&2 echo "Error: Script must be run as root. Aborting."
    exit 1
fi


while getopts ":c:" opt; do
    case $opt in
        # Configuration file
        c)
            CONFIG_FILE="$OPTARG"
            ;;
        \?)
            >&2 echo "Invalid option: -$OPTARG"
            exit 1
            ;;
        :)
            >&2 echo "Option -$OPTARG requires an argument."
            exit 1
            ;;
    esac
done


### Configuration ###
if [ -z "${CONFIG_FILE}" ]; then
    # Default configuration file is offsite_replication.cfg
    CONFIG_FILE="$(dirname "$0")/offsite_replication.cfg"
fi

if [ ! -e "${CONFIG_FILE}" ]; then
    echo "No config file (${CONFIG_FILE} does not exists): will create one for you."
    cat >> "${CONFIG_FILE}" <<'EOT'
# Configuration file for offsite_replication script

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

## /Scripts
EOT
    chmod 0600 "${CONFIG_FILE}"
    >&2 echo "Config file created in \"${CONFIG_FILE}\". Please adjust and restart script."
    exit 2
fi

if [ ! -f "${CONFIG_FILE}" ] || [ ! -r "${CONFIG_FILE}" ]; then
    >&2 echo "Config file \"${CONFIG_FILE}\" is not a readable file: cannot use it as configuration source."
    exit 1
fi

source "${CONFIG_FILE}"
### /Configuration ###



### Functions

# Extract a piggybacked file (from current file)
#
# @param piggyback_code_name    Code name for file in piggyback system
get_piggybacked_file ()
{
    if [ "$#" -ne 1 ]; then
        >&2 echo "Illegal number of parameters."
        >&2 echo "Usage: get_piggybacked_file piggyback_code_name"
        return 1
    fi

    piggyback_code_name="$1"

    #TODO: Handle possible "/" in $piggyback_code_name (because sed won't like it)
    #TODO: Better way of removing BEGIN and END lines
    sed --quiet '/##PBF:'${piggyback_code_name}':BEGIN/,/##PBF:'${piggyback_code_name}':END/p' "$0" | sed '1d' | head --lines=-1
}
### /Functions ###



### Process


# Create folders
mkdir --parents "${CFG_AUTOFS_CONTAINER}"
#mkdir --parents "${CFG_ENCFS_SOURCE_MOUNT_POINT}" #NOTE: Left for future improvements: EncFS source volume
mkdir --parents "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
mkdir --parents "${CFG_SCRIPTS_PATH}"
cp --archive --force "${CONFIG_FILE}" "${CFG_SCRIPTS_PATH}/$(basename "${CONFIG_FILE}")"


# Functions
get_piggybacked_file "functions.sh" > "${CFG_SCRIPTS_PATH}/functions.sh"
source "${CFG_SCRIPTS_PATH}/functions.sh"

get_piggybacked_file "uninstaller.sh" > "${CFG_SCRIPTS_PATH}/uninstaller.sh"
chmod u+x "${CFG_SCRIPTS_PATH}/uninstaller.sh"


# Packages
apt-get --assume-yes --quiet install autofs curlftpfs encfs rsync sshfs wget


## SSH keys

# Warn the user he must place SSH public key on destination server (of SSH key-based auth)
if [ ! -e ~/.ssh/id_rsa.pub ] && [ ! -e ~/.ssh/id_rsa ]; then
    echo "No SSH key at ~/.ssh/id_rsa*, will create one..."
    ssh-keygen -b 4096 -t rsa -N ""
    #TODO: Test the key was created at "~/.ssh/id_rsa.pub" ("-f" option might be useful)
fi
if [ ! -e ~/.ssh/id_rsa.pub ]; then
    >&2 echo "Error: Could not create the SSH key (no file at ~/.ssh/id_rsa.pub). Aborting."
    exit 1
else
    echo "Please authorize the following SSH key for user ${DESTINATION_SERVER_LOGIN} on server ${DESTINATION_SERVER_NAME}:"
    echo "====="
    cat ~/.ssh/id_rsa.pub
    echo "====="
    echo "(Press enter when ready to continue)"
    read
fi

echo "Done with SSH keys."
## /SSH keys


## .netrc file for FTP access
grep -Fxq "machine ${SOURCE_SERVER_HOST}" ~/.netrc
if [ $? -ne 0 ]; then # Found no directive for source server, will add it
    cat >> ~/.netrc <<EOT
machine ${SOURCE_SERVER_HOST}
    login ${SOURCE_SERVER_LOGIN}
    password ${SOURCE_SERVER_PASSWORD}
EOT
fi
## /.netrc file for FTP access


## AutoFS for FTP source
autofs_master_source_map="/- /etc/auto.ftp_${CFG_AUTOFS_SOURCE_MOUNT_NAME}"
grep -Eq "^${autofs_master_source_map}" /etc/auto.master
if [ $? -ne 0 ]; then # AutoFS source map not found
    echo "${autofs_master_source_map} uid=0,gid=0,--timeout=30,--ghost" >> /etc/auto.master # Add the mapping with it's options
fi
#TODO: Remove any existing $autofs_master_source_map line before adding our own?

echo "${CFG_AUTOFS_SOURCE_MOUNT_PATH} -fstype=fuse,ro,nodev,nonempty,noatime \:curlftpfs\#${SOURCE_SERVER_LOGIN}\@${SOURCE_SERVER_HOST}:${SOURCE_SERVER_PORT}${SOURCE_SERVER_PATH}" > /etc/auto.ftp_${CFG_AUTOFS_SOURCE_MOUNT_NAME}
service autofs restart

echo "Will test source AutoFS..."
ls -d "${CFG_AUTOFS_SOURCE_MOUNT_PATH}/." > /dev/null

if [ $? -ne 0 ]; then
    >&2 echo "Error: Obviously, listing of \"${CFG_AUTOFS_SOURCE_MOUNT_PATH}/\" failed, AutoFS must have failed to mount source path \"ftp://${SOURCE_SERVER_LOGIN}@${SOURCE_SERVER_HOST}:${SOURCE_SERVER_PORT}${SOURCE_SERVER_PATH}\". Aborting."
    exit 1
fi

echo "Done with AutoFS for source."
echo ""
## /AutoFS for FTP source


## AutoFS for SSH destination
echo "Will try to connect once to ${DESTINATION_SERVER_HOST} (port ${DESTINATION_SERVER_PORT}) so that you can accept it's RSA key fingerprint..."
echo "(Please verify it and answer \"yes\" to the \"Are you sure you want to continue connecting?\" question below)"
#TODO: Explicitly disable SSH password auth?
echo "====="
ssh -p ${DESTINATION_SERVER_PORT} ${DESTINATION_SERVER_LOGIN}@${DESTINATION_SERVER_HOST} echo 'Successfully connected to `hostname` as `whoami`'
echo "====="
if [ $? -ne 0 ]; then
    >&2 echo "Error: Obviously, SSH connection to ${DESTINATION_SERVER_HOST} as ${DESTINATION_SERVER_LOGIN} failed, either because of RSA fingerprint not accepted or wrong credentials. Aborting."
    exit 1
fi

autofs_master_destination_map="/- /etc/auto.ssh_${CFG_AUTOFS_DESTINATION_MOUNT_NAME}"
grep -Eq "^${autofs_master_destination_map}" /etc/auto.master
if [ $? -ne 0 ]; then # AutoFS source map not found
    echo "${autofs_master_destination_map} uid=0,gid=0,--timeout=30,--ghost" >> /etc/auto.master # Add the mapping with it's options
fi
#TODO: Remove any existing $autofs_master_destination_map line before adding our own?

echo "${CFG_AUTOFS_DESTINATION_MOUNT_PATH} -fstype=fuse,rw,nodev,nonempty,noatime,port=${DESTINATION_SERVER_PORT} \:sshfs\#${DESTINATION_SERVER_LOGIN}@${DESTINATION_SERVER_HOST}:${DESTINATION_SERVER_PATH}" > /etc/auto.ssh_${CFG_AUTOFS_DESTINATION_MOUNT_NAME}
service autofs restart

echo "Make sure \"${DESTINATION_SERVER_PATH}\" exists on ${DESTINATION_SERVER_HOST} and is writeable to ${DESTINATION_SERVER_LOGIN} before continuing"
echo "(Press enter when ready to continue)"
read

echo "Will test destination AutoFS..."
ls -d "${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/." > /dev/null

if [ $? -ne 0 ]; then
    >&2 echo "Error: Obviously, listing of \"${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/\" failed, AutoFS must have failed to mount destination path \"ssh://${DESTINATION_SERVER_LOGIN}@${DESTINATION_SERVER_HOST}:${DESTINATION_SERVER_PATH}\" (port=${DESTINATION_SERVER_PORT}). Aborting."
    exit 1
fi

echo "Done with AutoFS for destination."
echo ""
## /AutoFS for SSH destination


#NOTE: Left for future improvements: EncFS source volume

# EncFS destination volume
if [ ! -f "${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}/.encfs6.xml" ]; then
    echo "\"${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}\" does not contain a EncFS volume: will now create one and mount it once..."

    create_encfs "${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}" "$CFG_ENCFS_DESTINATION_ENCRYPTION_PASSWORD" "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
    destination_encfs_status=$?
else
    echo "Will try to mount EncFS destination on ${CFG_ENCFS_DESTINATION_MOUNT_POINT} once..."

    mount_encfs "${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}" "$CFG_ENCFS_DESTINATION_ENCRYPTION_PASSWORD" "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
    destination_encfs_status=$?
fi

if [ $destination_encfs_status -eq 0 ]; then
    echo "EncFS destination mounting looks successful, content list should follow:"
    echo "====="
    ls -l "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
    echo "====="
    echo "(Press enter when ready to continue)"
    read
    echo "Will now unmount EncFS destination..."
    fusermount -u "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
fi

echo "Done with EncFS for destination."
echo ""


## Scripts

# transfer-operator script
mkdir --parents "${CFG_SCRIPTS_PATH}/transfer-operator"
mkdir --parents "${CFG_SCRIPTS_LOGPATH}/transfer-operator"

scripts_onewaymirrorrsync_script_filepath="${CFG_SCRIPTS_PATH}/transfer-operator/one-way-mirror-rsync.sh"
scripts_onewaymirrorrsync_config_filepath="${CFG_SCRIPTS_PATH}/transfer-operator/${SOURCE_SERVER_NAME}.cfg"
scripts_onewaymirrorrsync_log_filepath="${CFG_SCRIPTS_LOGPATH}/transfer-operator/${SOURCE_SERVER_NAME}.log"

wget --quiet --output-document="${scripts_onewaymirrorrsync_script_filepath}" ${CFG_SCRIPTS_ONEWAYMIRROR_DOWNLOAD_URL}
chmod u+x "${scripts_onewaymirrorrsync_script_filepath}"
cat > "${scripts_onewaymirrorrsync_config_filepath}" <<EOT
# Configuration

rsyncExecutable="$(which rsync)"
#rsyncIncludeList="$(dirname "${scripts_onewaymirrorrsync_script_filepath}")/${SOURCE_SERVER_NAME}.rsync-include-list"
rsyncLogFilepath="${scripts_onewaymirrorrsync_log_filepath}"
#rsyncOtherOptions="--no-whole-file"
#rsyncRshOtherOptions="--bwlimit=1000"

sshExecutable="$(which ssh)"

lockFilepath="$(dirname "${scripts_onewaymirrorrsync_script_filepath}")/${SOURCE_SERVER_NAME}.lock"

# Source:
sourceDirpath="${CFG_AUTOFS_SOURCE_MOUNT_PATH}/"

# Destination:
destinationDirpath="${CFG_ENCFS_DESTINATION_MOUNT_POINT}/"

dryRun=0
verbose=0
EOT


get_piggybacked_file "encfs+script_wrapper.sh" > "${CFG_SCRIPTS_PATH}/encfs+script_wrapper.sh"
chmod u+x "${CFG_SCRIPTS_PATH}/encfs+script_wrapper.sh"
get_piggybacked_file "transfer.sh" > "${CFG_SCRIPTS_PATH}/transfer.sh"
chmod u+x "${CFG_SCRIPTS_PATH}/encfs+script_wrapper.sh"


# Cronjob
cat > "/etc/cron.d/${SOURCE_SERVER_NAME//./_}_offsite_replication" <<EOT
#   (...time specs...)    User    Command
    ${CFG_SCRIPTS_TRANSFEROPERATOR_CRON_TIMESPEC}    root    "${CFG_SCRIPTS_PATH}/encfs+script_wrapper.sh" -c "${CFG_SCRIPTS_PATH}/$(basename "${CONFIG_FILE}")" "${CFG_SCRIPTS_PATH}/transfer.sh" 2>&1
EOT

# Logrotate
cat > "/etc/logrotate.d/${SOURCE_SERVER_NAME//./_}_offsite_replication" <<EOT
${scripts_onewaymirrorrsync_log_filepath} {
    weekly
    rotate 52
    compress
    delaycompress
    notifempty
    missingok
}
EOT

## /Scripts

echo "Installation done."
echo "Configuration file \"${CONFIG_FILE}\" has been copied to \""${CFG_SCRIPTS_PATH}/$(basename "${CONFIG_FILE}")"\"."
echo "Please adapt rsync configuration file \"${scripts_onewaymirrorrsync_config_filepath}\"."

### /Process

# Mandatory exit code when using file piggy-backing
exit 0


### Piggy-backed files

# The following are files that are included within this script for ease of deployment (single file to send)
#
# Tokens delimiting start and end of files:
# * ##PBF:code_name:BEGIN    : Indicates next first line of file
# * ##PBF:code_name:END      : Indicates past last line of file
#
# "code_name" is an internal name of the block. Cannot contains "/"
################################################################################################################################################################
##PBF:functions.sh:BEGIN
#!/bin/bash

# This file is part of the "offsite_replication" script
#
# It contains only (shared) functions

# Tells if a path is already a mountpoint
#
# @param path
# @return int    0 if is not a mountpoint, 1 otherwise
is_mount_point ()
{
    mount | grep --extended-regexp --quiet "^[^[:space:]]+ on $1 type " # Test if mounted or not
    if [ $? -eq 0 ]; then
        return 1
    else
        return 0
    fi
}

# Create an EncFS volume
#
# @param encfs_volume_path
# @param volume_password
# @param mount_point_path
#
# @return int    0 if volume mounting went OK
#                1 if volume location and/or mount point could not be found
#                2 if volume mounting failed
#                3 if volume is already mounted
#                4 if volume already exists
create_encfs ()
{
    if [ "$#" -ne 3 ]; then
        >&2 echo "Illegal number of parameters."
        >&2 echo "Usage: create_encfs encfs_volume_path volume_password mount_point_path"
        return 1
    fi

    encfs_volume_path="$1"
    volume_password="$2"
    mount_point_path="$3"

    if [ ! -d "${encfs_volume_path}" ]; then
        mkdir --parents "${encfs_volume_path}"
    fi
    if [ ! -d "${mount_point_path}" ]; then
        mkdir --parents "${mount_point_path}"
    fi
    if [ ! -d "${encfs_volume_path}" ] || [ ! -d "${mount_point_path}" ]; then
        >&2 echo "Error: EncFS volume location (\"${encfs_volume_path}/\") and/or EncFS mount point (\"${mount_point_path}\") does not exists and we failed to create one or both. Aborting."
        return 1
    elif [ -f "${encfs_volume_path}/.encfs6.xml" ]; then
        >&2 echo "Error: \"${encfs_volume_path}/\" already contains an EncFS volume. Aborting."
        return 4
    else
        is_mount_point "${mount_point_path}" # Test if mount point already used
        if [ $? -eq 1 ]; then # mount point is in use
            >&2 echo "Error: \"${mount_point_path}/\" is already mounted. Aborting."
            return 3
        else
            UNATTENDED_TEMPFILE=$(mktemp) # Will contain answers to creation wizard (uses "pre-configured paranoia mode")
            cat >> "${UNATTENDED_TEMPFILE}" <<EOT
p
${volume_password}
${volume_password}
EOT
            cat "${UNATTENDED_TEMPFILE}" | encfs --stdinpass "${encfs_volume_path}" "${mount_point_path}"
            encfs_creation_result=$?
            rm "${UNATTENDED_TEMPFILE}"

            if [ ${encfs_creation_result} -ne 0 ]; then
                >&2 echo "Error: Obviously, EncFS volume creation on \"${encfs_volume_path}\" failed (exit code: ${encfs_mount_result})."
                >&2 echo "You can try to create it manually with the following command (attempted: \"pre-configured paranoia mode\"):"
                >&2 echo "encfs \"${encfs_volume_path}\" \"${mount_point_path}\""
                >&2 echo "Aborting."
                return 2
            fi
        fi
        # Post-relation: EncFS volume is mounted
        return 0
    fi
}

# Mount an EncFS volume
#
# @param encfs_volume_path
# @param volume_password
# @param mount_point_path
#
# @return int    0 if volume mounting went OK
#                1 if volume location and/or mount point could not be found
#                2 if volume mounting failed
#                3 if volume is already mounted
mount_encfs ()
{
    if [ "$#" -ne 3 ]; then
        >&2 echo "Illegal number of parameters."
        >&2 echo "Usage: mount_encfs encfs_volume_path volume_password mount_point_path"
        return 1
    fi

    encfs_volume_path="$1"
    volume_password="$2"
    mount_point_path="$3"

    if [ ! -d "${encfs_volume_path}" ]; then
        mkdir --parents "${encfs_volume_path}"
    fi
    if [ ! -d "${mount_point_path}" ]; then
        mkdir --parents "${mount_point_path}"
    fi
    if [ ! -d "${encfs_volume_path}" ] || [ ! -d "${mount_point_path}" ]; then
        >&2 echo "Error: EncFS volume location (\"${encfs_volume_path}/\") and/or EncFS mount point (\"${mount_point_path}\") does not exists and we failed to create one or both. Aborting."
        return 1
    else
        is_mount_point "${mount_point_path}" # Test if mount point already used
        if [ $? -eq 1 ]; then # mount point is in use
            >&2 echo "Error: \"${mount_point_path}/\" is already mounted. Aborting."
            return 3
        else
            PASSWORD_TEMPFILE=$(mktemp)
            echo "$volume_password" > "${PASSWORD_TEMPFILE}"
            cat "${PASSWORD_TEMPFILE}" | encfs --stdinpass "${encfs_volume_path}" "${mount_point_path}"
            encfs_mount_result=$?
            rm "${PASSWORD_TEMPFILE}"

            if [ ${encfs_mount_result} -ne 0 ]; then
                >&2 echo "Error: Obviously, mounting of EncFS volume \"${encfs_volume_path}\" failed (exit code: ${encfs_mount_result}), maybe the password is incorrect?"
                >&2 echo "You can try to mount it manually with the following command:"
                >&2 echo "encfs \"${encfs_volume_path}\" \"${mount_point_path}\""
                >&2 echo "Aborting."
                return 2
            fi
        fi
        # Post-relation: EncFS is mounted
        return 0
    fi
}

##PBF:functions.sh:END
################################################################################################################################################################

################################################################################################################################################################
##PBF:encfs+script_wrapper.sh:BEGIN
#!/bin/bash

# This script is part of the "offsite_replication" script
#
# Script to mount EncFS volumes, run a script and then umount the EncFS volumes.
# As this script can be run concurrently (already mounted volume will not trigger an error), the wrapped script must deal it (eg. lock mechanism).
#
# Debug notes:
# * A FUSE mount point can be unmounted via: fusermount -u {mount-point}
#
# Usage:
#     encfs+script_wrapper.sh [-c config_file] wrapped_script
# Operands:
# * wrapped_script    Filepath of the wrapped script.
#                     This script will be executed once the EncFS volume is mounted. EncFS volume will be unmounted once the script ends.
#                     It can set the variable "wrapped_script_exit_code" with exit code that wrapper must exit with.
#                     To browse EncFS volume, make a shell script that pause (or sleep) and use it as the wrapped_script.
# Options:
# * -c config_file    (Optional) Filepath of the configuration file. Default value is "offsite_replication.cfg"
#
# Exit codes:
# * 1 if usage/parameters error
# * 2 if EncFS volume mounting/unmounting error

if [ `id -u` -ne 0 ]; then
    >&2 echo "Error: Script must be run as root. Aborting."
    exit 1
fi


while getopts ":c:" opt; do
    case $opt in
        # Configuration file
        c)
            CONFIG_FILE="$OPTARG"
            ;;
        \?)
            >&2 echo "Invalid option: -$OPTARG"
            exit 1
            ;;
        :)
            >&2 echo "Option -$OPTARG requires an argument."
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ "$#" -ne 1 ]; then
    >&2 echo "Illegal number of parameters."
    >&2 echo "Usage: $0 [-c config_file] wrapped_script"
    exit 1
fi

WRAPPED_SCRIPT="$1"

### Configuration ###
if [ -z "${CONFIG_FILE}" ]; then
    # Default configuration file is offsite_replication.cfg
    CONFIG_FILE="$(dirname "$0")/offsite_replication.cfg"
fi

if [ ! -f "${CONFIG_FILE}" ] || [ ! -r "${CONFIG_FILE}" ]; then
    >&2 echo "Config file \"${CONFIG_FILE}\" is not a readable file: cannot use it as configuration source."
    exit 1
fi

if [ ! -f "${WRAPPED_SCRIPT}" ] || [ ! -r "${WRAPPED_SCRIPT}" ]; then
    >&2 echo "Wrapped script \"${WRAPPED_SCRIPT}\" is not a readable file: cannot use it."
    exit 1
fi

source "${CONFIG_FILE}"
### /Configuration ###


# Load shared functions
source "${CFG_SCRIPTS_PATH}/functions.sh"


### Process

#TODO: Check if both AutoFS path (source and destination) are up ("source" to avoid wiping the destination, "destination" to avoid writing to local disk)

#NOTE: Left for future improvements: Mount EncFS source volume
## Mount EncFS source volume
#mount_encfs "${CFG_AUTOFS_SOURCE_MOUNT_PATH}/${CFG_ENCFS_SOURCE_ENCRYPTED_VOLUME_SUBPATH}" "$CFG_ENCFS_SOURCE_ENCRYPTION_PASSWORD" "${CFG_ENCFS_SOURCE_MOUNT_POINT}"

# Mount EncFS destination volume
mount_encfs "${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}" "$CFG_ENCFS_DESTINATION_ENCRYPTION_PASSWORD" "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
mount_return_code=$?
if [ $mount_return_code -ne 0 ] && [ $mount_return_code -ne 3 ]; then
    >&2 echo "Error: Failed to mount destination EncFS volume (\"${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}\")."
    exit 2
fi

# Start with no error
wrapped_script_exit_code=0

# Run wrapped script in the same context/scope
source "${WRAPPED_SCRIPT}"


#NOTE: Left for future improvements: Unmount EncFS source volume
## Unmount EncFS destination volume
#fusermount -u "${CFG_AUTOFS_SOURCE_MOUNT_PATH}/${CFG_ENCFS_SOURCE_ENCRYPTED_VOLUME_SUBPATH}"
#if [ $? -ne 0 ]; then
#    >&2 echo "Error: Failed to unmount EncFS source."
#fi

# Unmount EncFS destination volume
fusermount -u "${CFG_ENCFS_DESTINATION_MOUNT_POINT}"
if [ $? -ne 0 ]; then
    >&2 echo "Error: Failed to unmount destination EncFS volume (\"${CFG_AUTOFS_DESTINATION_MOUNT_PATH}/${CFG_ENCFS_DESTINATION_ENCRYPTED_VOLUME_SUBPATH}\")."
    exit 2
fi

if [ $wrapped_script_exit_code -ne 0 ]; then # Did transfer failed?
    exit $wrapped_script_exit_code # Return it's error code if it did
fi

### /Process

##PBF:encfs+script_wrapper.sh:END
################################################################################################################################################################

################################################################################################################################################################
##PBF:transfer.sh:BEGIN
#!/bin/bash

# This script is part of the "offsite_replication" script
#
# Script that actually perform the data transfer.
# As this script can be run concurrently by the wrapper.sh, the wrapped script must deal it (eg. lock mechanism).
#
# Exit codes:
# * 0 if tranfer w


# Perform the transfer with "one-way-mirror-rsync.sh"
"${CFG_SCRIPTS_PATH}/transfer-operator/one-way-mirror-rsync.sh" -c "${CFG_SCRIPTS_PATH}/transfer-operator/${SOURCE_SERVER_NAME}.cfg" 2>&1
wrapped_script_exit_code=$?
if [ $wrapped_script_exit_code -eq 3 ]; then
    echo "one-way-mirror-rsync is already running."
    exit 0
elif [ $wrapped_script_exit_code -ne 0 ]; then
    >&2 echo "Error: one-way-mirror-rsync failed."
fi

##PBF:transfer.sh:END
################################################################################################################################################################

################################################################################################################################################################
##PBF:uninstaller.sh:BEGIN
#!/bin/bash

# This script is part of the "offsite_replication" script
#
# Script to uninstall what the installer made:
# remove cronjobs, logrotate and script files
# Configuration and auth files are kept

if [ `id -u` -ne 0 ]; then
    >&2 echo "Error: Script must be run as root. Aborting."
    exit 1
fi


while getopts ":c:" opt; do
    case $opt in
        # Configuration file
        c)
            CONFIG_FILE="$OPTARG"
            ;;
        \?)
            >&2 echo "Invalid option: -$OPTARG"
            exit 1
            ;;
        :)
            >&2 echo "Option -$OPTARG requires an argument."
            exit 1
            ;;
    esac
done


### Configuration ###
if [ -z "${CONFIG_FILE}" ]; then
    # Default configuration file is offsite_replication.cfg
    CONFIG_FILE="$(dirname "$0")/offsite_replication.cfg"
fi

if [ ! -f "${CONFIG_FILE}" ] || [ ! -r "${CONFIG_FILE}" ]; then
    >&2 echo "Config file \"${CONFIG_FILE}\" is not a readable file: cannot use it as configuration source."
    exit 1
fi

source "${CONFIG_FILE}"
### /Configuration ###


### Process

sed --in-place '\,/- /etc/auto.ftp_'${CFG_AUTOFS_SOURCE_MOUNT_NAME}',d' /etc/auto.master
sed --in-place '\,/- /etc/auto.ssh_'${CFG_AUTOFS_DESTINATION_MOUNT_NAME}',d' /etc/auto.master

rm "${CFG_SCRIPTS_PATH}/functions.sh"
rm "${CFG_SCRIPTS_PATH}/encfs+script_wrapper.sh"
rm "${CFG_SCRIPTS_PATH}/transfer.sh"
rm "${CFG_SCRIPTS_PATH}/transfer-operator/one-way-mirror-rsync.sh"

rm "/etc/cron.d/${SOURCE_SERVER_NAME//./_}_offsite_replication"
rm "/etc/logrotate.d/${SOURCE_SERVER_NAME//./_}_offsite_replication"

rm "$0"

echo "Uninstallation done."

### /Process

##PBF:uninstaller.sh:END
################################################################################################################################################################

### /Piggy-backed files
