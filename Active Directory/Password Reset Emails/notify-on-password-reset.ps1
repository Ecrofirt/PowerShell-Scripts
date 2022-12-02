<#
.Description
This script is designed to be kicked off from an Event-Triggered scheduled task that's present on all domain controllers.
It will send an email via an SMTP server to a target address logging the password reset.
#>

param(
    $TargetAccount,
    $TargetSID,
    $SubjectAccount,
    $SubjectSID,
    $Computer,
    $Time,
    $Keywords
)
$SMTPServer = "smtp.example.com"
$FromAddress = "from@example.com"
$ToAddress = "to@example.com


#Target accounts ending with $ are computer accounts
if ($TargetAccount -notlike "*$")
{
    $result = switch ($Keywords)
    {
        "0x8020000000000000" { "Success" }
        "0x8010000000000000" { "Failure" }
    }
    #Write-Host $SubjectAccount
    #Write-Host $TargetAccount
    #Write-Host $Time
    #Write-Host $result
    #Write-Host $Computer
    #Write-Host $SubjectSID
    #Write-Host $TargetSID
    #Read-Host

    $details = [pscustomobject]@{
    
        "Initiated By"      = $SubjectAccount
        "Target User"       = $TargetAccount
        "Time"              = (Get-Date -Date $Time)
        "Result"            = $result
        "Domain Controller" = $Computer
        "Initiator SID"     = $SubjectSID
        "Target SID"        = $TargetSID
    }

    $dList = $details | ConvertTo-Html -As List -Fragment

    $subject = "Password Reset: Initiated by $($SubjectAccount) against $($TargetAccount)"

    Send-MailMessage -SmtpServer $SMTPServer -From $FromAddress -To $ToAddress -Subject $subject -BodyAsHtml -Body "<p>$($dList)</p>"
}
