Param
(
    [CmdletBinding()]
    [Parameter(Mandatory=$true)]
    [string]$TemplateFilePath,
    [Parameter(Mandatory=$true)]
    [string]$ParametersFilePath
)

Add-AzureRmAccount | Out-Null #TODO: Create ServicePrincipal with a KeyVault

$allSubscriptions = Get-AzureRmSubscription
$InformationPreference = "Continue"
$WarningPreference = "Continue"
$ErrorActionPreference = "Stop"
[string]$resourceGroup = 'Default-ActivityLogAlerts' #Must exist
[string]$deploymentDebugLevel = 'All'
[System.Collections.Hashtable]$actionGroups = @{
    'Maintenance Alerts' = 'MaintAlerts'
    'Service Alerts' = 'SvcAlerts'
}


if(-not (Test-Path -Path $TemplateFilePath))
{
    Write-Output $("Template file {0} not found!" -f $TemplateFilePath)
    exit
}
if(-not (Test-Path -Path $ParametersFilePath))
{
    Write-Output $("Parameters file {0} not found!" -f $ParametersFilePath)
}


foreach($subscription in $allSubscriptions)
{
    $actSubscription = Select-AzureRMSubscription -SubscriptionObject $subscription
    Write-Information -MessageData $("Working on {0}" -f $($actSubscription.Subscription.Name))
    
    foreach($actionGroup in $actionGroups.Keys)
    {
        $params = @{
            Name = $resourceGroup
            ResourceGroupName = $resourceGroup
            TemplateFile = $TemplateFilePath
            TemplateParameterFile = $ParametersFilePath
            groupName = $actionGroup
            groupShortName = $($actionGroups.$actionGroup)
            #DeploymentDebugLevel = $deploymentDebugLevel
        }
        try
        {
            New-AzureRmResourceGroupDeployment @params | Out-Null
            Write-Information -MessageData $("Done deploying ARM template for {0}" -f $($actSubscription.Subscription.Name))
        }
        catch
        {
            Write-Warning -Message $("Failed deploying ARM template for {0}" -f $($actSubscription.Subscription.Name))
        }
    }
    
}
