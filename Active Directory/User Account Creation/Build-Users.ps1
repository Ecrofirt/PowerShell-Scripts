<#
.SYNOPSIS
This script builds Active Directory accounts based on CSV files

.DESCRIPTION
This script builds Active Directory user accounts based on CSV files. It is intended to be run as a scheduled task.

.NOTES
The CSV files are located in the .\incoming folder The incoming file is a CSV with the following columns
   Id
   PersonWaUserId
   PersonWwwEmailAddr
   FirstName
   MiddleName
   LastName
   PersonIndicator***

The column headers in the file may differ, so the script uses its own headers. Column positioning is important

Process:
Check incoming folder for files
If any files exist
 Query AD for all users, capturing the following properties: sAMAccountName, UserPrincipalName, mail, proxyAddresses and store them in an array
 For each file in the incoming folder
  Import the CSV to a list of users to build
  For each unique indicator in the list of users to build, process the list of users matching the indicator as follows:
   Check if a user exists in the array of AD Users that matches some of the properties of the user to build
    If so, create an error record
    Move to next user
   If no users exist that match the properties
    Attempt to build the user
    If the build fails
     Modify the user's Name property to include and numbers from the incoming UserPrincipalName, if applicable and attempt to rebuild
      If the build fails again
       create an error record
       Move to the next user
   Send an email with results about the build process
  Move the file to an archive folder
 Force an Azure AD Sync
 
 .PARAMETER WriteToConsole
 Indicates that output should be written to the console in addition to email

.EXAMPLE
.\incoming contains a file called users.csv set up as follows:
    "Id","PersonWaUserId","PersonWwwEmailAddr","FirstName","MiddleName","LastName","PersonIndicatorStaff"
    "6665557","randysavage","randysavage@example.com","Randy","","Savage","staff"
    "3334445","hulkhogan","hulkhogan@example.com","Hulk","","Hogan","staff"

Script is run as follows:
.\Build-ADUsers.ps1

