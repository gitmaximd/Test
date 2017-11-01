Param
(
    [CmdletBinding()]
    [Parameter(Mandatory=$true)]
    [string]$configFile
)

### Begin Functions ###
function ConnectAzureRM
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [pscredential]$credsAzure
        # TODO: Use ServicePrincipal instead of credentials
    )
    try
    {
        $connectionStatus = Add-AzureRmAccount -Credential $credsAzure -ErrorAction Stop
    }
    catch
    {
        "Failed connecting to Azure RM"
        exit
    }
    return $connectionStatus
}

function GetPolicyParameters
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$policyParametersFile
    )
    $psoParamObj = (Get-Content $policyParametersFile -Raw | ConvertFrom-Json)
    $result = $psoParamObj | Get-Member | Where-Object{$_.MemberType -eq 'NoteProperty'} | ForEach-Object {
        @{$_.Name=$psoParamObj.$($_.Name).metadata.value}
    }
    return $result
}
function SetAzureSubscriptionPolicy
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [array]$subscription,
        [Parameter(Mandatory=$true)]
        [string]$policyDefinitionFile,
        [Parameter(Mandatory=$false)]
        [string]$policyParametersFile,
        [Parameter(Mandatory=$false)]
        [string]$hashPolicyDefinitionFile,
        [Parameter(Mandatory=$false)]
        [string]$hashPolicyParametersFile
    )

    Begin
    {
        #TODO: Use logging function
        "Setting policy for {0}({1})" -f $($subscription.Name), $($subscription.Id)
    }
    Process
    {
        #$policyParamObj = GetPolicyParameters -policyParametersFile $policyParametersFile
        try
        {
            # TODO: Drop hard coded values
            $azureDefaultPolicyDefinition = Get-AzureRmPolicyDefinition | Where-Object{$_.Properties.DisplayName -like 'TEVA-DefaultPolicy'}
        }
        catch
        {
            $azureDefaultPolicyDefinition = $null
        }
        $azureDefaultPolicyAssignment = Get-AzureRmPolicyAssignment -Scope "/subscriptions/$($subscription.Id)"
        if($azureDefaultPolicyDefinition.Name) # Check if definition exists
        {
            if($azureDefaultPolicyDefinition.Name -eq $hashPolicyDefinitionFile) # Check if the version is the same
            {
                "Policy definition found on {0}({1})" -f $($subscription.Name),$($subscription.Id)
                if($azureDefaultPolicyAssignment) # Check if the policy definition assigned
                {
                    "Policy definition already assigned on {0}({1})" -f $($subscription.Name),$($subscription.Id)
                }
                else # Otherwise assign policy definition
                {
                    try
                    {
                        $azurePolicy = Get-AzureRmPolicyDefinition -Name $hashPolicyDefinitionFile
                        $params = @{
                            Name = 'TEVA-DefaultPolicy'
                            DisplayName = 'TEVA-DefaultPolicy'
                            PolicyDefinition = $azurePolicy
                            Scope = "/subscriptions/$($subscription.Id)"
                            PolicyParameterObject = $policyParamObj
                        }
                        New-AzureRmPolicyAssignment @params -ErrorAction Stop
                        "Done assigning policy on {0}({1})" -f $($subscription.Name),$($subscription.Id)
                    }
                    catch
                    {
                        "Failed assigning policy on {0}({1})" -f $($subscription.Name),$($subscription.Id)
                    }
                }
            }
            else # Otherwise remove the definition
            {
                if($azureDefaultPolicyAssignment) # Check if the definition is assigned and remove it
                {
                    "Remove policy assignment {0}" -f $($azureDefaultPolicyAssignment.ResourceId)
                    try
                    {
                        Remove-AzureRmPolicyAssignment -Id $azureDefaultPolicyAssignment.ResourceId -Confirm:$false
                    }
                    catch
                    {
                        "Failed removing policy assignment {0}" -f $($azureDefaultPolicyAssignment.ResourceId)
                        continue
                    }
                }
                else
                {
                    "Remove policy definition {0}" -f $($azureDefaultPolicyDefinition.ResourceId)
                    Remove-AzureRmPolicyDefinition -Id $($azureDefaultPolicyDefinition.ResourceId) -Force:$true -Confirm:$false
                    $params = @{
                        Name = $hashPolicyDefinitionFile
                        DisplayName = 'TEVA-DefaultPolicy'
                        Description = 'Teva default restrictions'
                        Policy = $policyDefinitionFile
                        #TODO: Create a condition to decide if the Parameter is required
                        Parameter = $policyParametersFile
                    }
                    try
                    {
                        $azurePolicy = New-AzureRmPolicyDefinition @params -ErrorAction Stop
                        $params = $null
                    }
                    catch
                    {
                        "Failed creating policy definitions in {0}({1})" -f $($subscription.Name),$($subscription.Id)
                        $params = $null
                        continue
                    }
                    try
                    {
                        $params = @{
                            Name = 'TEVA-DefaultPolicy'
                            DisplayName = 'TEVA-DefaultPolicy'
                            PolicyDefinition = $azurePolicy
                            Scope = "/subscriptions/$($subscription.Id)"
                            PolicyParameterObject = $policyParamObj
                        }
                        New-AzureRmPolicyAssignment @params -ErrorAction Stop
                    }
                    catch
                    {
                        "Failed assigning policy on {0}({1})" -f $($subscription.Name),$($subscription.Id)
                    }
                }
            }
        }
        else # Definition does not exists and policy is not assigned
        {
            $params = @{
                Name = $hashPolicyDefinitionFile
                DisplayName = 'TEVA-DefaultPolicy'
                Description = 'Teva default restrictions'
                Policy = $policyDefinitionFile
                #TODO: Create a condition to decide if the Parameter is required
                Parameter = $policyParametersFile
            }
            try
            {
                New-AzureRmPolicyDefinition @params -ErrorAction Stop
                $params = $null
            }
            catch
            {
                "Failed creating policy definitions in {0}({1})" -f $($subscription.Name),$($subscription.Id)
                $params = $null
                continue
            }
            try
            {
                $params = @{
                    Name = 'TEVA-DefaultPolicy'
                    DisplayName = 'TEVA-DefaultPolicy'
                    PolicyDefinition = $azureDefaultPolicyDefinition
                    Scope = "/subscriptions/$($subscription.Id)"
                    PolicyParameterObject = $policyParamObj
                }
                New-AzureRmPolicyAssignment @params
                "Done assigning policy on {0}({1})" -f $($subscription.Name),$($subscription.Id)
            }
            catch
            {
                "Failed assigning policy on {0}({1})" -f $($subscription.Name),$($subscription.Id)
            }
        }
    }
    End
    {
        "Done with {0}" -f $($subscription.Id)
    }
}

