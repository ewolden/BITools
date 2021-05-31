##Retrieve all arguments
[CmdletBinding()]
param(
    [parameter(Mandatory = $true, HelpMessage='ADF/Synapse file(s) path!')] [String] $inputpath,
    [parameter(Mandatory = $false, HelpMessage='Config file filepath!')] [String] $configFilePath = "")#,[bool]$SummaryOutput = $true,[bool]$VerboseOutput = $false,[bool]$debug = $false)

if ((Get-Item $inputpath) -is [System.IO.DirectoryInfo]) {
    $isFolder = $true
}

if ($configFilePath -eq "") {
    $configFilePath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    $configFilePath = "$($configFilePath)\defaultconfig.json" 
}
$config = Get-Content -Raw -Path $configFilePath | ConvertFrom-Json

$severities = $config.severity
$checkDetails = $config.checkDetails
$namingConvention = $config.namingConvention
$charsNamingConvention = $config.charsNamingConvention
$importance = ($severities | Sort-Object -Property value -Descending).name

$validRegex = '^[' + $charsNamingConvention + ']*$'
$negativeRegex = '[^' + $charsNamingConvention + ']'

#############################################################################################
# Helper functions for check of naming conventions
#############################################################################################
function CheckPrefix {
    param (
        [parameter(Mandatory = $true)] [String] $ObjectName,
        [parameter(Mandatory = $true)] [String] $ObjectType
    )
    $PfxObject = ($namingConvention | Where-Object -Property objectName -eq $ObjectType).prefix
    $PfxLength = $PfxObject.Length

    $Check = ($ObjectName.Substring(0, $PfxLength) -eq $PfxObject)
    return [PSCustomObject]@{passed=$Check;prefix=$PfxObject}
}

function CheckName {
    param (
        [parameter(Mandatory = $true)] [String] $ObjectName
    )

    $Check = ($ObjectName -match $validregex)
    if(!$Check) {
        $offendingCharacters = (Select-String $negativeRegex -input $ObjectName -AllMatches | ForEach-Object {$_.matches.value} | Sort-Object | Get-Unique | Join-String -DoubleQuote -Separator ', ')
    }
    return [PSCustomObject]@{passed=$Check;offendingCharacters=$offendingCharacters}
}

#############################################################################################
# Helper functions for identifying all activities
#############################################################################################

function FindSubActivities {
    param (
        [parameter(Mandatory = $true)] [PSCustomObject] $Activities
    )
    $newActivities = @()
    ForEach($Activity in $Activities){
        if(($Activity.type -eq "Until") -or $Activity.type -eq "ForEach"){
            ForEach($SubActivity in $Activity.typeProperties.activities) {
                if(-not ($Activities -contains $SubActivity)){
                    $newActivities += $SubActivity
                }
            }
        } elseif ($Activity.type -eq "IfCondition") {
            ForEach($SubActivity in $Activity.typeProperties.ifFalseActivities) {
                if(-not ($Activities -contains $SubActivity)){
                    $newActivities += $SubActivity
                }
            }
            ForEach($SubActivity in $Activity.typeProperties.ifTrueActivities) {
                if(-not ($Activities -contains $SubActivity)){
                    $newActivities += $SubActivity
                }
            }
        } elseif ($Activity.type -eq "Switch") {
            ForEach($Case in $Activity.typeProperties.cases) {
                ForEach($SubActivity in $Case.activities) {
                    if(-not ($Activities -contains $SubActivity)){
                        $newActivities += $SubActivity
                    }
                }
            }
        }
    }
    return $newActivities
}

#############################################################################################
if(-not (Test-Path -Path $inputpath))
{
    Write-Host "##vso[task.LogIssue type=error;]File/folder not found. Please check the path provided."
    exit 1
}

