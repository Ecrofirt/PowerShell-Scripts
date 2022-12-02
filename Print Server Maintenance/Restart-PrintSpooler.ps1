#This job automatically restarts the print spooler on our print servers if any jobs are stuck deleting
#I have it set to run nightly at 3AM.
$servers = @("printserver.example.com","printserver2.example.com")
$printers = @()
$badJobs = @()

#reference to the mail server
$mailServer = "smtp.example.com"
$ToAddress = "recipient@example.com"
$FromAddress = "sender@example.com"

#-----

#get all the jobs stuck deleting on each server
$badJobs = @(foreach ($server in $servers)
{

    try 
    {
        Get-Printer -ComputerName $server | Get-PrintJob | ? {$_.JobStatus -like "*deleting*"}
    }
    catch
    {
    }
})



#if there were bad jobs found on the servers, send a notification email, kill the spooler, delete stuck spooler files, and restart the spooler
if ($badJobs.Count -gt 0)
{
    $badServerList = $([String]::Join(", ", ($badJobs.ComputerName|Get-Unique)))
    
    Send-MailMessage -SmtpServer $mailServer -Subject "Restarting Print Spooler on $($badServerList)" -From $FromAddress -To $ToAddress -Body "Jobs were stuck deleting in the print spooler"

    #iterate through each server that housed the bad jobs
    foreach ($server in ($badJobs.ComputerName|Get-Unique))
    {
        
        $spooler = Get-Service -Name "spooler" -ComputerName $server

        #get all running dependant services for the spooler service on each server
        #check if the services were running and add them to an array if they were
        $runningDepServices = @(foreach ($dependantService in $spooler.DependentServices)
        {
            if ($dependantService.Status -eq "Running")
            {
                $dependantService 
            }            
        })

        #stop all running dependant services
        $runningDepServices|Stop-Service -Force

        #stop the spooler
        Stop-Service -InputObject $spooler -Force

        #attempt to clear any bad job spooler files on the server
        try
        {
            Invoke-Command -ComputerName $server -ScriptBlock {
                Remove-Item -Path "c:\Windows\system32\spool\PRINTERS\*.*" -Force
            }
        }
        catch
        {
        }

        #restart the spooler
        Start-Service -InputObject $spooler 
        
        #restart the dependant services       
        $runningDepServices|Start-Service
    }
}
