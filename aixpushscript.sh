######################################################################################
# Test AIX Push Script                                                               #
# Created by: Phil Schaefer                                                          #
# Created on: 1/6/2016                                                               #
# Updated on: 1/26/2016                                                              #
#                                                                                    #
######################################################################################
# Use: Runs specified script on servers in specified host file                       #
# Syntax: aixpushscript <hostfilename> <script to run>                               #
# Example: aixpushscript.sh hosts.txt getoslevel.sh                                  #
#                                                                                    #
# When run this script will dump output to a logfile in the same folder called       #
# <scriptname>.out.  If the file already exists it will append to the current file   #
# and put the current date before the new output                                     #
#                                                                                    #
######################################################################################

#!/usr/bin/ksh

usage(){
        print AIX Push Script - Run your script on specified list of servers in a file.
        print "Usage: aixpushscript.sh [-l] hostlistfile [-s] script"
}

while getopts "l:s:h" OPTION
do
        case $OPTION in
                l)
                  HOSTFILE=$OPTARG
                  ;;
                s)
                  SCRIPT=$OPTARG
                  ;;
                h|*)
                  usage
                  exit 1
                  ;;
        esac
done
shift $((OPTIND -1))

if [ -z "$HOSTFILE" ] ; then
        usage
        print ERROR: no hostlistfile specified
        exit
fi

if [ -z "$SCRIPT" ]; then
        usage
        print ERROR: no script specified
        exit 1
fi

SOURCE=/home/pschaefer/scripts
LOGFILE="${SCRIPT}.out"
LOGDIR=/home/pschaefer/scripts/logs

echo "Running $SCRIPT on servers in $HOSTFILE"
echo "******************** `date` ********************" >> $LOGDIR/$LOGFILE

for SERVER in `cat $SOURCE/$HOSTFILE | grep -v "#"`
        do
                echo $SERVER
                ssh -q -o "BatchMode yes" $SERVER 'ksh 2>&1' < $SOURCE/$SCRIPT
        done >> $LOGDIR/$LOGFILE

echo "$SCRIPT has finished running on servers in ${HOSTFILE}. Please check $LOGDIR/$LOGFILE for the results"
