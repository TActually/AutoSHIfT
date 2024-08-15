# ***AutoSHIfT*** 
## About
Autoshift is a bash script that aims to provide similar functionality as timeshift-autosnap, written by Marko Gobin.<BR>
I say similar because:<BR>
1) This script does not add hooks to the package manager.<BR>
  Which means you can run individual package manager tasks without having to use extra options to avoid the automation.<BR>
  I opted to create this as a stand-alone script so that you can do manual updates, if required, without triggering another backup.
  
2) This script will run itself once a week (starting from the date of first run), by default.<BR>
  I find that 1 week is a happy medium. **Let me know if this needs to be an adjustable option.**<BR>
  Since this script uses anacron instead of cron jobs, it will run, even if the scheduled time is missed.<BR>
    For example: If your backup is set for every Monday, but your computer remains in sleep mode from Sunday to Thursday, the script will run itself when you wake your computer up on Friday.
    
3) AutoSHIfT is made for use with RHEL/Fedora based systems that utilize the DNF package manager<BR>
	***System Requirements:***<BR>
    RHEL or Fedora based OS utilizing dnf as it's package manager.<BR>
    Timeshift backup utility (The script will check Timeshift and install it, if not present)<BR>
    Flatpak (you can, remove the flatpak commands if you don't use flatpaks)
    
## Installation and Usage
Simply download the script from the <A HREF="https://github.com/TActually/AutoSHIfT/releases">Download Page</A><BR> or clone the repository.
Make it executable: `chmod +x AutoSHIfT.sh`<BR>
Then run it with sudo: `sudo ./AutoSHIfT.sh`

## On the First run, AutoSHIfT will:
1) Create the cron job in the anacrontab file.<BR>
2) Create a folder for itself and its logs in your logged-in user's home directory.**
3) Move itself into the new folder.
4) Check number of backups, if more than 10, it will delete 1 of the backups before creating a new backup.
5) Perform all updates.<BR>
6) Create a log.<BR>
7) Display a notification when the processes is complete. The notification has to be clicked to be dismissed.<BR>

** The script will look for the logged in user automatically. If you have more than 1 user logged in on your machine, or you just want to specify a different user,
then you may want to edit the script and manually enter the user that the script should be installed under.
The variable is specifically noted towards the top of script.

*** The default settings for the number of backup copies to keep is 10. This can be adjusted in the script.
The variable is noted towards the top of script

Inspiration for this script comes from<BR>
https://gitlab.com/gobonja/timeshift-autosnap <BR>
and<BR>
https://github.com/wmutschl/timeshift-autosnap-apt