Output:
An email is sent with details
From: AD Account Manager <noreply@example.com>
To: Monitored Email <monitor@example.com`>
Subject: Staff Accounts Built - Including Error(s)
 
Total acounts processed: 2

Successfully Processed Accounts: 2

User ID	Email	First Name	Last Name
6665557	randysavage@example.com	Randy	Savage
3334445	hulkhogan@example.com	Hulk	Hogan
#>
param (
    [Parameter()]
    [Switch]
    $WriteToConsole
)



function Initialize-ScriptVariables
{
<#
.SYNOPSIS
Initializes script-wide variables

.NOTES
This function is used as a place to set up the script-wide variables. It only gets called if there's files to process.
#>

    #Grab a PDC server for use in the script
    $Script:DC = "$((Get-ADDomainController -Discover -Service PrimaryDC).HostName)"
    
    #Capture an array of all AD Users
    #Note: Do NOT use the -Server parameter here. It seems to cause non-standard properties (EmployeeID, MailNickname, etc) not to actually populate
    #Until they are called upon later. This causes a huge huge huge performance penalty when you attempt something like
    #ADUsers.EmployeeID -Contains "1234567" because it then communicates with AD on *each* item to download the EmployeeID - Don't believe me? Check your
    #Network traffic.
    $Script:ADUsers = Get-ADUser -Filter "EmployeeID -like '*'" -Properties SamAccountName,UserPrincipalName,EmployeeID,Mail,MailNickname,ProxyAddresses

    #This is the Server running Azure AD Connect
    $Script:AADConnectServer = "KC-ADCONN-01.example.com"

    #set up the CSV header
    $Script:CSVHeader = "EmployeeID","SAMAccountName","UserPrincipalName","GivenName","MiddleName","SurName","Indicator"

    #The DN of the OU where staff accounts will be placed
    $Script:StaffOU = "OU=Staff,OU=General_Accounts,OU=User_New,DC=example,DC=com"

    #AD Groups that staff accounts will be added to
    $Script:StaffGroups = @(
    "faculty-staff"
    "M365 - Office 365 A1 Plus for Faculty"
    "Staff-PC"
    )

    #The DN of the OU where student accounts will be placed
    $Script:StudentOU = "OU=Incoming,OU=Class_Groups,OU=Students,OU=General_Accounts,OU=User_New,DC=example,DC=com"

    #AD Groups that student accounts will be added to
    $Script:StudentGroups = @(
    "students"
    "M365 - Office 365 A1 Plus for Students"
    "Students-PC"
    )

    #Email variables
    $Script:SMTPServer = "smtp.example.com"
    $Script:From = "AD Account Manager <noreply@example.com>"
    $Script:To = "AcctInfo <acctinfo@example.com>"
}


function Build-ADUser
{
<#
.SYNOPSIS 
This function builds users and sends a report email

.DESCRIPTION 
This function builds one of more Active Directory users. Multiple users can be sent
To the function to be processed via the pipeline. Users are in the form of [pscustomobject] objects

.PARAMETER UserToBuild
The user object to be built. It must have the following attributes:
-EmployeeID (An employee/student ID number)
-SAMAccountName (non-email format)
-UserPrincipalName (email format)
-GivenName (first name)
-MiddleName
-SurName (last name)
This parameter also accepts input via the pipeline, to allow the function to build multiple users

.PARAMETER Indicator
Indicates what type of account to build - This impacts OU placement and AD Group Membership
Possible Values: Staff or Student

.EXAMPLE
$utb = [pscustomobject]@{EmployeeID="1234567"; SAMAccountName="johndoe"; UserPrincipalName="johndoe@example.com"; GivenName="John"; MiddleName="Q"; SurName="Doe"}

Build-ADUser -UserToBuild $utb -Indicator "Staff"

.EXAMPLE
$usersToBuild = @(
    [pscustomobject]@{EmployeeID="1234567"; SAMAccountName="johndoe"; UserPrincipalName="johndoe@example.com"; GivenName="John"; MiddleName="Q"; SurName="Doe"},
    [pscustomobject]@{EmployeeID="7654321"; SAMAccountName="janedoe"; UserPrincipalName="janedoe@example.com"; GivenName="Jane"; MiddleName="Z"; SurName="Doe"}
)

$usersToBuild | Build-ADUser-Indicator "Staff"
#>

    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [pscustomobject]
        $UserToBuild,
        [Parameter(Mandatory)]
        [ValidateSet("Staff","Student")]
        [string]
        $Indicator
    )
    #Begin occurs once at the beginning of the function call - it sets up some needed variables
    Begin
    {

        #Set up lists for error records and success records - Used in this function as well as Send-ResultEmail
        $Script:ErrorRecords = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Script:SuccessRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

        #Set up the OU and AD Groups users with this indicator will use 
        $OUPath = ""
        $ADGroups = $null

        switch($Indicator)
        {
            "Staff"{
                $OUPath = $Script:StaffOU
                $ADGroups = $Script:StaffGroups
                break
            }
            "Student"{
                $OUPath = $Script:StudentOU
                $ADGroups = $Script:StudentGroups
                break
            }
        }
    }

    #Work through each user account that was set up
    Process{

        #This allows the function to work appropriately with either a single object or with objects piped in
        if ($PSItem -ne $null)
        {
            $utb = $PSItem
        }
        else
        {
            $utb = $UserToBuild
        }

        #limit the SAMAccountName to 20 characters
        $utb.SAMAccountName = $utb.SAMAccountName.Substring(0,[Math]::Min($utb.SAMAccountName.Length,20))

        #Get numbers in the username - Useful if two people have the same name
        $numsInUserName = $utb.UserPrincipalName -replace "\D",""


        #will be used as a backup method 
        $userCreated = $false

        #Set a flag indicating that no error has occurred creating this user
        $errorOccurred = $false

        #A list of errors that occurred when creating the user
        $errorList = [System.Collections.Generic.List[String]]::new()

        #Look through a common list of breaking errors that would cause a duplicate user
        #For any of the common errors, raise the error flag and add an entry to the error list
        switch ($utb)
        {
            {$Script:ADUsers.EmployeeID -contains $_.EmployeeID}{
                $errorOccurred = $true
                $errorList.Add("EmployeeID $($_.EmployeeID)")
            }
            {$Script:ADUsers.SamAccountName -contains $_.SamAccountName}{
                $errorOccurred = $true
                $errorList.Add("SAMAccountName $($_.SamAccountName)")
            }
            {$Script:ADUsers.UserPrincipalName -contains $_.UserPrincipalName}{
                $errorOccurred = $true
                $errorList.Add("UserPrincipalName $($_.UserPrincipalName)")
            }
            {$Script:ADUsers.Mail -contains $_.UserPrincipalName}{
                $errorOccurred = $true
                $errorList.Add("Mail $($_.UserPrincipalName)")
            }
            {$Script:ADUsers.MailNickname -contains $_.SamAccountName}{
                $errorOccurred = $true
                $errorList.Add("MailNickname $($_.SamAccountName)")
            }
            {($Script:ADUsers.ProxyAddresses -match $_.UserPrincipalName).Count -gt 0}{
                $errorOccurred = $true
                $errorList.Add("ProxyAddresses matching $($_.UserPrincipalName)")
            }

        }

        #A unresolvable duplicate user was found based on a property
        #Generate an error record and skip further processing on the user
        if ($errorOccurred)
        {   $errorList.Insert(0,"Another Active Directory user exists with matching properties:")
            $Script:ErrorRecords.Add((New-ResultRecord -ID $utb.EmployeeID -Account $utb.SAMAccountName -RecordType Error -Errors $errorList))
        }
        #No Error occurred, try to make the user
        else
        {
            #Generate the properts to Splat into New-ADUser
            $properties =@{
                "Server" = $Script:DC #A DC to create the user on - this can keep replication issues from occurring as this DC will be consistently used
                "Path" = $OUPath #OU to place the user
                "Name" = "$($utb.SurName), $($utb.GivenName)$(if($utb.MiddleName){" $($utb.MiddleName.Substring(0,1))."})" #LastName, FirstName MiddleInitial.
                "DisplayName" = "$($utb.SurName), $($utb.GivenName)$(if($utb.MiddleName){" $($utb.MiddleName.Substring(0,1))."})" #LastName, FirstName MiddleInitial.
                "GivenName" = $utb.GivenName #FirstName
                "Surname" = $utb.SurName #LastName
                "SamAccountName" = $utb.SAMAccountName #Short format username
                "UserPrincipalName" = $utb.UserPrincipalName #email-format username
                "EmailAddress" = $utb.UserPrincipalName #Primary email address
                "AccountPassword" = (ConvertTo-SecureString $utb.EmployeeID -AsPlainText -Force) #Initial password is ID number
                "Enabled" = $true #User is enabled
                "ChangePasswordAtLogon" = $true #User must change password at next logon
                "OtherAttributes" = @{ #A colection of other attributes to set
                    "MailNickname" = $utb.SAMAccountName #nickname used by Exchange
                    "EmployeeID" = "$($utb.EmployeeID)" #User's ID number
                    "ProxyAddresses" = "SMTP:$($utb.UserPrincipalName)" #ProcyAddress used by Exchange
                } #OtherAttributes
            } #properties

            try{
                #Initially try to create the user - this will fail if another user in the same OU has the same name
                New-ADUser @properties -Credential $cred -ErrorAction SilentlyContinue -ErrorVariable err
                $userCreated = $true
            }
            #A common failure here would be another user in the same OU with the same Name property - We will attempt to catch this
            catch
            {
                Write-Error "In the initial Catch block"
                Write-Error $err[0].Message
                Write-Error "Attempting to use a variation of the Name"
                
                #Assuming that the most common failure would be two users in the same OU with the same Name
                #Modify the Name property and the DisplayName property and attempt to rebuild the user
                try
                {
                    #In our scenario people with the same first and last name would end up with accounts that have numbers
                    #ex: johndoe and johhndoe1124 
                    #If this user had number in their name, attempt to add the numbers to their name to make the entry unique
                    if ($numsInUserName -ne "")
                    {

                        $properties.Name += " - $($numsInUserName)"
                        $properties.DisplayName = $properties.Name
                        Write-Error "Attempting to create account with name $($properties.Name)"
                        New-ADUser @properties -Credential $cred -ErrorAction SilentlyContinue -ErrorVariable err                
                        $userCreated = $true
                    }
                    #if there were no numbers in the name, just assume this failure will need to be manually corrected
                    else
                    {
                        throw $err[0]
                    }
                }
                #This is a second nested failure that's been unaccounted for - Log the error and proceed to the next user
                catch
                {
                    Write-Error "Failed again. In the nested Catch block"
                    Write-Error $err[0].Message
                    $Script:ErrorRecords.Add((New-ResultRecord -ID $utb.EmployeeID -Account $utb.SAMAccountName -RecordType Error -Errors $err[0].Message))
                } #catch
            } #catch

            #user was successfully created - Log the success and proceed to the next user
            if ($userCreated)
            {
                $Script:SuccessRecords.Add((New-SuccessRecord -ID $utb.EmployeeID -Account $utb.SAMAccountName -Email $utb.UserPrincipalName -FirstName $utb.GivenName -LastName $utb.SurName))
                $Script:SuccessRecords.Add((New-ResultRecord -ID $utb.EmployeeID -Account $utb.SAMAccountName -RecordType Success -Email $utb.UserPrincipalName -FirstName $utb.GivenName -LastName $utb.SurName))
            }

        } #else no duplicate users found
    }

    #This block runs once at the end of all pipeline processing
    #Add all successfully created users to the appropriate AD groups
    End
    {
        #If there were successfully created users, add the users to the appropriate groups in AD
        if ($Script:SuccessRecords.Count -gt 0)
        {
            $ADGroups | Add-ADGroupMember -Members $SuccessRecords.Account -Server $Script:DC -Credential $cred
        }

        #Send an email with results
        Send-ResultEmail -AccountType $Indicator

        #If the script was called with a parameter to write results to the console window, get them written
        if ($Script:WriteToConsole.IsPresent)
        {
            Write-Results -AccountType $Indicator
        }
        Write-Results -AccountType $Indicator
    }

}


function ConvertTo-PrettyErrorList
{
<#
.SYNOPSIS
Helper function to convert error lists to an applicable format for email

.PARAMETER Errors
An array of errors

.PARAMETER As
Whether to convert the list to an Unordered HTML list or a simple newline delimited list

.EXAMPLE
ConvertTo-PrettyErrorList -Errors $errors -As HTML

#>
    param (
        [Parameter(Mandatory)]
        [string[]]
        $Errors,
        [Parameter(Mandatory)]
        [ValidateSet("HTML","SimpleList")]
        [string]
        $As
    )

    Process
    {
        #If there's more than one error, conversion can occur
        if ($Errors.Count -gt 1)
        {
            switch ($As)
            {
                #List separated by newline characters
                "SimpleList"{
                    $Errors -join "`n"
                    break
                }
                #There's more than one error - This will effectively turn an array into an unorderd HTML list.
                #It assumes the first array element is something like "Errors:" and it starts the list after the first array element 
                "HTML"{
                    ($Errors[0],"<ul><li>",($Errors[1..($Errors.Count-1)] -join "</li><li>"),"</li></ul>") -join ""
                    break
                }
            }
        }
        #Only one item, so this simply returns the unchanged error
        else
        {
            $Errors
        }
    }
}

