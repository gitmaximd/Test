<#
Param
(
    [Parameter(Mandatory=$true)]
    [string]$configFilePath = ''
)
#>
function ConvertConfigToVariables
{
    [CmdletBinding()]

    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$configFile = ''
    )

    try
    {
        [System.Collections.ArrayList]$global:grpVariables = @()
        $grpConfig = (Get-Content -Path $configFile -Raw) -join "`n" | ConvertFrom-Json
        $grpConfig.psobject.Properties | Where-Object {$_.MemberType -like 'NoteProperty'} | ForEach-Object {
            $grpVariables.Add($_.Name) | Out-Null
            New-Variable -Name $_.name -Value $_.value -Scope Global
        }
    }
    catch
    {
        Write-Error "Failed to import configuration file $configFile"
        exit
    }
}

function ParseAutomationForm
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$formFile
    )
    $xmlObj = New-Object System.Xml.XmlDocument
    $xmlObj.Load($formFile)
    return $xmlObj.AzureIaaSAutomation
}
function ProvisionOUStructure
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$projectName = '',
        [Parameter(Mandatory=$true)]
        [string]$projectOwner = '',
        [Parameter(Mandatory=$false)]
        [string]$projectExpirationDate = ''
    )
    if(-not [ADSI]::Exists("LDAP://OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"))
    {
        try
        {
            $adContextObj = New-Object System.DirectoryServices.DirectoryEntry('LDAP://OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva')
            $adOUObj = $adContextObj.Children.Add("OU=$projectName",'OrganizationalUnit')
            $adOUObj.CommitChanges()
            $adContextObj.Dispose()
            $adOUObj.Dispose()
        }
        catch
        {
            "Failed to create OU {0}" -f "OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"
            exit
        }
        try
        {
            $projectOwnerDN = GetUserDN -userAccount $projectOwner
            $adContextObj = New-Object System.DirectoryServices.DirectoryEntry("LDAP://OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva")
            $adContextObj.InvokeSet('managedby',$projectOwnerDN)
            $adContextObj.InvokeSet('adminDescription',$projectExpirationDate)
            $adContextObj.CommitChanges()
        }
        catch
        {
            "Failed to set Project Owner"
        }
    }
    else
    {
        "The OU {0} already exists" -f "OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"
    }
    if(-not [ADSI]::Exists("LDAP://OU=SRV,OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"))
    {
        try
        {
            $adContextObj = New-Object System.DirectoryServices.DirectoryEntry("LDAP://OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva")
            $adOUObj = $adContextObj.Children.Add("OU=SRV",'OrganizationalUnit')
            $adOUObj.CommitChanges()
            $adContextObj.Dispose()
            $adOUObj.Dispose()
        }
        catch
        {
            "Failed to create OU {0}" -f "OU=SRV,OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"
            exit
        }
    }
    else
    {
        "The OU {0} already exists" -f "OU=SRV,OU=$projectName,OU=Systems,OU=TevaCloud,DC=Apps,DC=Teva"
    }
}

function GetUserDN
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        #[string]$upn = '' # UPN
        [string]$userAccount = '' # sAMAccountName
    )
    $adSearcher = New-Object System.DirectoryServices.DirectorySearcher
    $adSearcher.SearchRoot = 'GC://DC=Apps,DC=Teva'
    #$adSearcher.Filter = "(&(objectClass=user)(userprincipalname=$upn))"
    $adSearcher.Filter = "(&(objectClass=user)(samaccountname=$userAccount))"
    [void]$adSearcher.PropertiesToLoad.AddRange(@('userprincipalname','distinguishedname'))
    $adSearcherResult = $adSearcher.FindOne()
    if($adSearcherResult)
    {
        return $adSearcherResult.Properties.distinguishedname[0]
    }
    else
    {
        "UPN {0} not found" -f $userAccount
    }
}

function ProvisionADGroups
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$projectName = '',
        [Parameter(Mandatory=$true)]
        [string]$projectOwner = '',
        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList]$adminUsers = '',
        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList]$regularUsers = '',
        [Parameter(Mandatory=$true)]
        [string]$targetOU = ''
    )

    $adGrpContextObj = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$targetOU")
    $adGrpAdmObj = $adGrpContextObj.Create('group',"CN=$($projectName)_Admins")
    $adGrpAdmObj.Put('groupType', '0x00000004' -bor '&H80000000')
    $adGrpAdmObj.Put('sAMAccountName',"$($projectName)_Admins")
    $adGrpAdmObj.Put('Description',"Admin accounts for $projectName servers")
    $adGrpAdmObj.Put('Info','Additional information')
    $adGrpAdmObj.Put('managedBy',$projectOwner)
    $adGrpAdmObj.SetInfo()

    foreach($adminUser in $adminUsers)
    {
        $adMemberDN = GetUserDN -userAccount $adminUser
        $adGrpAdmObj.add("LDAP://$adMemberDN")
        $adGrpAdmObj.setInfo()
    }
    $allUsers = $adminUsers + $regularUsers
    foreach($user in $allUsers)
    {
        $adMemberDN = GetUserDN -userAccount $user
        $adGrpRDSObj = New-Object System.DirectoryServices.DirectoryEntry('LDAP://CN=RDS_Users,OU=GRP,OU=AppsUsers,DC=Apps,DC=Teva')
        $adGrpRDSObj.add("LDAP://$adMemberDN")
        $adGrpRDSObj.setInfo()
    }
}

#ConvertConfigToVariables -configFile $configFilePath
$configParameters = ParseAutomationForm -formFile "F:\Scripts\i_0_.w_tevacorp_mdavidov_2017-09-13T203404.xml"
$projectOwner = $configParameters.General.projectOwner.Person.AccountId.Split('\')[-1]
$projectName = $configParameters.General.projectName
$projectExpirationDate = $configParameters.General.projectExpirationDate
[System.Collections.ArrayList]$adminUsers = @()
[System.Collections.ArrayList]$regularUsers = @()
$configParameters.Accounts.listAdminAccounts.Person.AccountId|%{$adminUsers.Add($($_.split('\')[-1]))}
$configParameters.Accounts.listRegAccounts.Person.AccountId|%{$regularUsers.Add($($_.split('\')[-1]))}
ProvisionOUStructure -projectName $projectName -projectOwner $projectOwner -projectExpirationDate $projectExpirationDate
ProvisionADGroups -projectName $projectName -adminUsers $adminUsers -regularUsers $regularUsers -projectOwner $projectOwnerDN -targetOU 'OU=GRP,OU=AppsUsers,DC=Apps,DC=Teva'