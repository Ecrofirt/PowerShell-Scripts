## App Pool Restarter
This script is meant to be run interactively.
In my environment we have some vendor applications using IIS Application Pools. These app pools are set up to cache things for a long time, which can cause a 24 hour delay between new data in our ERP and when the IIS applications 'see' the change. The recommendation from the vendor is to recycle the app pools if we need the changes to be immediate.

This script lets you select one or more IIS servers from a list, connect to them via user-supplied credentials, and then select one or more app pools to restart.

Servers and app pools can all be selected multiple times for complex scenarios.

This is used by some folks on our MIS team to push changes out to the IIS applications very quickly without needing to RDP into the servers themselves.

Good luck with it!
