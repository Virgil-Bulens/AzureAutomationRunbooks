<#
.SYNOPSIS

  Checks which Azure Automation Webhooks are about to expire and sends a warning mail

.DESCRIPTION

  Requires the following:
    - A system assigned managed identity for the Automation Account with following permissions:
      - "Automation Operator" role on the Automation Account that contains the "Send-GraphMail" Runbook
      - Permission to read Azure Automation Webhooks

    - Automation variables:
      - "ExpiryThreshold" - Number of days before expiration to send warning
      - "SendGraphMailAutomationAccountName" - Name of Automation Account that contains "Send-GraphMail" Runbook
      - "SendGraphMailResourceGroupName" - Name of Resource Group that contains "Send-GraphMail" Runbook
      - "To" - Warning recipient mail address

.NOTES
        Author: Virgil Bulens
        Last Updated: 12/02/2021
    Version 1.1

#>


#
# Variables
#
$ErrorActionPreference = "Stop"
$AutomationVariables = @(
    "ExpiryThreshold",
    "To",
    "SendGraphMailResourceGroupName",
    "SendGraphMailAutomationAccountName"
)

foreach ($Variable in $AutomationVariables)
{
    New-Variable -Name $Variable `
        -Value ( Get-AutomationVariable -Name $Variable )
}

$RunbookParameters = @{
    'Name'                  = "Send-GraphMail"
    'ResourceGroupName'     = $MailResourceGroupName
    'AutomationAccountName' = $MailAutomationAccountName
}


#
# Authentication
#
# Az
Connect-AzAccount -Identity | Out-Null


#
# Main
#
$Now = Get-Date
$Subscription = (Get-AzContext).Subscription.Name

$AutomationAccounts = Get-AzAutomationAccount

foreach ( $AutomationAccount in $AutomationAccounts )
{
    $Webhooks = Get-AzAutomationWebhook -ResourceGroupName $AutomationAccount.ResourceGroupName `
        -AutomationAccountName $AutomationAccount.AutomationAccountName

    foreach ( $Webhook in $Webhooks )
    {
        $ExpiryTime = $Webhook.ExpiryTime.DateTime
        $DaysLeft = $ExpiryTime - $Now | ForEach-Object Days

        if ( $DaysLeft -le $ExpiryThreshold )
        {
            # Send mail
            $ChildRunbookParameters = @{
                'To'      = $To 
                'Subject' = "Webhook $($Webhook.Name) expiring in $DaysLeft days!"
                'Content' = @"
Webhook $($Webhook.Name) is expiring in $DaysLeft days!
Please refresh it in time to avoid service disruptions.
Subscription: $Subscription
Resource Group: $($Webhook.ResourceGroupName)
Automation Account: $($Webhook.AutomationAccountName)
Runbook: $($Webhook.RunbookName)
Last Invoked: $($Webhook.LastInvokedTime.DateTime)
"@
            }

            Start-AzAutomationRunbook @RunbookParameters `
                -Parameters $ChildRunbookParameters
        }
    }

}
