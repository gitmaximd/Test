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





$configParameters = ParseAutomationForm -formFile "C:\Sources\GitHub-Teva\Automation\Infrastructure\i_0_.w_tevacorp_mdavidov_2017-09-13T203404.xml"
$projectOwner = $configParameters.General.projectOwner.Person.AccountId.Split('\')[-1]
$projectName = $configParameters.General.projectName
$projectExpirationDate = $configParameters.General.projectExpirationDate