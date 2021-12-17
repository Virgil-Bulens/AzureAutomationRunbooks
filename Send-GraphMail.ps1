<#
.SYNOPSIS

  Sends a simple mail with subject and content to a single recipient

.DESCRIPTION

  Requires the following:
    - An App Registration with the Microsoft Graph API Mail.Send permission
      The mailboxes this app has this permission on, should be restricted using the Exchange Online "New-ApplicationAccessPolicy" cmdlet
    - A licensed Exchange Online user or shared mailbox
    - An active client secret for the App Registration
    - A Key Vault containing the client secret
    - A system assigned managed identity for the Automation Account this runbook is in
      This identity should have at least the "Key Vault Secrets User" role on the client secret stored in the Key Vault, and the "Key Vault Reader" role on the Key Vault itself
    - Following variables stored in the Automation Account:
      - KeyVaultName
      - SecretName
      - TransactionalMailAppId
      - From
      - ExpirationWarningAddress
    - Az.Accounts and Az.KeyVault modules imported in the Automation Account


.PARAMETER To
  String mail address the mail will be sent to

.PARAMETER Subject
  OPTIONAL String subject of the mail

.PARAMETER Content
  OPTIONAL String content or body of the mail in text format

.NOTES
        Author: Virgil Bulens
        Last Updated: 12/17/2021
    Version 1.1

#>


#
# Parameters
#
Param(
  # To address
  [Parameter(
    Mandatory = $true,
    Position = 0
  )]
  [string]
  $To,

  # Mail subject
  [Parameter(
    Mandatory = $false,
    Position = 1
  )]
  [string]
  $Subject,

  # Content of the mail
  [Parameter(
    Mandatory = $false,
    Position = 2
  )]
  [string]
  $Content
)


#
# Variables
#
$ErrorActionPreference = "Stop"
$AutomationVariables = @(
  "KeyVaultName",
  "SecretName",
  "From",
  "ExpirationWarningAddress",
  "TransactionalMailAppId"
)
foreach ($Variable in $AutomationVariables)
{
  Set-Variable -Name $Variable `
    -Value ( Get-AutomationVariable -Name $Variable )
}

$InvalidCharacters = @(
  "\",  
  "`""
)


#
# Authentication
#
# Az
$ConnectAzAccount = Connect-AzAccount -Identity
if ( $ConnectAzAccount.Environments )
{
    
}

else
{
  Write-Error -Message "Could not connect to Azure!"
}


#
# Main
#
# Get required variables and secrets
$TenantId = Get-AzContext | ForEach-Object Tenant | ForEach-Object Id
$AppSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText

# Check if key is about to expire
$KeyExpiring = $false
$KeyExpirationDate = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName | ForEach-Object Expires
$Today = Get-Date
$DaysUntilExpiration = $KeyExpirationDate - $Today | ForEach-Object Days

if ($DaysUntilExpiration -le 10)
{
  $KeyExpiring = $true
}

# Get authentication token from App Registration "Transactional Mail"
$Uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$Body = @{
  'client_id'     = $TransactionalMailAppId
  'scope'         = "https://graph.microsoft.com/.default"
  'client_secret' = $AppSecret
  'grant_type'    = "client_credentials"
}

$Parameters = @{
  'Method'      = "Post"
  'Uri'         = $Uri
  'ContentType' = "application/x-www-form-urlencoded"
  'Body'        = $Body
}

$TokenRequest = Invoke-RestMethod @Parameters
$Token = $TokenRequest.access_token

# Replace invalid characters in Subject and Content
foreach ( $Character in $InvalidCharacters )
{
  $Subject = $Subject.Replace($Character, "\$Character")
  $Content = $Content.Replace($Character, "\$Character")
}

# Send mail using Graph API
$Headers = @{
  'Content-Type'  = "application\json"
  'Authorization' = "Bearer $Token"
}

$MailMessage = @"
{
  "message": {
    "subject": "$Subject",
    "body": {
      "contentType": "Text",
      "content": "$Content"
    },
    "toRecipients": [
      {
        "emailAddress": {
          "address": "$To"
        }
      }
    ]
  },
  "saveToSentItems": "false"
}
"@

$Parameters = @{
  'URI'         = "https://graph.microsoft.com/v1.0/users/$From/sendMail"
  'Headers'     = $Headers
  'Method'      = "Post"
  'ContentType' = "application/json"
  'Body'        = $MailMessage
}

Invoke-RestMethod @Parameters

# Send warning mail if app secret is about to expire
if ($KeyExpiring)
{
  $KeyVault = Get-AzKeyVault -VaultName $KeyVaultName
  $SubscriptionId = $KeyVault.ResourceId.Split("/")[2]
  $ResourceGroupName = $KeyVault.ResourceGroupName

  $Subject = "App Secret for Transactional Mail expiring in $DaysUntilExpiration days."
  $Content = "<p>The&nbsp;app&nbsp;secret&nbsp;for&nbsp;\`"Transactional&nbsp;Mail\`"&nbsp;will&nbsp;expire&nbsp;in&nbsp;$DaysUntilExpiration&nbsp;days.<br />Make&nbsp;sure&nbsp;to&nbsp;renew&nbsp;it&nbsp;here:&nbsp;<br />https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/$TransactionalMailAppId/isMSAApp/</p><p>Also&nbsp;update&nbsp;the&nbsp;new&nbsp;value&nbsp;and&nbsp;expiration&nbsp;date&nbsp;in&nbsp;the&nbsp;key&nbsp;vault:&nbsp;<br />https://portal.azure.com/#blade/Microsoft_Azure_KeyVault/ListObjectVersionsRBACBlade/overview/objectType/secrets/objectId/https%3A%2F%2F$KeyVaultName.vault.azure.net%2Fsecrets%2F$SecretName/vaultResourceUri/%2Fsubscriptions%2F$SubscriptionId%2FresourceGroups%2F$ResourceGroupName%2Fproviders%2FMicrosoft.KeyVault%2Fvaults%2F$KeyVaultName/vaultId/%2Fsubscriptions%2F$SubscriptionId%2FresourceGroups%2F$ResourceGroupName%2Fproviders%2FMicrosoft.KeyVault%2Fvaults%2F$KeyVaultName</p>"

  $MailMessage = @"
{
  "message": {
    "subject": "$Subject",
    "body": {
      "contentType": "HTML",
      "content": "$Content"
    },
    "toRecipients": [
      {
        "emailAddress": {
          "address": "$ExpirationWarningAddress"
        }
      }
    ]
  },
  "saveToSentItems": "false"
}
"@

  $Parameters = @{
    'URI'         = "https://graph.microsoft.com/v1.0/users/$From/sendMail"
    'Headers'     = $Headers
    'Method'      = "Post"
    'ContentType' = "application/json"
    'Body'        = $MailMessage
  }

  Invoke-RestMethod @Parameters

}