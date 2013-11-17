#!/bin/bash

# From DAViCal's Wiki "How can I migrate to DAViCal using already generated .ics files?"
# (http://wiki.davical.org/index.php?title=How_can_I_migrate_to_DAViCal_using_already_generated_.ics_files%3F#Import_the_calendars)

URLBASE="http://davical_host/caldav.php"
USR_ADMIN="admin"
PASSWORD_ADMIN=""

# Exported files
if [ ! -d exported_calendars/ ]; then
        echo "Missing exported_calendars/"
        exit 1
fi

find exported_calendars/ -name *.ics | while read i; do
        # Format:
        # exported_calendars/user/name.ics
        USR=`echo "$i"|cut -f 2 -d '/'`
        CALENDAR_NAME=`echo "$i"|cut -f 3 -d '/'|sed 's_\.ics$__g'`

        # For me, default calendar is 'calendar' (change it here)
        # Other calendars (user:xxx) get translated into 'xxx'
        EXPSIMPLE=s/^${USR}\$/calendar/g
        CALENDAR_NAME=`echo "$CALENDAR_NAME"|sed "$EXPSIMPLE"|sed 's_^.*:\(.*\)$_\1_g'`

        echo DEBUG \[$i\] $USR, $CALENDAR_NAME >&2

        # Use cURL
        URL=${URLBASE}/${USR}/${CALENDAR_NAME}/
        curl --insecure --basic --request PUT --header \
                "Content-Type: text/calendar; charset=utf-8" \
                -u ${USR_ADMIN}:${PASSWORD_ADMIN} \
                --data-binary @${i} \
                $URL
        if [ $? -ne 0 ]; then
                echo ERROR with user $USR, calendar $CALENDAR_NAME >&2
        fi
done
