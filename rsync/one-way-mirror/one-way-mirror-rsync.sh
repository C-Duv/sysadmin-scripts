#!/bin/bash

##
# Perform a one-way mirroring of files via rsync
# 
# This script will mirror a given source path to a given destination using
# rsync. Mode is "one-way mirror": so any file that is on destination but
# does not exists on source will be deleted from destination.
# At the end of the script, content of source will match content of destination
# (minus any exclusion that is set).
# 
# @author DUVERGIER Claude
##

while getopts ":c:" opt; do
    case $opt in
        # Configuration file
        c)
            CONFIG_FILE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

## Configuration ##
if [ -z "$CONFIG_FILE" ]; then
    # Default configuration file is <name of the script>.cfg
    CONFIG_FILE="${0%.*}.cfg"
fi

if [ ! -e "$CONFIG_FILE" ]; then
    echo "No config file ($CONFIG_FILE does not exists): will create one for you."
    cat >> "$CONFIG_FILE" <<'EOT'
# Configuration

rsyncExecutable="/usr/bin/rsync"
#rsyncIncludeList="$(dirname "$0")/rsync-include-list"
rsyncLogFilepath="$0.log"
#rsyncOtherOptions="--cvs-exclude"
#rsyncRshOtherOptions="-T -o Compression=no -x"

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

# Change value to 1 to perform a dry run (default: 0)
dryRun=0

# Sets verbosity level (default: 0)
verbose=0
EOT
    chmod 0600 "$CONFIG_FILE"
    echo "Config file created in \"$CONFIG_FILE\". Please adjust and restart script."
    exit 2
fi

if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
    echo "Config file \"$CONFIG_FILE\" is not a readable file: cannot use it as configuration source."
    exit 1
fi

source "$CONFIG_FILE"

if [ ! -e "$rsyncExecutable" ] || [ ! -x "$rsyncExecutable" ]; then
    echo "rsync location \"$rsyncExecutable\" declared in configuration is not an executable file: cannot use it."
    exit 1
fi

if [ -n "$rsyncIncludeList" ]; then
    if [ ! -e "$rsyncIncludeList" ] || [ ! -r "$rsyncIncludeList" ] || [ ! -f "$rsyncIncludeList" ]; then
        echo "Include list file \"$rsyncIncludeList\" declared in configuration is not a readable file: cannot use it."
        exit 1
    fi
fi

if [ -n "$rsyncLogFilepath" ]; then
    if [ -e "$rsyncLogFilepath" ]; then
        if [ ! -w "$rsyncLogFilepath" ] || [ ! -f "$rsyncLogFilepath" ]; then
            echo "Log file \"$rsyncLogFilepath\" declared in configuration is not a writable file: cannot use it."
            exit 1
        fi
    elif [ ! -w "$(dirname "$rsyncLogFilepath")" ]; then
        echo "Cannot create the log file \"$rsyncLogFilepath\" declared in configuration: Cannot write here."
        exit 1
    fi
fi

if [ -e "$lockFilepath" ]; then
    if [ ! -r "$lockFilepath" ] || [ ! -w "$lockFilepath" ] || [ ! -f "$lockFilepath" ]; then
        echo "Log file \"$lockFilepath\" declared in configuration is not a readable-writable file: cannot use it."
        exit 1
    fi
elif [ ! -w "$(dirname "$lockFilepath")" ]; then
    echo "Cannot create the lock file \"$lockFilepath\" declared in configuration: Cannot write here."
    exit 1
fi
## /Configuration ##


# Use lock to avoid multiple run
exec 9>$lockFilepath
if ! flock -n 9 ; then
    echo "I can tell $0 script is already running ($lockFilepath is present since $(stat -c %z $lockFilepath))... exiting this instance"
    exit 1
fi


## Rsync command creation ##
includeFromPart=()
if [ -n "$rsyncIncludeList" ]; then
    includeFromPart=(--include-from="$rsyncIncludeList")
fi

rsyncRshOtherOptionsPart=()
if [ -n "$rsyncRshOtherOptions" ]; then
    rsyncRshOtherOptionsPart=($rsyncRshOtherOptions)
fi

rshPart=""
# Source parameter
if [ -n "$sourceHost" ]; then
    sourcePart="$sourceUser@$sourceHost:$sourceDirpath"
    if [ -n "$sourceUserPrivateKeyFilepath" ] || [ -n "$sourceSshPort" ]; then
        rshPart="\"$sshExecutable\""
        if [ -n "$sourceUserPrivateKeyFilepath" ]; then
            rshPart="$rshPart -i \"$sourceUserPrivateKeyFilepath\""
        fi
        if [ -n "$sourceSshPort" ]; then
            rshPart="$rshPart -p $sourceSshPort"
        fi
        rshPart="$rshPart ${rsyncRshOtherOptionsPart[@]}"
        rshPart=(--rsh="$rshPart")
    fi
else
    sourcePart="$sourceDirpath"
fi

# Destination parameter:
if [ -n "$destinationHost" ]; then
    destinationPart="$destinationUser@$destinationHost:$destinationDirpath"
    if [ -n "$destinationUserPrivateKeyFilepath" ] || [ -n "$destinationSshPort" ]; then
        if [ -n "$rshPart" ]; then
            echo "It seems that you specified either private key file or SSH port for both source and destination: \
            Sorry I'm not smart enough to do that."
            exit 1
        fi
        rshPart="\"$sshExecutable\""
        if [ -n "$destinationUserPrivateKeyFilepath" ]; then
            rshPart="$rshPart -i \"$destinationUserPrivateKeyFilepath\""
        fi
        if [ -n "$destinationSshPort" ]; then
            rshPart="$rshPart -p $destinationSshPort"
        fi
        rshPart="$rshPart ${rsyncRshOtherOptionsPart[@]}"
        rshPart=(--rsh="$rshPart")
    fi
else
    destinationPart="$destinationDirpath"
fi

otherRsyncOptionsPart=()
if [ $dryRun -eq 1 ]; then
    otherRsyncOptionsPart+=(--dry-run)
fi
if [ $verbose -ge 1 ]; then
    for (( i=1; i<=$verbose; i++ )); do
        otherRsyncOptionsPart+=(--verbose)
    done
fi
if [ -n "$rsyncOtherOptions" ]; then
    otherRsyncOptionsPart+=($rsyncOtherOptions)
fi
## /Rsync command creation ##


## Run rsync ##
rsyncCommand=($rsyncExecutable \
    --log-file="$rsyncLogFilepath" \
    "${includeFromPart[@]}" \
    --recursive --links --times --group --owner --devices --specials --compress \
    --delete --delete-before --delete-excluded \
    "${otherRsyncOptionsPart[@]}" \
    "${rshPart[@]}" \
    "$sourcePart" \
    "$destinationPart"
)
${rsyncCommand[@]}
## /Run rsync ##
