#!/usr/bin/ksh

AIXTEAMEMAIL=""
LOGDIR="/usr/local/bin/Restores"
LOGFILE="RestoreLog"
#Document to get VG name from PVID of incoming disk and hostname. Used in GETDISKINFO 
DR_VGINFO="/usr/local/bin/DR_VGINFO.DOC"
#Command for lsviocfg with full path. Used in GETDISKINFO
#lsviocfg is a custom utility we built to pull information from our 3par arrays for information such as lun ID, size, etc.
#example output: hdisk0 (Avail pv rootvg) 72A913E6  3PAR-id=5094-DADR01004-p_dev_vg_maltr004.0 VOL-id=29353
LSVIOCFG="/usr/local/bin/lsviocfg"
#Directory where mounted snap will be mounted on client as well as on this server where snaps will be mounted
RESTOREDIR="/RESTORE"
#The following are used in GETDISKINFO to hold various info about the disk in question
VGID=""
PVCOUNT=""
VGNAME=""
HPSAN=""
HPSANFILE=""
LUNID=""
HOST=""
DISKLIST=""
SNAPDATE=""
#TMPVGNAME is used to record what VG is created when recreating the VG in IMPORTVG
TMPVGNAME=""
#Used to track whether duplicate PVIDs are detected in PVIDCHECK. If so we will need to check /tmp/duplicatepvids.txt for PVIDs of disks that in a volume group with multiple disks
DUPLICATES=""
#Used to flag if a disk is missing from a multidisk VG
MISSINGDISKS="no"

MISSINGDISKINFO=""
VVWWN=""
VVWWNFILE=""

CHECKDISKS () #check for new disks on server and build a list of disk names in newdisk.txt
{
        lspv | awk '{print $1}' > /tmp/disks1.txt
        cfgmgr
        lspv | awk '{print $1}' > /tmp/disks2.txt
        diff /tmp/disks1.txt /tmp/disks2.txt | grep ">" | sed 's/> //g' > /tmp/newdisks.txt
        if [ "$(cat /tmp/newdisks.txt | wc -l)" -eq "0" ] ; then
                cat /tmp/newdisks.txt > /tmp/newdiskskeep.txt
                rm /tmp/newdisks.txt
                exit
        fi
        echo "New Disk found."
        cat /tmp/newdisks.txt > /tmp/newdiskskeep.txt
}

PVIDCHECK ()
{
        if [ -z "$(lspv | awk '{print $2}' | sort | uniq -d | grep -v none)" ] ; then
                echo "Each disk is unique" >> $LOGDIR/$LOGFILE
                DUPLICATES="no"
        else
                echo "Duplicate PVIDs detected. Multiple snap dates have been attached for the same VG." >> $LOGDIR/$LOGFILE
                DUPLICATES="yes"

        fi
}