if ($isFolder) {
    #Parse folder into resource parts
    $LinkedServices = Get-ChildItem -Recurse "$($inputpath)\linkedService" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
    $Datasets = Get-ChildItem -Recurse "$($inputpath)\dataset" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
    $Pipelines = Get-ChildItem -Recurse "$($inputpath)\pipeline" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
    $DataFlows = Get-ChildItem -Recurse "$($inputpath)\dataflow" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
    $Triggers = Get-ChildItem -Recurse "$($inputpath)\trigger" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }
    $SQLScripts = Get-ChildItem -Recurse "$($inputpath)\sqlscript" | ForEach-Object { Get-Content $_ | ConvertFrom-Json }

    $resources = @($LinkedServices; $Datasets; $Pipelines; $DataFlows; $Triggers; $SQLScripts)
} else {
    #Parse template into resource parts
    #Split into synapse and ADF methods:
    $template = Get-Content $inputpath | ConvertFrom-Json
    $resources = $template.resources
    if ($template.variables -match "Microsoft.DataFactory/factories/") { #This is a data factory template 
        $LinkedServices = $resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/linkedServices"}
        $Datasets = $resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/datasets"}
        $Pipelines = $resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/pipelines"}
        $DataFlows = $resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/dataflows"}
        $Triggers = $resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/triggers"}
    } elseif ($template.variables -match "Microsoft.Synapse/workspaces/") { #This is a synapse template
        $LinkedServices = $resources | Where-Object {$_.type -eq "Microsoft.Synapse/workspaces/linkedServices"}
        $Datasets = $resources | Where-Object {$_.type -eq "Microsoft.Synapse/workspaces/datasets"}
        $Pipelines = $resources | Where-Object {$_.type -eq "Microsoft.Synapse/workspaces/pipelines"}
        $DataFlows = $resources | Where-Object {$_.type -eq "Microsoft.Synapse/workspaces/dataflows"}
        $Triggers = $resources | Where-Object {$_.type -eq "Microsoft.Synapse/workspaces/triggers"}
    }
    
}

#Set Activities
$Activities = $Pipelines.properties.activities
$newActivities = FindSubActivities($Activities)
$Activities += $newActivities
while ($newActivities.Count -ge 1) {
    $newActivities = FindSubActivities($Activities)
    $Activities += $newActivities
}
#$resources += $Activities

#Output variables
$CheckNumber = 0
$CheckDetail = ""
$Severity = ""
$CheckCounter = 0
$SummaryTable = @()
$VerboseDetailTable = @()

#String helper functions
function CleanName {
    param (
        [parameter(Mandatory = $true)] [String] $RawValue
    )
    if($isFolder) {
        $CleanName = $RawValue
    } else {
        $CleanName = $RawValue.substring($RawValue.IndexOf("/")+1, $RawValue.LastIndexOf("'") - $RawValue.IndexOf("/")-1)
    }
    
    return $CleanName
}

function CleanType {
    param (
        [parameter(Mandatory = $true)] [String] $RawValue
    )
    $CleanName = $RawValue.substring($RawValue.LastIndexOf("/")+1, $RawValue.Length - $RawValue.LastIndexOf("/")-1)
    return $CleanName
}

