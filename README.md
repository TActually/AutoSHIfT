
  ___        _        _____ _   _ _____ __ _____ 
 / _ \      | |      /  ___| | | |_   _/ _|_   _|
/ /_\ \_   _| |_ ___ \ `--.| |_| | | || |_  | |  
|  _  | | | | __/ _ \ `--. \  _  | | ||  _| | |  
| | | | |_| | || (_) /\__/ / | | |_| || |   | |  
\_| |_/\__,_|\__\___/\____/\_| |_/\___/_|   \_/  
                                                 
                                                 
Created by me, T Actually!


Autoshift is a bash script that aims to provide similar functionality as timeshift-autosnap, written by Marko Gobin. 
I say similar because:
1) This script does not add hooks to the package manager.
  Which means you can run individual package manager tasks without having to use extra options to avoid the automation.
  I opted to create this as a stand-alone script so that you can do manual updates, if required, without triggering another backup.
  
2) This script will run itself once a week (starting from the date of first run), by default.
  I find that 1 week is a happy medium. **Let me know if this needs to be an adjustable option.**
  Since this script uses anacron instead of cron jobs, it will run, even if the scheduled time is missed.
    For example: If your backup is set for every Monday, but your computer remains in sleep mode from Sunday to Thursday, the script will run itself when you wake your computer up on Friday.
    
3) AutoSHIfT is made for use with RHEL/Fedora based systems that utilize the DNF package manager
  System Requirements:
    RHEL or Fedora based OS utilizing dnf as it's package manager.
    Timeshift back utility (the script will alert & exit if timeshift is not installed)
    Flatpak (you can, remove the flatpak commands if you don't use flatpaks)
    
    
Installation and usage = super easy!!!
Simply download the script,
Make it executable: chmod +x AutoSHIfT.sh
Then run it with sudo: sudo ./AutoSHIfT.sh

On the First run, AutoSHIfT will:
a) Create the cron job in the anacrontab file.
b) Create a folder for itself and its logs in your logged-in user's** home directory.
c) Move itself into the new folder.
d) Check number of backups, if more than 10, it will delete 1 of the backups before creating a new backup.***
e) Perform all updates.
f) Create a log
g) Display a notification when the processes is complete. The notification has to be clicked to be dismissed.

**The script will look for the logged in user automatically. If you have more than 1 user logged in on your machine, then you may want to edit the script and manually enter the user that the script should be installed under.

***The default settings for the number of backup copies to keep is 10. This can be adjusted in the script.

Inspiration for this script comes from https://gitlab.com/gobonja/timeshift-autosnap and https://github.com/wmutschl/timeshift-autosnap-apt