GETDISKINFO () #Must pass this function disk name. Gathers info needed from VGDA, DR INFO doc, and SAN Info Docs.
{
        GDIDISK="$1"
        #VGID="$(readvgda -q $GDIDISK | grep VGID: | awk '{print $2}')"
        PVCOUNT="$(readvgda -q $GDIDISK | grep "PV count:" | awk '{print $3}')"
        HPSAN="$($LSVIOCFG $GDIDISK | awk '{print $5}' | sed 's/.*\(....\)/\1/')"
        case $HPSAN in
                13E7 )
                        HPSANFILE="/tmp/DA1101004.txt"
                        VVWWNFILE="/tmp/VVWWN_DA1101004.txt"
                        ;;
                ADEB )
                        HPSANFILE="/tmp/DA1101001.txt"
                        VVWWNFILE="/tmp/VVWWN_DA1101001.txt"
                        ;;
                13E6 )
                        HPSANFILE="/tmp/DADR01004.txt"
                        VVWWNFILE="/tmp/VVWWN_DADR01004.txt"
                        ;;
                ADE9 )
                        HPSANFILE="/tmp/DADR01001.txt"
                        VVWWNFILE="/tmp/VVWWN_DADR01001.txt"
                        ;;
        esac
        VVWWN="$($LSVIOCFG $GDIDISK | awk '{print $5}')"
        #Just trust that I know what I'm doing when I get VGNAME and HOST.  This whole script is my proudest and sadest moment rolled into one. Special thanks to FLUKEN.
        VGNAME="$(grep $VVWWN $VVWWNFILE | awk '{print $1}' | xargs -I\^ grep -w \^ $HPSANFILE | awk '{print $6}' | xargs -I\^ grep \^ $HPSANFILE | grep base | awk '{print $2}' | xargs -I\^ grep \^ $VVWWNFILE | awk '{print $10}' | sed 's/.*\(........\)/\1/' | xargs -I\^ grep \^ $DR_VGINFO | awk '{print $2}')"
        HOST="$(grep $VVWWN $VVWWNFILE | awk '{print $1}' | xargs -I\^ grep -w \^ $HPSANFILE | awk '{print $6}' | xargs -I\^ grep \^ $HPSANFILE | grep base | awk '{print $2}' | xargs -I\^ grep \^ $VVWWNFILE | awk '{print $10}' | sed 's/.*\(........\)/\1/' | xargs -I\^ grep \^ $DR_VGINFO | awk '{print $1}')"
        LUNID="$(grep $VVWWN $VVWWNFILE | awk '{print $1}')"
        SNAPDATE="$(awk '$1 ~ /^'$LUNID'$/ {print $5}' $HPSANFILE | sed 's/.*-//' | sed 's/\(.........\).*/\1/')"
}

REFRESHSANINFO ()
{
        echo "Updating 3PAR SAN info files" >> $LOGDIR/$LOGFILE
        ssh -i /.ssh/id_rsa.repl aixedit@DA1101001 "showvv -showcols Id,Name,Prov,Type,CopyOf,BsId" > /tmp/DA1101001.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DA1101001 "showvv -d" > /tmp/VVWWN_DA1101001.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DA1101004 "showvv -showcols Id,Name,Prov,Type,CopyOf,BsId" > /tmp/DA1101004.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DA1101004 "showvv -d" > /tmp/VVWWN_DA1101004.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DADR01001 "showvv -showcols Id,Name,Prov,Type,CopyOf,BsId" > /tmp/DADR01001.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DADR01001 "showvv -d" > /tmp/VVWWN_DADR01001.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DADR01004 "showvv -showcols Id,Name,Prov,Type,CopyOf,BsId" > /tmp/DADR01004.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DADR01004 "showvv -d" > /tmp/VVWWN_DADR01004.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DA00010001P "showvv -showcols Id,Name,Prov,Type,CopyOf,BsId" > /tmp/DA00010001P.txt
        ssh -i /.ssh/id_rsa.repl aixedit@DA00010001P "showvv -d" > /tmp/VVWWN_DA00010001P.txt
}

CLEARPVIDS ()
{
        #Clear PVIDs on disks in disk list and create new ones
        for i in `echo $DISKLIST | tr ' ' '\n'`
                do
                        chdev -a pv=clear -l $i
                        chdev -a pv=yes -l $i
                done
}

IMPORTVG ()
{
        #Import the VG specifying all disks needed. The -L is ridiculously big to force default lv names
        echo "All disks for $VGNAME on $HOST are found for snap (MMDD_HHMM) $SNAPDATE.  Recreating the VG" >> $LOGDIR/$LOGFILE
        TMPVGNAME="$(recreatevg -L "$RESTOREDIR/$HOST/$VGNAME$SNAPDATE" -Y "asbkljasdlkjsaldkhglkjsdlkjsdlfkjhsalkjsdlkjglk" "$DISKLIST")"
        RC=$?
        if [[ $RC -gt 0 ]] then
                echo "recreating $VGNAME has failed" >> $LOGDIR/$LOGFILE
                exit
        fi
}