#############################################################################################
#Review resource dependants
#############################################################################################
$ResourcesList = New-Object System.Collections.ArrayList($null)
$DependantsList = New-Object System.Collections.ArrayList($null)
#Get resources
if($isFolder) {
    ForEach($Dataset in $Datasets) {
        $CompleteResource =  "datasets" + "|" + $Dataset.name
        if(-not ($ResourcesList -contains $CompleteResource)) {
            [void]$ResourcesList.Add($CompleteResource)
        }
    }
    ForEach($Pipeline in $Pipelines) {
        $CompleteResource =  "pipelines" + "|" + $Pipeline.name
        if(-not ($ResourcesList -contains $CompleteResource)) {
            [void]$ResourcesList.Add($CompleteResource)
        }
    }
    ForEach($DataFlow in $DataFlows) {
        $CompleteResource =  "dataflows" + "|" + $DataFlow.name
        if(-not ($ResourcesList -contains $CompleteResource)) {
            [void]$ResourcesList.Add($CompleteResource)
        }
    }
    ForEach($Trigger in $Triggers) {
        $CompleteResource =  "triggers" + "|" + $Trigger.name
        if(-not ($ResourcesList -contains $CompleteResource)) {
            [void]$ResourcesList.Add($CompleteResource)
        }
    }
} else {
    ForEach($Resource in $resources) {
        $ResourceName = CleanName -RawValue $Resource.name
        $ResourceType = CleanType -RawValue $Resource.type
        
        $CompleteResource =  $ResourceType + "|" + $ResourceName
        
        if(-not ($ResourcesList -contains $CompleteResource)) {
            [void]$ResourcesList.Add($CompleteResource)
        }
    }
}
#Get dependants
if($isFolder) {
    #for pipeline check all activities
    ForEach($Activity in $Activities) {
        if($Activity.type -eq "Copy") {
            ForEach($input in $Activity.inputs) {
                $DependantName = "datasets" + "|" + $input.referenceName
                if(-not ($DependantsList -contains $DependantName)) {
                    [void]$DependantsList.Add($DependantName)
                }
            }
            ForEach($output in $Activity.outputs) {
                $DependantName = "datasets" + "|" + $input.referenceName
                if(-not ($DependantsList -contains $DependantName)) {
                    [void]$DependantsList.Add($DependantName)
                }
            }
        } elseif (($Activity.type -eq "Lookup") -Or ($Activity.type -eq "Delete") -Or ($Activity.type -eq "GetMetadata") -Or ($Activity.type -eq "Validation")) {
            $DependantName = "datasets" + "|" + $Activity.typeProperties.dataset.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        } elseif ($Activity.type -eq "SynapseNotebook") {
            $DependantName = "notebooks" + "|" + $Activity.typeProperties.notebook.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        } elseif ($Activity.type -eq "SparkJob") {
            $DependantName = "SparkJobs" + "|" + $Activity.typeProperties.sparkJob.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        } elseif ($Activity.type -eq "ExecuteDataFlow") {
            $DependantName = "dataflows" + "|" + $Activity.typeProperties.dataflow.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        } elseif ($Activity.type -eq "ExecutePipeline") {
            $DependantName = "pipelines" + "|" + $Activity.typeProperties.pipeline.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        } elseif ($Activity.type -in @("Until", "WebActivity", "Switch", "ForEach", "SetVariable", "IfCondition", "WebHook", "AppendVariable", "Wait", "Filter")) {
            #Do nothing
        } else {#should cover rest
            $DependantName = "linkedServices" + "|" + $Activity.linkedServiceName.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        }
    }

    #for datasets check all linked services
    ForEach($Dataset in $Datasets) {
        $DependantName = "linkedServices" + "|" + $Dataset.properties.linkedServiceName.referenceName
        if(-not ($DependantsList -contains $DependantName)) {
            [void]$DependantsList.Add($DependantName)
        }
    }

    #For triggers check all pipelines
    ForEach($Trigger in $Triggers) {
        ForEach($Pipeline in $Dataset.properties.pipelines) {
            $DependantName = "pipelines" + "|" + $Pipeline.pipelineReference.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        }
    }
    #TODO: add source/sink
    #For dataflows check datasets
    ForEach($Dataflow in $DataFlows) {
        ForEach($Dataset in $Dataflow.properties.typeProperties.sources) {
            $DependantName = "datasets" + "|" + $Dataset.dataset.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        }
        ForEach($Dataset in $Dataflow.properties.typeProperties.sinks) {
            $DependantName = "datasets" + "|" + $Dataset.dataset.referenceName
            if(-not ($DependantsList -contains $DependantName)) {
                [void]$DependantsList.Add($DependantName)
            }
        }
    }
} else {
    ForEach($Resource in $resources)# | Where-Object {$_.type -ne "Microsoft.DataFactory/factories/triggers"})
    {
        if($Resource.dependsOn.Count -eq 1)
        {
            $DependantName = CleanName -RawValue $Resource.dependsOn[0].ToString()
            $CompleteDependant = $DependantName.Replace('/','|')

            if(-not ($DependantsList -contains $CompleteDependant))
            {
                [void]$DependantsList.Add($CompleteDependant)
            }
        } else {
            ForEach($Dependant in $Resource.dependsOn)
            {
                $DependantName = CleanName -RawValue $Dependant
                $CompleteDependant = $DependantName.Replace('/','|')

                if(-not ($DependantsList -contains $CompleteDependant))
                {
                    [void]$DependantsList.Add($CompleteDependant)
                }
            }
        }
    }
}