function Send-ResultEmail
{
<#
.SYNOPSIS
Sends an email with results from the account creation

.DESCRIPTION
This function send an email with detailed results. It accounts for errors and succeses.
The function relies on script-level variables of error and success lists

.PARAMETER AccountType
The type of accounts that were created - Used to format the email subject

.EXAMPLE
Send-ResultEmail -AccountType Staff

.NOTES
This function relies on script-level variables for Errors and Successes
SMTP Server / To / From variables are defined in another function
#>
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Staff","Student")]
        [String]
        $AccountType
    )

    #Email subject
    $Subject = "$($AccountType) Accounts Built$(if ($Script:ErrorRecords.Count -gt 0){" - Including Error(s)"})"

    #CSS to make the tables look pretty
    $Header =
@"
                <style>
                TABLE {border-collapse: collapse;}
                TD, TH {text-align: left; padding: 3px; border-width: 1px; border-color: #000000; border-style: dotted;}
                TR:nth-child(even) {background-color: #f2f2f2;}
                </style>
"@

    #Set the body up as a StringBuilder so it can be appended quickly
    $emailBody = [System.Text.StringBuilder]::new()

    #Set up HTML head and a Total line
    $null = $emailBody.Append("<html><head>$($Header)</head><body>")
    $null = $emailBody.Append("<p>Total acounts processed: $($Script:ErrorRecords.Count +$Script:SuccessRecords.Count)</p>")

    #process errors
    if ($Script:ErrorRecords.Count -gt 0)
    {
        #Append the error list to the email
        $null = $emailBody.Append("<p><strong><font color='red'>Account$(if($Script:ErrorRecords.Count -gt 1){"s"}) with errors: $($Script:ErrorRecords.Count)</font></strong></p>")
        $null = $emailBody.Append(($Script:ErrorRecords|Sort-Object -Property ID | ConvertTo-Html -Fragment -As Table -Property "Employee ID","Account Name",@{Name="Error(s)";Expression={(ConvertTo-PrettyErrorList -Errors $_.Errors -As HTML)}}) -join "")
    }

    #process successes
    if ($Script:SuccessRecords.Count -gt 0)
    {
        #Append the success list to the table
        $null = $emailBody.Append("<p><strong>Successfully Processed Account$(if($Script:SuccessRecords.Count -gt 1){"s"}): $($Script:SuccessRecords.Count)</strong></p>")
        $null = $emailBody.Append(($Script:SuccessRecords|Sort-Object -Property ID | Select-Object -Property "Employee ID","Email","First Name","Last Name" | ConvertTo-Html -Fragment -As Table) -join "")
    }

    #Finish up the HTML
    $null = $emailBody.Append("</body></html>")
    
    #ConvertTo-HTML replaces all < and > characters with their visual equivalent - This puts them back
    $null = $emailBody.Replace("&lt;","<")
    $null = $emailBody.Replace("&gt;",">")
    

    #Send the email message
    Send-MailMessage -SmtpServer $Script:SMTPServer -From $Script:From -To $Script:To -Subject $Subject -BodyAsHtml -Body $emailBody.ToString()
}


function Write-Results
{
<#
.SYNOPSIS
Writes the account building results the the console

.DESCRIPTION
This function writes detailed results of the account building to the screen.
It relies on a script-level error and success lists

.PARAMETER AccountType
Which types of accounts were created

.EXAMPLE
Write-Results -AccountType Staff
#>
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Staff","Student")]
        [String]
        $AccountType
    ) 

    

    Write-Host "Results:"
    Write-Host "$($AccountType) Accounts Built$(if ($Script:ErrorRecords.Count -gt 0){" - Including Error(s)"})"

    Write-Host "Total acounts processed: $($Script:ErrorRecords.Count + $Script:SuccessRecords.Count)"

    #process errors
    if ($Script:ErrorRecords.Count -gt 0)
    {
        #Write the total number of errored accounts
        Write-Host
        Write-Host -ForegroundColor Red "Account$(if($Script:ErrorRecords.Count -gt 1){"s"}) with errors: $($Script:ErrorRecords.Count)"
        
        #Write each errored account in a formatted list, with individual errors converted to a simple list
        $ErrorResults =  "$($Script:ErrorRecords|Sort-Object -Property ID | Format-List -Property "Employee ID","Account Name",@{Name="Error(s)";Expression={(ConvertTo-PrettyErrorList -Errors $_.Errors -As SimpleList)}} |Out-String -Width 1000)"
        Write-Host $ErrorResults
    }

    #process successes
    if ($Script:SuccessRecords.Count -gt 0)
    {
        Write-Host
        Write-Host "Successfully Processed Account$(if($Script:SuccessRecords.Count -gt 1){"s"}): $($Script:SuccessRecords.Count)"
        Write-Host "$($Script:SuccessRecords|Sort-Object -Property ID | Format-List -Property "Employee ID","Email","First Name","Last Name" | Out-String -Width 1000)"
    }
    Write-Host
}


