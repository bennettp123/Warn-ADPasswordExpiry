#Requires -Version 2.0
param(
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$users,
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$false)]
        [string]$appToken,
    [parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Mandatory=$false)]
        [string]$userToken
)

Import-Module ActiveDirectory

function Warn-User {
    Param(
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$true,HelpMessage="Message")]
            [string]$message,
        [Parameter(Mandatory=$true,Position=2,ValueFromPipeline=$true,HelpMessage="Pushover app token")]
            [string]$appToken,
        [Parameter(Mandatory=$true,Position=3,ValueFromPipeline=$true,HelpMessage="Pushover user token")]
            [string]$userToken
    )
    PROCESS {
        $uri = "https://api.pushover.net/1/messages.json"
        $parameters = New-Object System.Collections.Specialized.NameValueCollection
        $parameters.Add("token", $appToken)
        $parameters.Add("user", $userToken)
        $parameters.Add("message", $message)
        $client = New-Object System.Net.WebClient
        $client.Encoding = [System.Text.Encoding]::UTF8
        $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $bytes = $client.UploadValues($uri, $parameters) | Select-Object
        [System.Text.Encoding]::UTF8.GetString($bytes) # assume utf8 encoding of response
    }
}

$lockedUsers = New-Object System.Collections.ArrayList

while ($true) {
    ForEach ($user in $users) {
        $username = Split-Path -Leaf $user
        if ((Get-ADUser -identity $username -properties LockedOut).LockedOut) {
            if (!($lockedUsers -contains $user)) {
                Warn-User ("{0}: account is locked!" -f $user) $appToken $userToken
                $lockedUsers.Add($user)  | Out-Null
            }
        } else {
            while ($lockedUsers -contains $user) {
                $lockedUsers.Remove($user) | Out-Null
            }
        }
    }
    Start-Sleep -s 60
}