#Get trigger dependants
if($isFolder) {
    ForEach($Trigger in $Triggers){
        if($Trigger.properties.pipelines.Count -ge 1) {
            $CompleteResource = "triggers" + "|" + $Trigger.name
            if(-not ($DependantsList -contains $CompleteResource)) {
                [void]$DependantsList.Add($CompleteResource)
            }
        }
    }
} else {
    ForEach($Resource in $Triggers)
    {
        $ResourceName = CleanName -RawValue $Resource.name
        $ResourceType = CleanType -RawValue $Resource.type
        $CompleteResource = $ResourceType + "|" + $ResourceName

        if($Resource.dependsOn.count -ge 1)
        {
            if(-not ($DependantsList -contains $CompleteResource)) {
                [void]$DependantsList.Add($CompleteResource)
            }
        }
    }
}

#Establish simple redundancy to use later
$RedundantResources = $ResourcesList | Where-Object {$DependantsList -notcontains $_}

#############################################################################################
#Check for pipeline without triggers
#############################################################################################
$CheckDetail = "Pipeline(s) without any triggers attached. Directly or indirectly."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "pipeline_without_triggers"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "pipelines*"})
    {
        $Parts = $RedundantResource.Split('|')

        $CheckCounter += 1
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Pipeline";
            Name = $Parts[1];
            CheckDetail = "Does not have any triggers attached.";
            Severity = $Severity
        }
    }

    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check pipeline with an impossible execution chain.
#############################################################################################
$CheckDetail = "Pipeline(s) with an impossible AND/OR activity execution chain."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "pipeline_impossible_execution_chain"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    $ActivityFailureDependencies = New-Object System.Collections.ArrayList($null)
    $ActivitySuccessDependencies = New-Object System.Collections.ArrayList($null)

    #get upstream failure dependants
    ForEach($Activity in $Activities)
    {
        if($Activity.dependsOn.Count -gt 1)
        {
            ForEach($UpStreamActivity in $Activity.dependsOn)
            {
                if(($UpStreamActivity.dependencyConditions.Contains('Failed')) -or ($UpStreamActivity.dependencyConditions.Contains('Skipped')))
                {  
                    if(-not ($ActivityFailureDependencies -contains $UpStreamActivity.activity))
                    {
                        [void]$ActivityFailureDependencies.Add($UpStreamActivity.activity)
                    }
                }
            }
        }
    }

    #get downstream success dependants
    ForEach($ActivityDependant in $ActivityFailureDependencies)
    {
        ForEach($Activity in $Activities | Where-Object {$_.name -eq $ActivityDependant})
        {
            if($Activity.dependsOn.Count -ge 1)
            {
                ForEach($DownStreamActivity in $Activity.dependsOn)
                {
                    if($DownStreamActivity.dependencyConditions.Contains('Succeeded'))
                    {                  
                        if(-not ($ActivitySuccessDependencies -contains $DownStreamActivity.activity))
                        {
                            [void]$ActivitySuccessDependencies.Add($DownStreamActivity.activity)
                        }
                    }
                }
            }
        }
    }
    
    #compare dependants - do they exist in both lists?
    $Problems = $ActivityFailureDependencies | Where-Object {$ActivitySuccessDependencies -contains $_}
    if($Problems.Count -gt 0)
    {
        $CheckCounter += 1
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Pipeline";
            Name = $PipelineName;
            CheckDetail = "Has an impossible AND/OR activity execution chain.";
            Severity = $Severity
        }
    }
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check for pipeline descriptions
#############################################################################################
$CheckDetail = "Pipeline(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "pipeline_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Pipeline in $Pipelines)
    {
        $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
        $PipelineDescription = $Pipeline.properties.description

        if(([string]::IsNullOrEmpty($PipelineDescription)))
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for pipelines not in folders
#############################################################################################
$CheckDetail = "Pipeline(s) not organised into folders."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "pipeline_not_in_folder"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Pipeline in $Pipelines)
    {
        $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
        $PipelineFolder = $Pipeline.properties.folder.name
        if(([string]::IsNullOrEmpty($PipelineFolder)))
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Not organised into a folder.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for pipelines without annotations
#############################################################################################
$CheckDetail = "Pipeline(s) without annotations."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "pipeline_without_annotation"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Pipeline in $Pipelines)
    {
        $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
        $PipelineAnnotations = $Pipeline.properties.annotations.Count
        if($PipelineAnnotations -le 0)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Does not have any annotations.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for data flow descriptions
#############################################################################################
$CheckDetail = "Data Flow(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "dataflow_without_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($DataFlow in $DataFlows)
    {
        $DataFlowName = (CleanName -RawValue $DataFlow.name.ToString())
        $DataFlowDescription = $DataFlow.properties.description

        if(([string]::IsNullOrEmpty($DataFlowDescription)))
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Data Flow";
                Name = $DataFlowName;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check activity timeout values
#############################################################################################
$CheckDetail = "Activitie(s) with timeout values still set to the service default value of 7 days."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "activity_timeout_value"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Activity in $Activities) {
        $timeout = $Activity.policy.timeout
        if(-not ([string]::IsNullOrEmpty($timeout)))
        {        
            if($timeout -eq "7.00:00:00")
            {
                $CheckCounter += 1           
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = $Activity.Name;
                    CheckDetail = "Timeout policy still set to the service default value of 7 days.";
                    Severity = $Severity
                }
            }
        }
    }

    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check activity descriptions
