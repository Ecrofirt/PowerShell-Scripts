## Password Reset Emails
At my current employer we don't have software to audit account actions beyond the event logs on our domain controllers. A need arose to capture account password resets, so I came up with the idea of a scheduled task pushed to our Domain Controllers OU that would send an email any time a user's password was reset.

In this folder you'll find 3 files:
1. A complete exported scheduled task XML file - This file can be modified in a text editor to update paths, and imported into Group Policy Preferences as a scheduled task by copying/pasting the file
2. The actual powershell script that should be run from. One universal location may be \\domain\netlogon
3. A file that describes the steps needed to manually create the scheduled task XML file should you not trust the one attached to this folder
