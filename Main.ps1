# Requires Version 5

# Functions
Function Get-AzureRmResourceTypes
{
	Param(
	[Parameter(Mandatory=$true)]
	[string]$providerNameSpace
	)
	(Get-AzureRmResourceProvider | Where-Object {$_.ProviderNameSpace -eq $providerNameSpace}).ResourceTypes | ForEach-Object {$providerNameSpace + "/" + $_.ResourceTypeName}
}

# Local Template and Parameter File with Resources to Deploy 
[string]$templateFile = "C:\Bin\Scripts\AzureRM\Assessment\Templates\resourcesdeploy.json"
[string]$templateParameterFile = "C:\Bin\Scripts\AzureRM\Assessment\Parameters\resourcesdeploy.parameters.json"

# Local Template and Parameter File with Resource Policy to define and assign
[string]$policyTemplateFile = "C:\Bin\Scripts\Azure\Assessment\Policies\resourcespolicy.json"
[string]$policyTemplateParameterFile = "C:\Bin\Scripts\Azure\Assessment\Parameters\resourcespolicy.parameters.json"

# Other Script Variables
[string]$resourceGroupName = "Assessment-RG"
[string]$deploymentName = "Assesment-Deployment"
[string]$location = "West Europe"

# Import the AzureRM module, end script when not OK
Write-Host -ForeGroundColor Green "Importing the AzureRM module"
Import-Module AzureRM -ErrorAction Stop

# Login to Azure
Write-Host -ForeGroundColor Green "Login to Azure"
Connect-AzureRmAccount

# Select the proper Azure subscription using a Choice Menu
Write-Host -ForeGroundColor Green "Setting the proper Azure Subscription Id"
$azureSubscription = Get-AzureRmSubscription
Set-AzureRmContext -SubscriptionId $azureSubscription.Id

# First we need to deploy a Resource Group if it doesn't exist already
Write-Host -ForeGroundColor Green "Checking if Resource Group $resourceGroupName already exists in location $location"
Get-AzureRmResourceGroup -Name $resourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue

if ($notPresent)
{
	Write-Host -ForeGroundColor Green "Deploying Resource Group $resourceGroupName in location $location"
	New-AzureRmResourceGroup -ErrorAction Stop -Name $resourceGroupName -Location $location

	# Add Tags with keeping existing tags
	Write-Host -ForeGroundColor Green "Adding Tags to Resource Group $resourceGroupName"
	$tags = (Get-AzureRmResourceGroup -Name $resourceGroupName).Tags
	$tags += @{Environment = "Test"; Company = "Sentia"}
	Set-AzureRmResourceGroup -ErrorAction Stop -Tag $tags -Name $resourceGroupName
}

# First Test Deployment of SA
Write-Host -ForeGroundColor Green "Testing Deployment for Storage Account in $resourceGroupName"
Test-AzureRmResourceGroupDeployment -ErrorAction Stop -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile  $templateParameterFile

# If OK, then Deploy SA
Write-Host -ForeGroundColor Green "Executing Deployment for Storage Account in $resourceGroupName"
New-AzureRmResourceGroupDeployment -ErrorAction Stop -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $templateParameterFile

# Register ResourceProvider NameSpace "PolicyInsights". Registering this resource provider makes sure that your subscription works with it.
Write-Host -ForeGroundColor Green "Registering AzureRmResourceProvider for $($azureSubscription.Id)"
Register-AzureRmResourceProvider -ErrorAction Stop -ProviderNamespace Microsoft.PolicyInsights

# Create Policy Assignment Scope
[string]$assignmentScope = "/subscriptions/$($azureSubscription.SubscriptionId)" 

# Collect all Allowed Resource Provider Namespaces (visible from this location) in an array
Write-Host -ForeGroundColor Green "Collecting Allowed Resource Types"
[array]$allowedResourceTypes = @(Get-AzureRmResourceTypes -ProviderNamespace "Microsoft.Compute")
[array]$allowedResourceTypes += @(Get-AzureRmResourceTypes -ProviderNamespace "Microsoft.Storage")

# Now Create a Custom Policy Definition from Template and Parameter File
Write-Host -ForeGroundColor Green "Creating a new Policy Definition"
$policyDefinition = New-AzureRmPolicyDefinition -Name "allowed-resourcetypes" -DisplayName "Allowed resource types" -Description "This policy enables you to specify the resource types that your organization can deploy." -Policy $policyTemplateFile -Parameter $policyTemplateParameterFile -Mode All

# Param the AllowedResourceTypes array in the policy assignment for the given Scope
Write-Host -ForeGroundColor Green "Assigning the Policy Definition"
New-AzureRMPolicyAssignment -ErrorAction Stop -Name "Allow Microsoft.Compute and Microsoft.Storage" -Scope $assignmentScope -PolicyDefinition $policyDefinition -listOfResourceTypesAllowed $allowedResourceTypes

# Log Off from Azure
Write-Host -ForeGroundColor Green "Logging out from Azure"
Disconnect-AzureRmAccount