#############################################################################################
$CheckDetail = "Activitie(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "activity_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Activity in $Activities) 
    {
        $ActivityDescription = $Activity.description
        if(([string]::IsNullOrEmpty($ActivityDescription)))
        {        
            $CheckCounter += 1         
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Activity";
                Name = $Activity.Name;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check foreach activity batch size unset
#############################################################################################
$CheckDetail = "Activitie(s) ForEach iteration without a batch count value set."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "activity_batch_size_unset"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Activity in $Activities | Where-Object {$_.type -eq "ForEach"})
    {   
        [bool]$isSequential = $false #attribute may only exist if changed, assume not present in arm template
        if((-not [string]::IsNullOrEmpty($Activity.typeProperties.isSequential)))
        {
            $isSequential = $Activity.typeProperties.isSequential
        }
        $BatchCount = $Activity.typeProperties.batchCount

        if(!$isSequential)
        {
            if(([string]::IsNullOrEmpty($BatchCount)))
            {        
                $CheckCounter += 1
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = $Activity.Name;
                    CheckDetail = "ForEach does not have a batch count value set, should be set to service maximum (50).";
                    Severity = $Severity
                }
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}


#############################################################################################
#Check foreach activity batch size is less than the service maximum
#############################################################################################
$CheckDetail = "Activitie(s) ForEach iteration with a batch count size that is less than the service maximum."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "activity_batch_size_less_than_max"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Activity in $Activities | Where-Object {$_.type -eq "ForEach"})
    {     
        [bool]$isSequential = $false #attribute may only exist if changed, assume not present in arm template
        if((-not [string]::IsNullOrEmpty($Activity.typeProperties.isSequential)))
        {
            $isSequential = $Activity.typeProperties.isSequential
        }
        $BatchCount = $Activity.typeProperties.batchCount

        if(!$isSequential)
        {
            if($BatchCount -lt 50)
            {        
                $CheckCounter += 1
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = $Activity.Name;
                    CheckDetail = "ForEach has a batch size that is less than the service maximum (50).";
                    Severity = $Severity
                }
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check linked service using key vault
#############################################################################################
$CheckDetail = "Linked Service(s) not using Azure Key Vault to store credentials."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "linked_service_using_key_vault"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    $LinkedServiceList = New-Object System.Collections.ArrayList($null)
    ForEach ($LinkedService in $LinkedServices | Where-Object {$_.properties.type -ne "AzureKeyVault"})
    {
        $typeProperties = Get-Member -InputObject $LinkedService.properties.typeProperties -MemberType NoteProperty

        ForEach($typeProperty in $typeProperties) 
        {
            $propValue = $LinkedService.properties.typeProperties | Select-Object -ExpandProperty $typeProperty.Name
            #if($propValue.authenticationType -ne "Anonymous") {
                #handle linked services with multiple type properties
                if(([string]::IsNullOrEmpty($propValue.secretName))){
                    $LinkedServiceName = (CleanName -RawValue $LinkedService.name)
                    if(-not ($LinkedServiceList -contains $LinkedServiceName))
                    {
                        [void]$LinkedServiceList.Add($LinkedServiceName) #add linked service if secretName is missing
                    }
                }
                if(-not([string]::IsNullOrEmpty($propValue.secretName))){
                    $LinkedServiceName = (CleanName -RawValue $LinkedService.name)
                    [void]$LinkedServiceList.Remove($LinkedServiceName) #remove linked service if secretName is then found
                }
            #}
        }
    }
    $CheckCounter = $LinkedServiceList.Count
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0


    {  
        ForEach ($LinkedServiceOutput in $LinkedServiceList)
        {
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Linked Service";
                Name = $LinkedServiceOutput;
                CheckDetail = "Not using Key Vault to store credentials.";
                Severity = $Severity
            }
        }
    }
}

#############################################################################################
#Check for linked services not in use
#############################################################################################
$CheckDetail = "Linked Service(s) not used by any other resource."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "linked_service_not_in_use"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "linkedServices*"})
    {
        $Parts = $RedundantResource.Split('|')

        $CheckCounter += 1
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Linked Service";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
            Severity = $Severity
        }
    }
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check linked service descriptions
#############################################################################################
$CheckDetail = "Linked Service(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "linked_service_without_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($LinkedService in $LinkedServices)
    {
        $LinkedServiceName = (CleanName -RawValue $LinkedService.name.ToString())
        $LinkedServiceDescription = $LinkedService.properties.description
        if(([string]::IsNullOrEmpty($LinkedServiceDescription)))
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Linked Service";
                Name = $LinkedServiceName;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for linked service without annotations
#############################################################################################
$CheckDetail = "Linked Service(s) without annotations."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "linked_service_without_annotation"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Pipeline in $Pipelines)
    {
        $LinkedServiceName = (CleanName -RawValue $LinkedService.name.ToString())
        $LinkedServiceAnnotations = $Pipeline.properties.annotations.Count
        if($LinkedServiceAnnotations -le 0)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Linked Service";
                Name = $LinkedServiceName;
                CheckDetail = "Does not have any annotations.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for datasets not in use
#############################################################################################
$CheckDetail = "Dataset(s) not used by any other resource."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "dataset_not_in_use"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "datasets*"})
    {
        $Parts = $RedundantResource.Split('|')

        $CheckCounter += 1
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Dataset";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
            Severity = $Severity
        }
    }
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check for dataset without description
#############################################################################################
$CheckDetail = "Dataset(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "dataset_without_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Dataset in $Datasets)
    {
        $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
        $DatasetDescription = $Dataset.properties.description
        if(([string]::IsNullOrEmpty($DatasetDescription)))
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check dataset not in folders
#############################################################################################
$CheckDetail = "Dataset(s) not organised into folders."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "dataset_not_in_folder"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Dataset in $Datasets)
    {
        $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
        $DatasetFolder = $Dataset.properties.folder.name
        if(([string]::IsNullOrEmpty($DatasetFolder)))
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Not organised into a folder.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for datasets without annotations
#############################################################################################
$CheckDetail = "Dataset(s) without annotations."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "dataset_without_annotation"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Dataset in $Datasets)
    {
        $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
        $DatasetAnnotations = $Dataset.properties.annotations.Count
        if($DatasetAnnotations -le 0)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Does not have any annotations.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for triggers not in use
#############################################################################################
$CheckDetail = "Trigger(s) not used by any other resource."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "trigger_not_in_use"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "triggers*"})
    {
        $Parts = $RedundantResource.Split('|')

        $CheckCounter += 1
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Trigger";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
            Severity = $Severity
        }
    }
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check for trigger descriptions
#############################################################################################
$CheckDetail = "Trigger(s) without a description value."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "trigger_without_description"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Trigger in $Triggers)
    {
        $TriggerName = (CleanName -RawValue $Pipeline.name.ToString())
        $TriggerDescription = $Trigger.properties.description

        if(([string]::IsNullOrEmpty($TriggerDescription)))
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Trigger";
                Name = $TriggerName;
                CheckDetail = "Does not have a description.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for trigger without annotations
#############################################################################################
$CheckDetail = "Trigger(s) without annotations."
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "trigger_without_annotation"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Trigger in $Triggers)
    {
        $TriggerName = (CleanName -RawValue $Trigger.name.ToString())
        $TriggerAnnotations = $Trigger.properties.annotations.Count

        if($TriggerAnnotations -le 0)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Trigger";
                Name = $TriggerName;
                CheckDetail = "Does not have any annotations.";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check for SQL lookup timeouts
#############################################################################################
$CheckDetail = "Activitie(s) SQL lookup timeout set to default"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "lookup_sql_timeout"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1    
    ForEach ($Activity in $Activities | Where-Object {$_.type -eq "Lookup"})
    {     
        if(($Activity.typeProperties.source.type -eq 'AzureSqlSource')) {
            if($Activity.typeProperties.source.queryTimeout -eq '02:00:00') {
                $CheckCounter += 1
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = $Activity.Name;
                    CheckDetail = "SQL query timeout is set to default value";
                    Severity = $Severity
                }
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
#Check naming conventions for pipelines
#############################################################################################
$CheckDetail = "Naming conventions pipelines"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "naming_convention_pipeline"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Pipeline in $Pipelines)
    {
        $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
        $PipelineCheckPrefix = CheckPrefix -ObjectName $PipelineName -ObjectType "Pipeline"
        $PipelineCheckName = CheckName -ObjectName $PipelineName

        if(! $PipelineCheckPrefix.passed)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Name does not adhere to naming convention (prefix), should start with $($PipelineCheckPrefix.prefix)";
                Severity = $Severity
            }
        }

        if(! $PipelineCheckName.passed)
        {
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Name does not adhere to naming convention (characters), offending characters: $($PipelineCheckName.offendingCharacters)";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
        IssueCount = $CheckCounter; 
        CheckDetail = $CheckDetail;
        Severity = $Severity
    }
    $CheckCounter = 0
}

