## How to Set up The Scheduled Task


Trigger
-
Begin the task: On an event
Log: Security
Source: Microsoft Windows security auditing
Event ID: 4724

Actions
-
Action: Start a program
Program/script: powershell.exe
Arguments: -ExecutionPolicy Bypass -NoProfile -NonInteractive -File \\server\share\notify-on-password-reset.ps1 -TargetAccount $(TargetAccount) -TargetSID $(TargetSID) -SubjectAccount $(SubjectAccount) -SubjectSID $(SubjectSID) -Computer $(Computer) -Time $(Time) -Keywords $(Keywords)


After Task Creation
-
Export the task to a .XML file. You need to edit the XML file to add Value queries to create the TargetAccount, TargetSID, SubjectAccount, SubjectSID, Computer, Time, and Keywords parameters.

To do so, find the `EventTrigger` element in the file and edit it to add the following:

    				<EventTrigger>
					<Enabled>true</Enabled>
					<Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Security"&gt;&lt;Select Path="Security"&gt;*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4724]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
					<ValueQueries>
						<Value name="Computer">Event/System/Computer</Value>
						<Value name="Keywords">Event/System/Keywords</Value>
						<Value name="SubjectAccount">Event/EventData/Data[@Name='SubjectUserName']</Value>
						<Value name="SubjectSID">Event/EventData/Data[@Name='SubjectUserSid']</Value>
						<Value name="TargetAccount">Event/EventData/Data[@Name='TargetUserName']</Value>
						<Value name="TargetSID">Event/EventData/Data[@Name='TargetSid']</Value>
						<Value name="Time">Event/System/TimeCreated/@SystemTime</Value>
					</ValueQueries>
				</EventTrigger>


Credit  for the ValueQueries stuff goes to: [https://michlstechblog.info/blog/windows-passing-parameters-to-event-triggered-schedule-tasks/](https://michlstechblog.info/blog/windows-passing-parameters-to-event-triggered-schedule-tasks/)

This could be manually set up with `New-ScheduledTaskTrigger` but subscriptions and value queries aren't as easy to set up that way.
