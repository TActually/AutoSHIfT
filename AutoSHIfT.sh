#! /bin/bash

#  Welcome to AutoSHIfT.
#  Author: T Actually tactually@outlook.com
#  Website: https://github.com/TActually/AutoSHIfT
#  Licensed under GNU General Public License v3.0
#
#  Autoshift is a script  that automatically performs a system backup,
#  then performs DNF and Flatpak updates.
#  The automation is done via a weekly anacron job and
#  the timeshift backups are kept to a definable number.
#  Anacron jobs run, even if the scheduled time is missed.
#  This is intended for systems using the DNF package manager and timeshift, however
#  I'm not much of a coder, you see the script, modify it for your needs.
#  ***IMPORTANT*** First/Manual run of this script must be run as root (sudo)!
################################################################################

# This line discovers the 1st signed in user for the location of the script & logs.
liuser=$(users | cut -d ' ' -f 1)
#liuser=USERNAME  #uncomment this line, comment the line above it to manually enter user.

# IMPORTANT: All timeshift backups (manual or automated) are counted and can be removed.
# If you wish to keep manual backups, you'll need to protect or move them separately.
# This line outputs a list of current backups and obtains a line count.
TSCount=$(timeshift --list | wc -l)

# The unimportant output from 'timeshift --list' is 11 lines long.
# Each additional line is a backup listing.
# Example and Default: 21 lines means that 10 backups will be kept at all times.
TSList=21

# This line controls the number of days that logs are kept before being purged.
D2K=60

# This section will check to make sure that Timeshift is installed
# If Not, script will install timeshift, then exit(quit).
# The script exits to allow you to configure timeshift before creating your first backup.
if [ $(dnf list installed "timeshift" | grep -c "timeshift") -ge 1 ]
then
    :
else
    echo "The Timeshift Backup Utility is not installed on this system.";
    echo "This script will exit. Please run 'sudo dnf install timeshift', then re-run this script.";
    exit
fi

# This section of the script will check for automation, folders and files.
# On first run, it will  create the automation, create folders and move itself into folders.
if [ $(grep "AutoSHIfT" /etc/anacrontab -c) == 0 ]
then
    echo "@weekly 0       AutoSHIfT   ./home/$liuser/AutoSHIfT/AutoSHIfT.sh" >> /etc/anacrontab &&
    mkdir /home/$liuser/AutoSHIfT && mkdir /home/$liuser/AutoSHIfT/logs &&
    chown $liuser:$liuser /home/$liuser/AutoSHIfT && chown $liuser:$liuser /home/$liuser/AutoSHIfT/logs &&
    echo "This is your first time running AutoSHIfT.";
    echo "A weekly cron Job has been added to anacrontab, so,";
    echo "You'll never have to manually run this script, unless you want to!";
    echo "AutoSHIfT and it's logs will reside in ~>  /home/$liuser/AutoSHIfT";
    echo "You'll receive a persistent notification every time AutoSHIfT runs successfully.";
    echo "All backup and update actions are happening in the background, not on screen!";
    echo "You won't see action until the script completes(up to 15 minutes). IT IS NOT FROZEN!!!";
    echo "Make a habit out of checking the logs ~>  /home/$liuser/AtuoSHIfT/logs";
fi

exec &>> /home/$liuser/AutoSHIfT/logs/$(date +"%m%d%Y").log
LOCAutoSHIfT=$(updatedb; locate AutoSHIfT.sh | awk '{ if (/.local/ && !seen) { seen = 0 } else print }')

if [ $LOCAutoSHIfT != "/home/$liuser/AutoSHIfT/AutoSHIfT.sh" ]
then
    mv $LOCAutoSHIfT /home/$liuser/AutoSHIfT/
fi

# This section performs the backup and system update functions.
# I've chosen to include flatpak updates here, you can delete and/or replace that command.
if [ $TSCount -ge $TSList ];
then
    echo "0" | timeshift --delete && dnf clean all && timeshift --create --comment AutoSHIfT &&
    dnf upgrade -y && flatpak update -y
else
    dnf clean all && timeshift --create --comment AutoSHIfT && dnf upgrade -y && flatpak update -y
fi


# This section creates a persistent notification at the end of each successful run.
notification="notify-send -a 'AutoSHIfT' 'System updates succeeded. Restart recommended!' -u critical"

echo "*/1 * * * * $liuser $notification" >> /etc/crontab && sleep 59s &&
sed -i '/AutoSHIfT/d' /etc/crontab &&

find /home/$liuser/AutoSHIfT/logs -mtime +$D2K -delete
exit