#############################################################################################
#Check naming conventions for activites
#############################################################################################
$CheckDetail = "Naming conventions activities"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "naming_convention_activity"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Activity in $Activities) {
        $ActivityCheckPrefix = CheckPrefix -ObjectName $Activity.Name -ObjectType $Activity.Type
        $ActivityCheckName = CheckName -ObjectName $Activity.Name

        if(! $ActivityCheckPrefix.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Activity";
                Name = $Activity.Name;
                CheckDetail = "Name does not adhere to naming convention (prefix), should start with $($ActivityCheckPrefix.prefix)";
                Severity = $Severity
            }
        }
        if(! $ActivityCheckName.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Activity";
                Name = $Activity.Name;
                CheckDetail = "Name does not adhere to naming convention (characters), offending characters: $($ActivityCheckName.offendingCharacters)";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
# Check naming conventions for datasets
#############################################################################################
$CheckDetail = "Naming conventions datasets"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "naming_convention_dataset"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($Dataset in $Datasets)
    {
        $DatasetName = (CleanName -RawValue $Dataset.name.ToString())

        $CheckDatasetName = CheckName -ObjectName $DatasetName
        $CheckDatasetPrefix = CheckPrefix -ObjectName $DatasetName -ObjectType "Dataset"

        if(! $CheckDatasetName.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Name does not adhere to naming convention (characters), offending characters: $($CheckDatasetName.offendingCharacters)";
                Severity = $Severity
            }
        }

        if(! $CheckDatasetPrefix.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Name does not adhere to naming convention (prefix), should start with $($CheckDatasetPrefix.prefix)";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}
#############################################################################################
# Check naming conventions for SQL scripts
#############################################################################################
$CheckDetail = "Naming conventions sqlscripts"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "naming_convention_sqlscripts"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($SQLScript in $SQLScripts)
    {
        $SQLScriptName = (CleanName -RawValue $SQLScript.name.ToString())
        $CheckSQLScriptName = CheckName -ObjectName $SQLScriptName
        $CheckSQLScriptPrefix = CheckPrefix -ObjectName $SQLScriptName -ObjectType "SqlQuery"

        if(! $CheckSQLScriptName.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "SqlScript";
                Name = $SQLScriptName;
                CheckDetail = "Name does not adhere to naming convention (characters), offending characters: $($CheckSQLScriptName.offendingCharacters)";
                Severity = $Severity
            }
        }

        if(! $CheckSQLScriptPrefix.passed)
        {        
            $CheckCounter += 1
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "SqlScript";
                Name = $SQLScriptName;
                CheckDetail = "Name does not adhere to naming convention (prefix), should start with $($CheckSQLScriptPrefix.prefix)";
                Severity = $Severity
            }
        }
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
# Check naming conventions for Linked services
#############################################################################################
$CheckDetail = "Naming conventions linked service"
$Severity = ($checkDetails | Where-Object { $_.checkName -eq "naming_convention_linked_service"} | Select-Object ).severity
if($Severity -ne "ignore") {
	$CheckNumber += 1
    ForEach ($LinkedService in $LinkedServices)
    {
        $LinkedServiceScriptName = (CleanName -RawValue $LinkedService.name.ToString())
        $CheckLinkedServiceScriptName = CheckName -ObjectName $LinkedServiceScriptName
        $CheckLinkedServiceScriptPrefix = CheckPrefix -ObjectName $LinkedServiceScriptName -ObjectType "LinkedService"
        if(!($LinkedServiceScriptName -contains "WorkspaceDefaultStorage" -or $LinkedServiceScriptName -contains "WorkspaceDefaultSqlServer")){
            if(! $CheckLinkedServiceScriptName.passed)
            {        
                $CheckCounter += 1
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "LinkedService";
                    Name = $SQLScriptName;
                    CheckDetail = "Name does not adhere to naming convention (characters), offending characters: $($CheckLinkedServiceScriptName.offendingCharacters)";
                    Severity = $Severity
                }
            }

            if(! $CheckLinkedServiceScriptPrefix.passed)
            {        
                $CheckCounter += 1
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "LinkedService";
                    Name = $SQLScriptName;
                    CheckDetail = "Name does not adhere to naming convention (prefix), should start with $($CheckLinkedServiceScriptPrefix.prefix)";
                    Severity = $Severity
                }
            }
        }
        
    }
    $SummaryTable += [PSCustomObject]@{
            IssueCount = $CheckCounter; 
            CheckDetail = $CheckDetail;
            Severity = $Severity
        }
    $CheckCounter = 0
}