function New-ResultRecord {
<#
.SYNOPSIS
Creates a record of an account creation result

.DESCRIPTION
This function creates a record of an account creation result. Results can either be Successes or Errors.
The function uses dynamic parameters based on the value of the RecordType parameter.
If the value is 'Success' additional parameters will become available to capture additional account information
If the value is 'Error' an additional parameter will become available for the Error message(s)

.PARAMETER RecordType
Indicates whether this is a Success record or an Error record

.PARAMETER ID
The user's ID number

.PARAMETER Account
The account name for the user (typically SAMAccountName, though UPN can be used)

.PARAMETER Errors
(dynamic parameter - Error record) An array of errors

.PARAMETER EmailAddress
(dynamic parameter - Success record) The user's email address

.PARAMETER FirstName
(dynamic parameter - Success record) The user's first name

.PARAMETER LastName
(dynamic parameter - Success record) The user's first name

.EXAMPLE
New-ResultRecord -RecordType Success -Id "0123456" -Account "johndoe" -EmailAddress "johndoe123@example.com" -FirstName "John" -LastName "Doe"

.EXAMPLE
New-ResultRecord -RecordType Error -Id "0123456" -Account "johndoe" -Errors "Matching ID number","Matching username","Matching email"

#>
    param (
        [Parameter(Mandatory)]
        [ValidateSet("Error","Success")]
        [string]
        $RecordType,
        [Parameter(Mandatory)]
        [String]
        $ID,
        [Parameter(Mandatory)]
        [String]
        $Account
    )

    #This generates dynamic parameters based on whether the RecordType that was selected was Error or Success
    DynamicParam
    {
        $attribCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        if ($RecordType -eq "Error")
        {
            $pAttribute = [System.Management.Automation.ParameterAttribute]@{
                ParameterSetName="Error"
                Mandatory = $true
            }
            $attribCollection.Add($pAttribute)

            $paramDictionary.Add('Errors',([System.Management.Automation.RuntimeDefinedParameter]::new('Errors',[string[]],$attribCollection)))
        }
        elseif ($RecordType -eq "Success")
        {
            $pAttribute = [System.Management.Automation.ParameterAttribute]@{
                ParameterSetName="Success"
                Mandatory = $true
            }
            $attribCollection.Add($pAttribute)

            $paramDictionary.Add('EmailAddress',([System.Management.Automation.RuntimeDefinedParameter]::new('EmailAddress',[string],$attribCollection)))
            $paramDictionary.Add('FirstName',([System.Management.Automation.RuntimeDefinedParameter]::new('FirstName',[string],$attribCollection)))
            $paramDictionary.Add('LastName',([System.Management.Automation.RuntimeDefinedParameter]::new('LastName',[string],$attribCollection)))
        }

        return $paramDictionary
    }

    Process{

        #Generate a different record based on the RecordType that was selected
        switch ($RecordType)
        {
            "Error"{
                [pscustomobject]@{
                    "Employee ID"=$ID
                    "Account Name" = $Account
                    "Errors" = $PSBoundParameters.Errors
                }
                break
            }
            "Success"{
                [PSCustomObject]@{
                    "Employee ID" = $ID
                    "Account" = $Account
                    "Email" = $PSBoundParameters.EmailAddress
                    "First Name" = $PSBoundParameters.FirstName
                    "Last Name" = $PSBoundParameters.LastName
                }
                break
            }
        }

    }
    
}


