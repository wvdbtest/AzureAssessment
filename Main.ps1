# Requires Version 5

<#
.SYNOPSIS 
This script deploys the resources defined in the ARM template and parameter file into a new resource group.

.DESCRIPTION
An ARM template (preferably named 'resourcesdeploy.json') and corresponding parameter file (optional, preferably named 'resourcesdeploy.parameters.json') describe the resources that will be deployed into MS Azure.
The script checks whether or not the resource group (which is passed as $resourceGroupName) exists, and creates it if it doesn't. This resource group will be in the region specified by $location (defaults to "West Europe" if no location was given).
The PowerShell session needs to be logged in to an Azure Account for this to work, and the Azure PowerShell context should be set to the desired subscription.
All the resources will then be deployed into the resource group.

.PARAMETER ResourceGroupName
Name of the resource group into which the resources will be deployed.

.PARAMETER DeploymentName
Name of the deployment.

.PARAMETER TemplateFile
Relative filepath (or URL) of the ARM template file. (e.g. '.\resourcesdeploy.json')

.PARAMETER TemplateParameterFile
Relative filepath (or URL) of the ARM template parameter file (e.g. '.\resourcesdeploy.parameters.json')

.PARAMETER policyTemplateFile
Relative filepath (or URL) of the Resource Policy template file. (e.g. '.\resourcespolicy.json')

.PARAMETER policyTemplateParameterFile
Relative filepath (or URL) of the Resource Policy parameter file (e.g. '.\resourcespolicy.parameters.json')

.PARAMETER Location
The desired Azure region (defaults to West Europe).

.EXAMPLE
.\Main.ps1 -ResourceGroupName myRG -DeploymentName myDep -TemplateFile '.\resourcesdeploy.json' -TemplateParameterFile '.\resourcesdeploy.parameters.json' -Location 'North Europe'
#>

Param(
[Parameter(Mandatory=$true)]
[string]$resourceGroupName,
[Parameter(Mandatory=$true)]
[string]$deploymentName,
[Parameter(Mandatory=$true)]
[string]$templateFile,
[Parameter(Mandatory=$true)]
[string]$templateParameterFile,
[Parameter(Mandatory=$false)]
[string]$location="West Europe",
[Parameter(Mandatory=$true)]
[string]$policyTemplateFile,
[Parameter(Mandatory=$true)]
[string]$policyTemplateParameterFile
)

# Functions
Function Get-AzureRmResourceTypes
{
	Param(
	[Parameter(Mandatory=$true)]
	[string]$providerNameSpace
	)
	
	Return (Get-AzureRmResourceProvider | Where-Object {$_.ProviderNameSpace -eq $providerNameSpace}).ResourceTypes | ForEach-Object {$providerNameSpace + "/" + $_.ResourceTypeName}
}

Function Read-Choice 
{
	Param(
		[Parameter(Mandatory=$false)]
		[string]$Message,		
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[array]$Choices,		
		[Parameter(Mandatory=$false)]
		[int]$DefaultChoice = 1,
		[Parameter(Mandatory=$false)]		
		[string]$Title=[string]::Empty 
	)
	
	# Create Menu
	[System.Management.Automation.Host.ChoiceDescription[]]$Poss = $Choices | % {New-Object System.Management.Automation.Host.ChoiceDescription "&$($_)", "Sets $_ as the current Azure Subscription."}

	# Output Menu
	$selectedAzureSubscription = $Host.UI.PromptForChoice($Title,$Message,$Poss,$DefaultChoice)
	
	# Return
	Return $selectedAzureSubscription
}

# Start timer
$stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

# Import the AzureRM module, end script when not OK
Write-Host -ForeGroundColor Yellow "Importing the AzureRM module"
Import-Module AzureRM -ErrorAction Stop

# Login to Azure
Write-Host -ForeGroundColor Yellow "Please login to Azure first"
Connect-AzureRmAccount -ErrorAction Stop

# Check and Display the Azure Subcriptions
[array]$azureSubscriptions = @(Get-AzureRmSubscription)
$azureSubscriptions

# When multiple, select the appropriate Azure subscription in a Choice Menu
if ($azureSubscriptions.Count -gt 1)
{
	Write-Host -ForeGroundColor Yellow "Please Select the appropriate Azure Subscription by entering the choice number."
	
	# Display objects in the Shell (will be the Subscription Ids)
	$azureSubscriptions | % {$Id = 0} {"$Id : $_"; $Id++}
	
	# Prompt for Choice
	$azureSubscription = $azureSubscriptions[(Read-Choice -Message " " -Choices (0..($Id -1)) -DefaultChoice ($Id -1))]
}
else
{
	$azureSubscription = $azureSubscriptions
}

# Set Azure RM Context using the Subscription Id
Write-Host ""
Write-Host -ForeGroundColor Yellow "Setting the Azure RM Context to Azure Subscription Id $($azureSubscription.Id)"
Set-AzureRmContext -ErrorAction Stop -SubscriptionId $azureSubscription.Id

# Now we need to deploy a Resource Group first, if it doesn't exist already
Write-Host -ForeGroundColor Yellow "Checking if Resource Group $resourceGroupName already exists in location $location"
$resourceGroupObject = Get-AzureRmResourceGroup -ErrorAction SilentlyContinue -ErrorVariable notPresent -Name $resourceGroupName