MOUNTANDEXPORT ()
{
        #mount filesystems
        lsvg -l $TMPVGNAME | awk 'NR > 2 {print $7}' | grep -v "N/A" | sort -d | xargs -I ^ mount ^

        #Check to see that all file systems mounted
        if [ "$(lsvg -l $TMPVGNAME | grep -v "N/A" | grep closed | awk '{print $7}' | wc -l)" -ne "0" ] ; then
                echo "The following filesystems did not mount for VG $TMPVGNAME:
                $(lsvg -l $TMPVGNAME | grep -v "N/A" | grep closed | awk '{print $7}')" >> $LOGDIR/$LOGFILE
                echo "The following filesystems did not mount for VG $TMPVGNAME:
                $(lsvg -l $TMPVGNAME | grep -v "N/A" | grep closed | awk '{print $7}')" | mail -s "Filesystems failed to mount on mchir045" $AIXTEAMEMAIL
        fi

        #Change folder permissions
        chmod 766 $RESTOREDIR/$HOST
        chmod 766 $RESTOREDIR/$HOST/$VGNAME$SNAPDATE

        #export base folder for host and all filesystems. Uhg.
        mknfsexp -d $RESTOREDIR/$HOST -t ro -h $HOST -r $HOST
        lsvg -l $TMPVGNAME | grep -v N/A | awk 'NR > 2 {print $7}' | sort | xargs -I^ mknfsexp -d ^ -t ro -h $HOST -r $HOST

        #NFS mount on host
        #Build Mount Script for all filesystems in the recreated VG
        for i in `lsvg -l $TMPVGNAME | grep -v N/A | awk 'NR > 2 {print $7}' | sort`
        do
                echo "sudo mount mchir045:$i \`echo $i | sed 's/\\/$HOST//g'\`" >> /tmp/mount$HOST.sh
        done

        #Make mount script executable
        chmod +x /tmp/mount$HOST.sh

        #Mount base directory on host then copy mount script over and run on host.  Remove mount script from host and mchir045
        MOUNTCMD="ssh $HOST \"sudo mount mchir045:/$RESTOREDIR/$HOST $RESTOREDIR\" "
        su - ifreling -c " $MOUNTCMD "
        su - ifreling -c "scp /tmp/mount$HOST.sh $HOST:/tmp"
        su - ifreling -c "ssh $HOST /tmp/mount$HOST.sh"
        su - ifreling -c "ssh $HOST rm /tmp/mount$HOST.sh"
        rm /tmp/mount$HOST.sh


}

FSCKFILESYSTEMS ()
{
        for FS in `lsvg -l $TMPVGNAME | awk 'NR > 2 {print $7}' | grep -v "N/A"`
                do
                        fsck -y $FS
                        RC=$?
                        if [ "$RC" = "4" ] ; then
                                echo "Filesystem check on $FS for $TMPVGNAME has File system errors left uncorrected" >> $LOGDIR/$LOGFILE
                        fi
                done
}

BUILDDISKLIST ()
{
        #If only one disk set the disklist to be just that disk and if there were duplicate PVIDs detected remove it from the duplicatepvid list
        if [ "$PVCOUNT" = "1" ] ; then
                DISKLIST="$(echo $DISK)"
                MISSINGDISKS="no"
        else
                DISKMATCH
        fi
}

