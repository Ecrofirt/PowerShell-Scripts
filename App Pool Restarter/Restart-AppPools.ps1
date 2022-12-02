#list of servers that have app pools, one server FQDN per line
$servers = @(
    "server1.example.com"
    "server2.example.com"
    "server3.example.com"
)

#Create Yes/No choices for credential selection
[System.Management.Automation.Host.ChoiceDescription[]]$YN = [System.Management.Automation.Host.ChoiceDescription[]]("&Yes","&No")

#Set up the selections as choice descriptions
[System.Collections.Generic.List[System.Management.Automation.Host.ChoiceDescription]]$choices = [System.Collections.Generic.List[System.Management.Automation.Host.ChoiceDescription]]::new()
for($i = 0; $i -lt $servers.Count;$i++)
{
       $choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&$($i+1) $($servers[$i])","Find app pools on $($servers[$i])"))
}
#Add Cancel as the last choice
$choices.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Cancel","Quit the script"))

#Select servers
Clear-Host
$selections = $Host.ui.PromptForChoice("App Pool Recycler - Multiple Choices allowed","`nSelect servers with app pools to recycle in order, blank entry indicates selection complete`nThe same server can be selected multiple times for complex scenarios`n`n",$choices,[int[]]($choices.Count-1))

#If the user didn't pick CANCEL
if ($selections -notcontains ($choices.Count-1))
{
    #create an array of app pool choices, based on the user's selections
    $appPoolChoices = @(foreach ($server in $selections)
    {
        Clear-Host
        Write-Host "Connecting to $($servers[$server])..."
        
        #if the user hasn't entered credentials before capture them
        if ($null -eq $credentials)
        {
            $credentials = Get-Credential -Message "Enter a username/password to an admin account on $($servers[$server])"
        }
        #if credentials were used previously, ask if they should be reused
        else
        {
            if ($Host.ui.PromptForChoice("$($servers[$server]) - Credential Reuse","Reuse the $($credentials.UserName) credential on $($servers[$server])?",$YN,0) -eq 1)
            {
                $credentials = Get-Credential -Message "Enter a username/password to an admin account on $($servers[$server])"
            }
        }

        #get app pools on the selected server
        $apps = Invoke-Command -Credential $credentials -ComputerName ($servers[$server]) -ScriptBlock{Get-WebApplication}

        Clear-Host 

        #Add all app pools to a list
        $pools =[System.Collections.Generic.List[System.Management.Automation.Host.ChoiceDescription]]::new()
        $x=1
        @($apps.applicationPool).ForEach(
            {
                $pools.Add([System.Management.Automation.Host.ChoiceDescription]::new("&$x $_","Restart the $_ app pool"))
                $x++
            }
        )
        #add a cancel option to the end
        $pools.Add([System.Management.Automation.Host.ChoiceDescription]::new("&Cancel","Skip the app pool(s) on this server"))

        #Let the user select pools
        $selectedPools = $Host.UI.PromptForChoice("$($servers[$server]) Pool Selection - Multiple choices allowed","`nSelect pools to recycle in order, blank entry indicates selection complete`nThe same pool can be selected multiple times for complex scenarios`n`n",$pools,[int[]]($pools.Count-1))
        
        #the user didn't select Cancel
        if ($selectedPools -notcontains ($pools.Count-1))
        {
            #create a hashtable of Server, AppPool, Client Credentials to return back out of this loop
            $selectedPools.ForEach{
                @{
                    "Server"=$servers[$server]
                    "AppPool"=@($apps.applicationPool)[$_]
                    "Credentials" = $credentials
                }
            }
        }
        #the user selected Cancel
        else
        {
            Write-Host "Cancelling pool selection on $($servers[$server])."
            Start-Sleep -Seconds 2
        }#End the pool selector


    }) #end the appPoolChoices selector
    
    Clear-Host
    #If the user selected at least one App Pool
    if ($appPoolChoices.Count -gt 0)
    {
        #Iterate through all selected app pools and restart them
        foreach ($pool in $appPoolChoices)
        {
            Write-Host "Restarting $($pool["AppPool"]) on $($pool["Server"])"
            Invoke-Command -Credential $pool["Credentials"] -ComputerName $pool["Server"] -ScriptBlock{Restart-WebAppPool -Name $using:pool["AppPool"]}
            Write-Host "Sleeping for 10 seconds..."
            Start-Sleep -Seconds 10
        }
    }
    #user didn't select and app pools
    else
    {
        Write-Host "Ultimately, you didn't choose any app pools. There's nothing to do here."
    }
}
#the user chose Cancel
else
{
    Write-Host "You chose to cancel."
} #end the main IF

Write-Host "All actions complete."
Write-Host "Okie doke, goodbye!"
Start-Sleep -Seconds 3
