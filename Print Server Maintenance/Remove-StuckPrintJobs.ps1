#This job automatically kills all print jobs older than a specified time. 
#My environment is set up such that I have printers with different naming conventions and different 'old' timeouts, but I gave an example for a less complex scenario
#I have this job set up as a schedule task running every 5 minutes.

#the cutoff time for old lab and staff print jobs
$oldLabDate = (Get-Date).AddMinutes(-15)
$oldStaffDate = (Get-Date).AddHours(-2)
$servers = @("printserver.example.com","printserver2.example.com")

#bad print jobs - Yes, I know this will get overwritten later on the $badJobs= line
$badJobs = @()
#details about bad print jobs - Yes, I know this will get overwritten later on the $badJobList= line
$badJobList  = @()

$mailServer = "smtp.example.com"
$ToAddress = "recipient@example.com"
$FromAddress = "sender@example.com
"
#-----

#Get all bad print jobs on each print server, with different specifications for lab, staff, and 'other' printers
try
{
    $badJobs = @(foreach ($server in $servers)
    {
        #if you have no requirement for different 'old' times based on printer names, you can use a more simplified method
        #In this approach, I'm just getting all printers on the server, getting all jobs on all printers, and capturing ones that meet the following:
        #Job is older than 2 hours, and status of job is not like *deleting*
        #Get-Printer -ComputerName $server | Get-PrintJob | ? {$_.SubmittedTime -le $oldStaffDate -and $_.JobStatus -notlike "*deleting*"}




        #If you have different sets of printers with common naming conventions and you want to set different rules for the different naming conventions, 
        #here's an example of how to do that
        #naming conventions used here: staff-Building-Floor-Room-PrinterNum, lab-Building-Floor-Room-PrinterNum
        $jobs = Get-Printer -ComputerName $server | Get-PrintJob
        foreach ($job in $jobs)
        {
            #Lab printer jobs older than 15 minutes with a status not like *deleting*
            if (($job.Name -like "lab-*") -and ($job.SubmittedTime -le $oldLabDate) -and ($job.JobStatus -notlike "*deleting*"))
            {
                #output the job to be collected into $badJobs
                $job
            }
            #staff printer jobs older than 2 hours with a status not like *deleting*
            elseif (($job.Name -like "staff-*") -and ($job.SubmittedTime -le $oldStaffDate) -and ($job.JobStatus -notlike "*deleting*"))
            {
                $job
            }
        }
    })
}
catch
{
    Write-Host "Error getting jobs"
}


#This bit does 2 things:
#First, it iterates through all bad jobs and creates an array of pscustomobjects with info about the job - This is list is emailed out later
#If then removes the bad jobs themselves
try
{
    #create an array of information regarding the bad jobs
    $badJobList = @(foreach ($badJob in $badJobs)
    {
        if ($badJob.JobStatus -ne "Blocked")
        {
            $printer = Get-Printer -ComputerName $badJob.ComputerName -Name $badJob.PrinterName
            [PSCustomObject]@{
                Server = $badJob.ComputerName
                Queue = "<a href=http://$($printer.Comment)>$($badJob.PrinterName)</a>" #In my environment a printer's Comment field is its IP address - this creates a link to the printer's webpage
                'Queue Status' = $printer.PrinterStatus
                'Document Name' = $badJob.DocumentName
                'Job Status' = $badJob.JobStatus
                Owner = $badJob.UserName
                Pages = $badJob.TotalPages
                'Size (MB)' = ($badJob.Size/1MB).ToString("F")
                Submitted = $badJob.SubmittedTime
            }
        }
    })

    #clear the bad jobs from the printer
    $badJobs | Remove-PrintJob
}
catch
{
    Write-Host "Error removing jobs"
    $_
    #read-host
}

#Send an email with information about the bad jobx
try
{
    if ($badJobList.Count -gt 0)
    {
        Write-Host "Attempting to email"
        $Header = 
@"
            <style>
            TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
            TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
            TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
            </style>
"@
    
        $htmlTable = $($badJobList | Select-Object -Property Server,Queue,'Queue Status','Document Name','Job Status',Owner,Pages,'Size (MB)',Submitted | ConvertTo-Html -As Table -Fragment)
        $htmlTable = $htmlTable -replace "&lt;","<"
        $htmlTable = $htmlTable -replace "&gt;",">"

        Send-MailMessage -SmtpServer $mailServer -Subject "Clearing Stuck jobs on $([String]::Join(", ", ($badJobList.Server| Get-Unique)))" -From $FromAddress -To $ToAddress -Body "$($Header)<p><strong>Criteria:</strong></br>Lab printers with jobs older than 15 minutes</br>Staff printers with jobs older than 2 hours</br></p><p><strong>Stuck Job Information:</strong></br>$($htmlTable)</p>" -BodyAsHtml:$true 
    }
}
catch
{
    Write-Host "Error sending mail"
}