DISKMATCH ()
{
        if [ "$DUPLICATES" = "no" ] ; then
                #get list of PVIDs in the VG for the Disk we are working on
                VGDISKPVIDS=$(lqueryvg -p $DISK -P | awk '{print $1}')

                #Go through list of PVIDS, check if there is an hdisk with that PVID and if so add it to the Disklist
                for PVID in `echo $VGDISKPVIDS | tr ' ' '\n'`
                        do
                                TMPCHECK="$(lspv | grep $PVID | wc -l)"
                                if [ "$TMPCHECK" -eq "1" ] ; then
                                        DISKLIST="$DISKLIST $(lspv | grep $PVID | awk '{print $1}')"
                                fi
                        done
                #Get number of disks currently in disklist and then check to see if the number of disks matches the PV count for the VG
                DISKCOUNT="$(echo $DISKLIST | tr " " "\n" | wc -l)"
                if [ "$DISKCOUNT" -eq "$PVCOUNT" ] ; then
                        MISSINGDISKS="no"
                else
                        MISSINGDISKS="yes"
                fi

        else
                #get list of PVIDs in the VG for the Disk we are working on
                VGDISKPVIDS=$(lqueryvg -p $DISK -P | awk '{print $1}')

                #Go through list of PVIDS
                for PVID in `echo $VGDISKPVIDS | tr ' ' '\n'`
                        do
                                #Since in this case Duplicates  = yes there will be multiple hdisks for each PVID  Here we build the list of hdisks for the PVID we are on
                                DUPDISKS="$(lspv | grep $PVID | awk '{print $1}')"

                                #Now we go through the list of hdisks for the PVID we are on and find the lun ID to get the snapdate for that particular lun.
                                for HDISK in `echo $DUPDISKS | tr ' ' '\n'`
                                        do
                                                TMPVVWWN="$($LSVIOCFG $HDISK | awk '{print $5}')"
                                                TMPLUNID="$(grep $TMPVVWWN $VVWWNFILE | awk '{print $1}')"

                                                TMPSNAPDATE="$(awk '$1 ~ /^'$TMPLUNID'$/ {print $5}' $HPSANFILE | sed 's/.*-//' | sed 's/\(.........\).*/\1/')"

                                                #Now if the snap date for this hdisk matches the snapdate for the original disk it is part of this VG and will be added to the disklist
                                                if [ "$TMPSNAPDATE" == "$SNAPDATE" ] ; then
                                                        DISKLIST="$HDISK $DISKLIST"
                                                fi
                                        done
                        done

                #Get number of disks currently in disklist and then check to see if the number of disks matches the PV count for the VG
                DISKCOUNT="$(echo $DISKLIST | tr " " "\n" | wc -l)"
                if [ "$DISKCOUNT" -eq "$PVCOUNT" ] ; then
                        MISSINGDISKS="no"
                else
                        MISSINGDISKS="yes"
                fi
        fi
}