#############################################################################################
Write-Host ""
Write-Host $Hr

   
Write-Host ""
Write-Host "Results Summary:"
Write-Host ""
Write-Host "Checks ran against template:" $CheckNumber
Write-Host "Checks with issues found:" ($SummaryTable | Where-Object {$_.IssueCount -ne 0}).Count.ToString()
Write-Host "Total issue count:" ($SummaryTable | Measure-Object -Property IssueCount -Sum).Sum

$SummaryTable = $SummaryTable | Sort-Object {$importance.Indexof($_.Severity)}

$SummaryTable | Where-Object {$_.IssueCount -ne 0} | Format-Table @{
    Label = "Issue Count";Expression = {$_.IssueCount}; Alignment="Center"}, @{
    Label = "Check Details";Expression = {$_.CheckDetail}}, @{
    Label = "Severity";
    Expression =
    {
        switch ($_.Severity)
        {
            #https://docs.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences#span-idtextformattingspanspan-idtextformattingspanspan-idtextformattingspantext-formatting
            'ignore' {$color = $severities[0].color; break }
            'info' {$color = $severities[1].color; break }
            'low' {$color = $severities[2].color; break }
            'medium' {$color = $severities[3].color; break }
            'high' {$color = $severities[4].color; break }
            'critical' {$color = $severities[5].color; break }
            default {$color = "0"}
        }
        $e = [char]27
        "$e[${color}m$($_.Severity)${e}[0m"
    }
}