### End Functions ###


### Begin Script ###

if(-not (Test-Path -Path $configFile))
{
    "Configuration file not found {0}" -f $configFile
}
else # Convert JSON to variables
{
    [System.Collections.ArrayList]$variables = @()
    $psoConfig = (Get-Content -Path $configFile -Raw) -join "`n" | ConvertFrom-Json
    $psoConfig.psobject.Properties | Where-Object {$_.MemberType -like 'NoteProperty'} | ForEach-Object {
        [void]$variables.Add($_.Name)
        New-Variable -Name $_.name -Value $_.value
    }
    if(-not (Test-Path -Path $policyDefinitionFile))
    {
        "Policy definition file not found {0}" -f $policyDefinitionFile
        exit
    }
    if(-not (Test-Path -Path $policyParametersFile))
    {
        "Policy definition file not found {0}" -f $policyParametersFile
        exit
    }
}



ConnectAzureRM -credsAzure (Get-Credential)
$policyParamObj = GetPolicyParameters -policyParametersFile $policyParametersFile
$azureSubscriptions = Get-AzureRmSubscription | Select-Object Name,Id
$hashPolicyDefinitionFile = (Get-FileHash -Path $policyDefinitionFile -Algorithm MD5).Hash
$hashPolicyParametersFile = (Get-FileHash -Path $policyParametersFile -Algorithm MD5).Hash
foreach($subscription in $azureSubscriptions)
{
    Set-AzureRmContext -SubscriptionId $subscription.Id | Out-Null
    SetAzureSubscriptionPolicy -subscription $subscription `
        -policyDefinitionFile $policyDefinitionFile -policyParametersFile $policyParametersFile `
        -hashPolicyDefinitionFile $hashPolicyDefinitionFile -hashPolicyParametersFile $hashPolicyParametersFile
}

# Clear variables
$variables | ForEach-Object{
    Remove-Variable -Name $_ -Confirm:$false
}
### End Script ###