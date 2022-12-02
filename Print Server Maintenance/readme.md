## Print Server Maintenance Scripts
The scripts in this folder are used to automate some of the routine print server maintenance that's common in a college environment.

When a printer has a hardware failure of some kind (paper jam, no toner, out of paper, etc), users may send print jobs, notice they aren't printing, and walk away frustrated, abandoning the jobs, but leaving them in the print queue ready to print out as soon as the issue is resolved. In the case of public computer labs, people will sometimes attempt to print the same job multiple times thinking they've made a mistake.

This will lead to a glut of otherwise useless paper printing out when the issue is repaired.
To combat this, I wrote the scripts in this folder.

 - Remove-StuckPrintJobs.ps1 is designed to be run frequently as a scheduled task against remote print servers. It will connect to the servers and look for jobs older than a specified time period, and attempt to remove those jobs. It will then send an email notifying that this has occurred.
 - Restart-PrintSpooler.ps1 is designed to 'clean up' print servers that have jobs that failed to properly delete. It will connect to the servers and look for jobs in with a "Deleting" status.  If it finds any  it sends a notification email, and then shuts down the spooler and and dependent services, clears the System32\Spool\Printers folder, and restarts the services.
 
These two scripts have turned the print servers in my environment into an almost completely no-touch setup. The only time I need to access them is when I'm installing updates, new drivers, or modifying queues.

Good luck with them!