Write-Host $Hr

Write-Host ""
Write-Host "Results Details:"
#Sort verbose table according to Severity
$VerboseDetailTable = $VerboseDetailTable | Sort-Object {$importance.Indexof($_.Severity)}, {($_.Component)}, {($_.CheckDetail)} 

$tab = [char]9
ForEach ($Detail in $VerboseDetailTable) {
    if(($Detail.Severity -eq "High") -or ($Detail.Severity -eq "Medium")) {
        Write-Host "##vso[task.LogIssue type=error;]" $Detail.Component $tab $Detail.CheckDetail $tab $Detail.Name
    } elseif($Detail.Severity -eq "Low") {
        Write-Host "##vso[task.LogIssue type=warning;]" $Detail.Component $tab $Detail.CheckDetail $tab $Detail.Name
    } else {
        Write-Host $Detail.Component $tab $Detail.CheckDetail $tab $Detail.Name
	}
}

if(($VerboseDetailTable.Severity -contains "High") -or ($VerboseDetailTable.Severity -contains "Medium")) {
    Write-Host "##vso[task.complete result=Failed;]DONE"
} elseif ($VerboseDetailTable.Severity -contains "Low") {
    Write-Host "##vso[task.complete result=SucceededWithIssues;]DONE"
} else {
    Write-Host "##vso[task.complete result=Succeeded;]DONE"
}