if ($notPresent)
{
	Write-Host -ForeGroundColor Yellow "Deploying Resource Group $resourceGroupName in location $location"
	New-AzureRmResourceGroup -ErrorAction Stop -Name $resourceGroupName -Location $location
}
else
{
	Write-Host -ForeGroundColor Green "Resource Group $resourceGroupName already exists - continuing with existing object!"
}

# Add Tags with keeping existing tags and avoid fatal error when one of the tags already exists - in that case, skip it
Write-Host -ForeGroundColor Yellow "Checking Tags for Resource Group $resourceGroupName"
[hashtable]$tags = $resourceGroupObject.Tags

if ($tags)
{
	if (!$tags.containskey("Environment")) {$tags += @{Environment = "Test"}}
	if (!$tags.containskey("Company")) {$tags += @{Company = "Sentia"}}
}
else
{
	$tags = @{Environment = "Test"; Company = "Sentia"}
}

# Set Tags
Write-Host -ForeGroundColor Yellow "Setting Tags for Resource Group $resourceGroupName"
Set-AzureRmResourceGroup -ErrorAction Stop -Tag $tags -Name $resourceGroupName

# First Test Deployment of Resources using template and parameter file
Write-Host -ForeGroundColor Yellow "Testing Deployment for Resources in $resourceGroupName"
Test-AzureRmResourceGroupDeployment -ErrorAction Stop -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $templateParameterFile
Write-Host -ForeGroundColor Green "All fine - continuing!"

# If OK, then Deploy Resources
Write-Host -ForeGroundColor Yellow "Executing Deployment for Resources in $resourceGroupName"
New-AzureRmResourceGroupDeployment -ErrorAction Stop -Name $deploymentName -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $templateParameterFile

# Register ResourceProvider NameSpace "PolicyInsights". Registering this resource provider makes sure that your subscription works with it
Write-Host -ForeGroundColor Yellow "Registering AzureRmResourceProvider for Azure Subscription Id $($azureSubscription.Id)"
Register-AzureRmResourceProvider -ErrorAction Stop -ProviderNamespace Microsoft.PolicyInsights

# Collect all Resource Provider Namespaces - visible from this location - to allow the underlying Resource Types, in an array
Write-Host -ForeGroundColor Yellow "Collecting Allowed Resource Types"
[array]$allowedResourceTypes = @(Get-AzureRmResourceTypes -ProviderNamespace "Microsoft.Compute")
[array]$allowedResourceTypes += @(Get-AzureRmResourceTypes -ProviderNamespace "Microsoft.Storage")

# Set Policy Assignment Scope. Underlying Resource Groups will inherit the policy definition and assignment when set to the Subscription
[string]$assignmentScope = "/subscriptions/$($azureSubscription.SubscriptionId)" 

# First check if the policy definition already exists, this determines the cmdlet to change the policyrules
Write-Host -ForeGroundColor Yellow "Checking if Policy Defintion already exists"
$policyDefinition = Get-AzureRmPolicyDefinition | Where-Object {$_.Name -eq "custom-allowed-resourcetypes"}

# Now prepare the Custom Policy Definition from Template and Parameter File. Remark: New-AzureRmPolicyDefinition does not have a -Scope parameter yet
if (!$policyDefinition)
{
	Write-Host -ForeGroundColor Yellow "Creating new Policy Definition"
	$policyDefinition = New-AzureRmPolicyDefinition -ErrorAction Stop -ErrorVariable policyDefinitionFailed -Name "custom-allowed-resourcetypes" -DisplayName "Custom Allowed Resource Types" -Description "This policy enables you to specify the resource types that your organization can deploy." -Policy $policyTemplateFile -Parameter $policyTemplateParameterFile
}
else
{
	Write-Host -ForeGroundColor Yellow "Modifying existing Policy Definition"
	$policyDefinition = Set-AzureRmPolicyDefinition -ErrorAction Stop -ErrorVariable policyDefinitionFailed -Name "custom-allowed-resourcetypes" -DisplayName "Custom Allowed Resource Types" -Description "This policy enables you to specify the resource types that your organization can deploy." -Policy $policyTemplateFile -Parameter $policyTemplateParameterFile
}

if (!$policyDefinitionFailed)
{
	# Param the AllowedResourceTypes array in the policy assignment for the given Scope
	Write-Host -ForeGroundColor Yellow "Assigning the Policy Definition"
	New-AzureRMPolicyAssignment -ErrorAction Stop -Name "Only Allow Microsoft.Compute and Microsoft.Storage" -Scope $assignmentScope -PolicyDefinition $policyDefinition -listOfResourceTypesAllowed $allowedResourceTypes
}
else
{
	Write-Host -ForeGroundColor Red "Assignment was skipped as the creation of the Policy Definition has failed."
	Write-Host ""
}

# Log Off from Azure
Write-Host -ForeGroundColor Yellow "Logging out from Azure"
Disconnect-AzureRmAccount

# Stop timer and show elapsed time
$stopWatch.Stop()
"Elapsed time: {0:00} hours, {1:00} minutes, {2:00} seconds, {3:000} milliseconds" -f $stopWatch.Elapsed.Hours, $stopWatch.Elapsed.Minutes, $stopWatch.Elapsed.Seconds, $stopWatch.Elapsed.Milliseconds