STALEDISKCHK () #Checks for disks not in a Volume Group but still have a PVID. If there are disks in this state then they were part of a VG that did not have all it's disks
{
        STALEDISKSCOUNT=$(lspv | grep "None" | grep -v "none" | wc -l)

        if [ "$STALEDISKSCOUNT" -ne "0" ] ; then
                COUNT=$(cat /tmp/missingdiskcount)
                COUNT=$(($COUNT+1))
                echo $COUNT > /tmp/missingdiskcount
        else
                echo "0" > /tmp/missingdiskcount
        fi

        if [ "$(cat /tmp/missingdiskcount)" -ge "3" ] ; then
                STALEDISKS="$(lspv | grep "None" | grep -v "none" | awk '{print$1}')"
                TMPVGID=""
                TMPSNPDATE=""
                PVIDCHECK
                if [ "$DUPLICATES" -eq "no" ] ; then
                        #Checking through all disks not in a VG that have a PVID still
                        for i in `echo $STALEDISKS | tr ' ' '\n'`
                                do
                                        GETDISKINFO $i
                                        #Checking the TMPVGID variable to see if we have processed a disk with this VGID previously. If not add it to the list of VGs in TMPVGID
                                        if [ "$(echo $TMPVGID | grep $VGID)" -ne "$VGID" ] ; then
                                                TMPVGID="$TMPVGID $VGID"

                                                #Get the list of PVIDs needed for the VG
                                                VGDISKPVIDS=$(lqueryvg -p $i -P | awk '{print $1}')

                                                #Now check each PVID on mchir45 and if it is not present go out to the host and get the 3PAR ID for that disk
                                                for PVID in `echo $VGDISKPVIDS | tr ' ' '\n'`
                                                        do
                                                                if [ -z "$(lspv | grep $PVID)" ] ; then
                                                                        CMD="ssh $HOST \"lspv | grep $PVID\" "
                                                                        THEMISSINGDISK="$(su - ifreling -c "$CMD" | awk '{print $1}')"
                                                                        CMD2="ssh $HOST \"/usr/local/bin/lsviocfg $THEMISSINGDISK\" "
                                                                        THREEPARID="$(su - ifreling -c "$CMD2" | awk '{print $6}')"
                                                                        MISSINGDISKINFO="PVID $PVID is missing for VG $VGNAME from host $HOST. Please ask the storage team to attach a snap of \"$THREEPARID\" from the snap with date_time $SNAPDATE : $MISSINGDISKINFO"

                                                                        MISSINGDISKINFO="$(echo $MISSINGDISKINFO | tr ':' '\n')"
                                                                        echo "$MISSINGDISKINFO" | mail -s "Missing Disks Detected on mchir045" $AIXTEAMEMAIL

                                                                fi
                                                        done
                                        fi
                                done
                elif [ "$DUPLICATES" -eq "yes" ] ; then
                        for i in `echo $STALEDISKS | tr ' ' '\n'`
                                do
                                        GETDISKINFO $i
                                        #Checking the TMPVGID variable to see if we have processed a disk with this VGID previously. If not add it to the list of VGs in TMPVGID a second check for the snap date is needed in case we have multiple snaps of a VG with multiple disks missing a disk
                                        if [ "$(echo $TMPVGID | grep $VGID)" -ne "$VGID" && "$TMPSNPDATE" -ne "$SNAPDATE" ] ; then
                                                TMPVGID="$TMPVGID $VGID"

                                                #Get the list of PVIDs needed for the VG
                                                VGDISKPVIDS=$(lqueryvg -p $i -P | awk '{print $1}')
                                                for PVID in `echo $VGDISKPVIDS | tr ' ' '\n'`
                                                        do
                                                                if [ -z "$(lspv | grep $PVID)" ] ; then
                                                                        CMD="ssh $HOST \"lspv | grep $PVID\" "
                                                                        THEMISSINGDISK="$(su - ifreling -c "$CMD" | awk '{print $1}')"
                                                                        CMD2="ssh $HOST \"/usr/local/bin/lsviocfg $THEMISSINGDISK\" "
                                                                        THREEPARID="$(su - ifreling -c "$CMD2" | awk '{print $6}')"
                                                                        MISSINGDISKINFO="PVID $PVID is missing for VG $VGNAME from host $HOST. Please ask the storage team to attach a snap of \"$THREEPARID\" from the snap with date_time $SNAPDATE : $MISSINGDISKINFO"

                                                                        MISSINGDISKINFO="$(echo $MISSINGDISKINFO | tr ':' '\n')"
                                                                        echo "$MISSINGDISKINFO" | mail -s "Missing Disks Detected on mchir045" $AIXTEAMEMAIL

                                                                else
                                                                        TMPHDISK="$(lspv | grep $PVID | awk '{print $1}')"
                                                                        TMPVVWWN="$($LSVIOCFG $TMPHDISK | awk '{print $5}')"
                                                                        TMPLUNID="$(grep $TMPVVWWN $VVWWNFILE | awk '{print $1}')"
                                                                        TMPSNAPDATE="$(awk '$1 ~ /^'$TMPLUNID'$/ {print $5}' $HPSANFILE | sed 's/.*-//' | sed 's/\(.........\).*/\1/')"
                                                                        if [ "$TMPSNAPDATE" -ne "$SNAPDATE" ] ; then
                                                                                CMD="ssh $HOST \"lspv | grep $PVID\" "
                                                                                THEMISSINGDISK="$(su - ifreling -c "$CMD" | awk '{print $1}')"
                                                                                CMD2="ssh $HOST \"/usr/local/bin/lsviocfg $THEMISSINGDISK\" "
                                                                                THREEPARID="$(su - ifreling -c "$CMD2" | awk '{print $6}')"
                                                                                MISSINGDISKINFO="PVID $PVID is missing for VG $VGNAME from host $HOST. Please ask the storage team to attach a snap of \"$THREEPARID\" from the snap with date_time $SNAPDATE : $MISSINGDISKINFO"

                                                                                MISSINGDISKINFO="$(echo $MISSINGDISKINFO | tr ':' '\n')"
                                                                                echo "$MISSINGDISKINFO" | mail -s "Missing Disks Detected on mchir045" $AIXTEAMEMAIL

                                                                        fi

                                                                fi
                                                        done
                                        fi
                                done

                fi
        fi
}

