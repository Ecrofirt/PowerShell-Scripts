## Active Directory User Account Creation
I've written a comprehensive script to build Active Directory user accounts based on data file exports from an external system.
Setup preparation for the script is as follows:

 - In the script root the following folders must exist
	 - archive
	 - incoming

CSV files are placed in the **incoming** folder through any of a number of means (not handled in this script, but suggestions could be: file share, automated SFTP move, etc.)

The files must be formatted as CSV and must contain the following columns (in order):

	EmployeeID
	SAMAccountName
	UserPrincipalName
	GivenName
	MiddleName
	SurName
	Indicator

The script is intended to be run as a scheduled task as an account with permissions to query AD, create users, reset user passwords, and modify group membership.