##MAIN SCRIPT BODY##

#Get files in the incoming folder as an array
$files = @(Get-ChildItem -File -Path $PSScriptRoot\incoming)

#if there's at least one file, begin processing
if ($files.Count -gt 0)
{
    #Initializes script-wide variables
    Initialize-ScriptVariables 

    #Process each file
    foreach ($file in $files)
    {

        #Convert the CSV data into PowerShell objects and strip out the first row, assuming the first row has the value "ID" in the EmployeeID column
        $UsersToBuild = @(Import-Csv -Path $file.FullName -Header $CSVHeader | ? {$_.EmployeeID -ne "Id"})
        
        #Files should be structured so that an individual file contains *only* students or staff, not a mixture of both.
        #As such, this should only return a single indicator but lord knows what will happen in the future. This is to future-proof things
        #In case the content of the data files is modified at some point in the future to include both staff and students in a single file
        $Indicators = @($UsersToBuild.Indicator | Sort-Object | Get-Unique)

        #iterate each identifier - should only be one but you never know
        foreach ($indicator in $Indicators)
        {

            $UsersToBuild.Where{$_.Indicator -eq $indicator} | Build-ADUser -Indicator $indicator

        }#foreach indicator

        #move the file to a backup location
        Move-Item -Path $file.FullName -Destination "$PSScriptRoot\archive\$((Get-Date).ToString("yyyyMMdd-HHmmss"))_$($file.Name)" -Force

    } #foreach file

    #Force an AAD Connect sync
    Invoke-Command -ComputerName $AADConnectServer -Credential $cred -ScriptBlock {Start-ADSyncSyncCycle}

} #files.count gt 0