SCHEDULECLEANUP () #Builds AT job to unmount filesystem from host, remove from exports, unmounts the filesystems, exports the vg, clears the PVIDs on the disks, and cleans up directories
{
        #Build unmount script
        for i in `lsvg -l $TMPVGNAME | grep -v N/A | awk 'NR > 2 {print $7}' | sort -r`
        do
                echo "sudo umount \`echo $i | sed 's/\\/$HOST//g'\`" >> /tmp/umount$SNAPDATE$HOST.sh
        done

        #Make umount script executable
        chmod +x /tmp/umount$SNAPDATE$HOST.sh

        #Copy unmount script to host and remove from mchir045
        su - ifreling -c "scp /tmp/umount$SNAPDATE$HOST.sh $HOST:/tmp"
        rm /tmp/umount$SNAPDATE$HOST.sh



        #Build at job file and schedule for 1 day later
        cat > /tmp/atjob$TMPVGNAME$HOST.sh <<EOF
        #!/usr/bin/ksh
        set -x

        #Cleanup job for $VGNAME restore on $HOST ($TMPVGNAME on mchir045)

        #umount nfs mounts on $HOST and remove umount script
        su - ifreling -c \"ssh $HOST /tmp/umount$SNAPDATE$HOST.sh\"
        su - ifreling -c \"ssh $HOST rm /tmp/umount$SNAPDATE$HOST.sh\"

        #Get list of disks in the VG
        REMOVEDISKS=\"\$(lsvg -p $TMPVGNAME | awk 'NR > 2 {print \$1}')\"

        #unmount FS on mchir045 and remove from exports
        for i in \`lsvg -l $TMPVGNAME | grep -v N/A | awk 'NR > 2 {print $7}' | sort -r\`
                do
                        umount \$i
                        rmnfsexp -d \$i
                done


        #varyoffvg
        varyoffvg $TMPVGNAME

        #export VG
        exportvg $TMPVGNAME

        #Remove PVIDs of disks that were in that VG
        for i in \`echo \$REMOVEDISKS | tr ' ' '\n'\`
                do
                        chdev -a pv=clear -l \$i
                done

        #Remove directories on mchir045 for this specific snap
        if [ -d "$RESTOREDIR/$HOST/$VGNAME$SNAPDATE" ] ; then
                rm -rf $RESTOREDIR/$HOST/$VGNAME$SNAPDATE
        fi

        #Check if root directory for host is empty. If so remove from exports and delete directory
        if [ "\$(ls $RESTOREDIR/$HOST | wc -l)" -eq "0" ] ; then
                su - ifreling -c \"ssh $HOST sudo umount $RESTOREDIR\"
                rmnfsexp -d $RESTOREDIR/$HOST
                rmdir $RESTOREDIR/$HOST
        fi

        #Remove backup file of this atjob
        rm /tmp/atjob$TMPVGNAME$HOST.sh
EOF

        chmod +x /tmp/atjob$TMPVGNAME$HOST.sh
        echo "/tmp/atjob$TMPVGNAME$HOST.sh" | at now +1 day
}

########################################PROGRAM START########################################

# See if there have been new disks added to server
CHECKDISKS

echo "******************** NEW DISKS HAVE BEEN DETECTED ********************" >> $LOGDIR/$LOGFILE
echo "******************** `date` ********************" >> $LOGDIR/$LOGFILE

# Update flat files with latest diskinfo from all 3PAR SANs
REFRESHSANINFO

# Check for duplicate PVIDs to see if multiple snaps of the same disk are being presented
PVIDCHECK

for DISK in `cat /tmp/newdisks.txt`
        do
                if [ "$(lspv | grep $DISK | awk '{print $3}')" != "None" ] ; then
                        echo "Disk $DISK is already a part of a VG"
                else
                        GETDISKINFO $DISK
                        #Reset Disklist variable to clear out any disks from previous loop.
                        DISKLIST=""
                        BUILDDISKLIST
                        if [ "$MISSINGDISKS" = "no" ] ; then
                                CLEARPVIDS
                                IMPORTVG
                                FSCKFILESYSTEMS
                                MOUNTANDEXPORT
                                SCHEDULECLEANUP
                        else
                                echo "Not all disks needed for $VGNAME on $HOST for snapdate $SNAPDATE were found" >> $LOGDIR/$LOGFILE

                        fi
                fi
        done

STALEDISKCHK
