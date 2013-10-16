#Requires -Version 2.0 

param(
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$user,
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$domain,
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$server = $domain,
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$friendlyName = ("{0}@{1}" -f $user, $domain)
)

Start-Transcript

function Sleep-Until($future_time)
{
    if (($future_time -as [DateTime]) -or ([String]$future_time -as [DateTime])) {
        if ($(Get-Date $future_time) -gt $(Get-Date)) {
            $sec = [System.Math]::Ceiling($($(Get-Date $future_time) - $(Get-Date)).TotalSeconds)
            Start-Sleep -Seconds $sec
        }
        else {
            Write-Host "You must specify a date/time in the future"
            return
        }
    }
    else {
        Write-Host "Incorrect date/time format"
    }
}

function Get-Friendly-Date {
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
            [DateTime]$date
    )
    PROCESS {
        $timeSpan = New-TimeSpan -Start $(Get-Date) -End $date
        $days = $timeSpan.Days
        $hours = $timeSpan.Hours
        $minutes = $timeSpan.Minutes
        $seconds = $timeSpan.Seconds
        
        # handle negatives
        if ($days -lt 0) {
            if ($days -eq -1) {
                return ("expired {0} day ago" -f ([math]::round(-$days+(-$hours/24),0)))
            } else {
                return ("expired {0} days ago" -f ([math]::round(-$days+(-$hours/24),0)))
            }
        }
        if ($hours -lt 0) {
            if ($hours -eq -1) {
                return ("expired {0} hour ago" -f ([math]::round(-$hours+(-$minutes/60),0)))
            } else {
                return ("expired {0} hours ago" -f ([math]::round(-$hours+(-$minutes/60),0)))
            }
        }
        if ($minutes -lt -15) {
            if ($minutes -eq -1) {
                return ("expired {0} minute ago" -f ([math]::round(-$minutes+(-$seconds/60),0)))
            } else {
                return ("expired {0} minutes ago" -f ([math]::round(-$minutes+(-$seconds/60),0)))
            }
        }
        if (($minutes -lt 0) -and ($minutes -gt -5)) {
            return "has expired"
        }
        
        # handle positives
        if ($days -gt 0) {
            if ($days -eq 1) {
                return ("expires in {0} day" -f [math]::round($days+($hours/24),0))
            } else {
                return ("expires in {0} days" -f [math]::round($days+($hours/24),0))
            }
        }
        if ($hours -gt 0) {
            if ($hours -eq 1) {
                return ("expires in {0} hour" -f [math]::round($hours+($minutes/60),0))
            } else {
                return ("expires in {0} hours" -f [math]::round($hours+($minutes/60),0))
            }
        }
        if ($minutes -gt 0) {
            if ($minutes -eq 1) {
                return ("expires in {0} minute" -f [math]::round($minutes+($seconds/60),0))
            } else {
                return ("expires in {0} minutes" -f [math]::round($minutes+($seconds/60),0))
            }
        }
        
        # default case; days, hours and minutes all are zero
        return "has expired"
    }
}

function Warn-User {
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,HelpMessage="Friendly name of the user")]
            [string]$name,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$true,HelpMessage="Expiry Date of the user")]
            [DateTime]$expiryDate
    )
    PROCESS {
        $friendlyExpiryDate = (Get-Friendly-Date $expiryDate)
        Write-Host ("DEBUG: currentDate: {0}, expiryDate: {1}, friendlyDate: {2}" -f ($(Get-Date), $expiryDate, $friendlyExpiryDate))
        $uri = "https://api.pushover.net/1/messages.json"
        $parameters = New-Object System.Collections.Specialized.NameValueCollection
        $parameters.Add("token", "aFJoKkREjf87i7gb8BRCJJx3euH1KN")
        $parameters.Add("user", "ISUX3zbvhr1m7cnDWhBgazPX1E9gpL")
        $parameters.Add("message", ("{0}: password {1}" -f $name, $friendlyExpiryDate))
        $client = New-Object System.Net.WebClient
        $client.Encoding = [System.Text.Encoding]::UTF8
        $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $bytes = $client.UploadValues($uri, $parameters) | Select-Object
        [System.Text.Encoding]::UTF8.GetString($bytes) # assume utf8 encoding of response
    }
}

function Get-ADUserPasswordExpiryDate {
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,HelpMessage="Identity of the Account")]
            [object]$accountIdentity,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$true,HelpMessage="Servername")]
            [string]$server
    )
    PROCESS {
        $accountObj = Get-ADUser $accountIdentity -properties PasswordExpired, PasswordNeverExpires, PasswordLastSet
        # Make sure the password is not expired, and the account is not set to never expire
        if ((!($accountObj.PasswordExpired)) -and (!($accountObj.PasswordNeverExpires))) {
            $passwordSetDate = $accountObj.PasswordLastSet
            # see if the date the password was last set is available
            if ($passwordSetDate -ne $null) {
                $maxPasswordAgeTimeSpan = $null
                # see if we're at Windows2008 domain functional level, which supports granular password policies
                if ($global:dfl -ge 4) { # 2008 Domain functional level
                    $accountFGPP = Get-ADUserResultantPasswordPolicy $accountObj
                    if ($accountFGPP -ne $null) {
                        $maxPasswordAgeTimeSpan = $accountFGPP.MaxPasswordAge
                    }
                }
                # 2003 or ealier Domain Functional Level, or no granular password policy
                # return domain default.
                $default = Get-ADDefaultDomainPasswordPolicy -Server $server
                if ($default -ne $null) {
                    $maxPasswordAgeTimeSpan = $default.MaxPasswordAge
                } else {
                    # no default found; return null
                    return $null
                }
                
                #wtfisthisbs
                if ($maxPasswordAgeTimeSpan -eq $null -or $maxPasswordAgeTimeSpan.TotalMilliseconds -ne 0) {
                    $DateofExpiration = $passwordSetDate + $maxPasswordAgeTimeSpan
                    $DaysTillExpire = [math]::round(((New-TimeSpan -Start (Get-Date) -End ($DateofExpiration)).TotalDays),0)
                    $strName = $accountIdentity.SamAccountName
                    
                    $PolicyDays = [math]::round((($maxPasswordAgeTimeSpan).TotalDays),0)
                    #$DateofExpiration = (Get-Date).AddDays($DaysTillExpire)
                    
                    #return hash
                    @{
                        'domain' = $domain;
                        'username' = $user;
                        'expiryDate' = $DateofExpiration;
                        'expiryDays' = $DaysTillExpire;
                        'lastReset' = $passwordSetDate;
                    }
                }
            }
        }
    }
}

function Get-ModuleStatus { 
	param	(
		[parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$true, HelpMessage="No module name specified!")] 
		[string]$name
	)
	if(!(Get-Module -name "$name")) { 
		if(Get-Module -ListAvailable | ? {$_.name -eq "$name"}) { 
			Import-Module -Name "$name" 
			# module was imported
			return $true
		} else {
			# module was not available (Windows feature isn't installed)
			return $false
		}
	}else {
		# module was already imported
		return $true
	}
} # end function Get-ModuleStatus

if ((Get-ModuleStatus ActiveDirectory) -eq $false){
	$error.clear()
	Write-Host "Installing the Active Directory module..." -ForegroundColor yellow
	Get-ModuleStatus ServerManager
	Add-WindowsFeature RSAT-AD-PowerShell
	if ($error){
		Write-Host "Active Directory module could not be installed. Exiting..." -ForegroundColor red; 
		if ($transcript){Stop-Transcript}
		exit
	}
}

#Write-Host ("DEBUG: {0} {1} {2} {3}" -f $user, $domain, $server, $friendlyName)

$account = Get-ADUser -Identity $user -Server $server
if ($user -ne $null) {
    $result = Get-ADUserPasswordExpiryDate $account $server
} else {
    Write-Host ("User {0} not found in domain {1} using server {2}." -f $user, $domain, $server)
}

$warnDays = 2              # start warning N days before expiry
$warnFrequencyHours = 6*60 # warn every N minutes
$finalWarnTimeMinutes = 15 # final warning N minutes before expiry
$sleepMinutes = 60         # how long to sleep on 

$lastReset = $null

while ($true) {
    if ($result -eq $null) {
        Write-Host "Error: result is null!" -ForgroundColor Red
        Sleep-Until $( $(Get-Date).AddMinutes($sleepMinutes) )
        $result = Get-ADUserPasswordExpiryDate $account $server
    } else {
        if ($(Get-Date) -gt $result.expiryDate) {
            # Password has already expired
            Warn-User $friendlyName $result.expiryDate
            # Check again 24 hours
            Sleep-Until $( $(Get-Date).AddDays(1) )
            $result = Get-ADUserPasswordExpiryDate $account $server
            continue
        }
    
        $warnings = New-Object System.Collections.ArrayList
        $firstWarning = ($result.expiryDate).AddDays(-$warnDays)
        $thisWarning = $firstWarning
        
        # Warn now if password expires soon
        if ($firstWarning -lt $(Get-Date)) {
            Warn-User $friendlyName $result.expiryDate
        }
        
        while ($thisWarning -lt $result.expiryDate) {
            if ($thisWarning -gt $(Get-Date)) {
                $warnings.Add($thisWarning) | Out-Null
            }
            $thisWarning = $thisWarning.AddMinutes($warnFrequencyHours)
        }
        
        # second-last warning is 15 minutes before expiry
        $thisWarning = ($result.expiryDate).AddMinutes(-$finalWarnTimeMinutes)
        if ($thisWarning -gt $(Get-Date)) {
            $warnings.Add($thisWarning) | Out-Null
        }
        
        # final warning upon expiry
        $thisWarning = $result.expiryDate
        if ($thisWarning -gt $(Get-Date)) {
            $warnings.Add($thisWarning) | Out-Null
        }
        
        Write-Host ("DEBUG warnings.count:{0}" -f $warnings.Count)
        Write-Host ("DEBUG: {0}" -f $warnings)
        
        while ($result -ne $null) {
            $lastReset = $result.lastReset
            
            $warnings = @($warnings | Sort-Object)
            $nextWarning, $warnings = @($warnings)
            if ($nextWarning -eq $null) {
                # no more warnings, start over
                $result = Get-ADUserPasswordExpiryDate $account $server
                break
            }
            
            # Wait until next warning
            Write-Host ("Sleeping until next check at {0}..." -f $nextWarning)
            Sleep-Until $nextWarning
            
            $result = Get-ADUserPasswordExpiryDate $account $server
            if ($result -eq $null) {
                Write-Host "Error: result is null!" -ForgroundColor Red
            } else {
                if (($result.lastReset -gt $lastReset) -or ($result.expiryDays -gt $warnDays)) {
                    # password has been reset; start again!
                    $result = Get-ADUserPasswordExpiryDate $account $server
                    break
                } else {
                    Warn-User $friendlyName $result.expiryDate
                }
            }
        }
    }   
}