##Retrieve all arguments
[CmdletBinding()]
param($ARMTemplateFilePath)#,[bool]$SummaryOutput = $true,[bool]$VerboseOutput = $false,[bool]$debug = $false)

#############################################################################################
# Helper array for check of naming conventions
#############################################################################################
$PrefixTable = @()
$PrefixTable += [PSCustomObject]@{ObjectType = "Pipeline";                 ObjectPrefix = "Pl";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Dataset";                  ObjectPrefix = "Ds";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Lookup";                   ObjectPrefix = "Lkp";}
$PrefixTable += [PSCustomObject]@{ObjectType = "GetMetadata";              ObjectPrefix = "Gm";}
$PrefixTable += [PSCustomObject]@{ObjectType = "SetVariable";              ObjectPrefix = "Set";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AppendVariable";           ObjectPrefix = "ApV";}
$PrefixTable += [PSCustomObject]@{ObjectType = "ForEach";                  ObjectPrefix = "Fe";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Filter";                   ObjectPrefix = "Flt";}
$PrefixTable += [PSCustomObject]@{ObjectType = "SqlServerStoredProcedure"; ObjectPrefix = "Sp";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Copy";                     ObjectPrefix = "Cp";}
$PrefixTable += [PSCustomObject]@{ObjectType = "ExecuteDataFlow";          ObjectPrefix = "Df";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AzureDataExplorerCommand"; ObjectPrefix = "Ade";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AzureFunctionActivity";    ObjectPrefix = "Af";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Custom";                   ObjectPrefix = "Cst";}
$PrefixTable += [PSCustomObject]@{ObjectType = "DatabricksNotebook";       ObjectPrefix = "Nb";}
$PrefixTable += [PSCustomObject]@{ObjectType = "DatabricksSparkJar";       ObjectPrefix = "Jar";}
$PrefixTable += [PSCustomObject]@{ObjectType = "DatabricksSparkPython";    ObjectPrefix = "Py";}
$PrefixTable += [PSCustomObject]@{ObjectType = "DataLakeAnalyticsU-SQL";   ObjectPrefix = "Us";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Delete";                   ObjectPrefix = "Del";}
$PrefixTable += [PSCustomObject]@{ObjectType = "ExecutePipeline";          ObjectPrefix = "Exp";}
$PrefixTable += [PSCustomObject]@{ObjectType = "ExecuteSSISPackage";       ObjectPrefix = "Exs";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Validation";               ObjectPrefix = "Val";}
$PrefixTable += [PSCustomObject]@{ObjectType = "WebActivity";              ObjectPrefix = "Web";}
$PrefixTable += [PSCustomObject]@{ObjectType = "WebHook";                  ObjectPrefix = "Whk";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Wait";                     ObjectPrefix = "Wt";}
$PrefixTable += [PSCustomObject]@{ObjectType = "HDInsightHive";            ObjectPrefix = "Hv";}
$PrefixTable += [PSCustomObject]@{ObjectType = "HDInsightMapReduce";       ObjectPrefix = "Mr";}
$PrefixTable += [PSCustomObject]@{ObjectType = "HDInsightPig";             ObjectPrefix = "Pig";}
$PrefixTable += [PSCustomObject]@{ObjectType = "HDInsightSpark";           ObjectPrefix = "Spk";}
$PrefixTable += [PSCustomObject]@{ObjectType = "HDInsightStreaming";       ObjectPrefix = "Str";}
$PrefixTable += [PSCustomObject]@{ObjectType = "IfCondition";              ObjectPrefix = "If";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Switch";                   ObjectPrefix = "Sw";}
$PrefixTable += [PSCustomObject]@{ObjectType = "Until";                    ObjectPrefix = "Unt";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AzureMLBatchExecution";    ObjectPrefix = "Mlb";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AzureMLUpdateResource";    ObjectPrefix = "Mlu";}
$PrefixTable += [PSCustomObject]@{ObjectType = "AzureMLExecutePipeline";   ObjectPrefix = "Mle";}
$PrefixTable += [PSCustomObject]@{ObjectType = "ExecuteWranglingDataflow"; ObjectPrefix = "Pq";}

#############################################################################################
# Helper functions for check of naming conventions
#############################################################################################
function CheckPrefix {
    param (
        [parameter(Mandatory = $true)] [String] $ObjectName,
        [parameter(Mandatory = $true)] [String] $ObjectType
    )
    $PfxObject = ($PrefixTable | Where-Object -Property ObjectType -eq $ObjectType).ObjectPrefix
    $PfxLength = $PfxObject.Length

    $Check = ($ObjectName.Substring(0, $PfxLength) -eq $PfxObject)
    return $Check
}

function CheckName {
    param (
        [parameter(Mandatory = $true)] [String] $ObjectName
    )

    $Check = ($ObjectName -match '^[a-zA-Z0-9]*$')
    return $Check
}

#############################################################################################
if(-not (Test-Path -Path $ARMTemplateFilePath))
{
    Write-Host "##vso[task.LogIssue type=error;]ARM template file not found. Please check the path provided."
    exit 1
}

$Hr = "-------------------------------------------------------------------------------------------------------------------"
Write-Host ""
Write-Host $Hr
Write-Host "Running checks for Data Factory ARM template:"
Write-Host ""
$ARMTemplateFilePath
Write-Host ""

#Parse template into ADF resource parts
$ADF = Get-Content $ARMTemplateFilePath | ConvertFrom-Json
$LinkedServices = $ADF.resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/linkedServices"}
$Datasets = $ADF.resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/datasets"}
$Pipelines = $ADF.resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/pipelines"}
#$Activities = $Pipelines.properties.activities #regardless of pipeline
$DataFlows = $ADF.resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/dataflows"}
$Triggers = $ADF.resources | Where-Object {$_.type -eq "Microsoft.DataFactory/factories/triggers"}

#Output variables
$CheckNumber = 0
$CheckDetail = ""
$Severity = "" #Info, Low, Medium, High
$CheckCounter = 0
$SummaryTable = @()
$VerboseDetailTable = @()

#String helper functions
function CleanName {
    param (
        [parameter(Mandatory = $true)] [String] $RawValue
    )
    $CleanName = $RawValue.substring($RawValue.IndexOf("/")+1, $RawValue.LastIndexOf("'") - $RawValue.IndexOf("/")-1)
    return $CleanName
}

function CleanType {
    param (
        [parameter(Mandatory = $true)] [String] $RawValue
    )
    $CleanName = $RawValue.substring($RawValue.LastIndexOf("/")+1, $RawValue.Length - $RawValue.LastIndexOf("/")-1)
    return $CleanName
}

#Importance level sorting
$importance = 'High', 'Medium', 'Low', 'Info'
$VerboseOutput = $true

#############################################################################################
#Review resource dependants
#############################################################################################
$ResourcesList = New-Object System.Collections.ArrayList($null)
$DependantsList = New-Object System.Collections.ArrayList($null)

#Get resources
ForEach($Resource in $ADF.resources)
{
    $ResourceName = CleanName -RawValue $Resource.name
    $ResourceType = CleanType -RawValue $Resource.type
    $CompleteResource =   $ResourceType + "|" + $ResourceName
    
    if(-not ($ResourcesList -contains $CompleteResource))
    {
        [void]$ResourcesList.Add($CompleteResource)
    }
}

#Get dependants
ForEach($Resource in $ADF.resources)# | Where-Object {$_.type -ne "Microsoft.DataFactory/factories/triggers"})
{
    if($Resource.dependsOn.Count -eq 1)
    {
        $DependantName = CleanName -RawValue $Resource.dependsOn[0].ToString()
        $CompleteDependant = $DependantName.Replace('/','|')

        if(-not ($DependantsList -contains $CompleteDependant))
        {
            [void]$DependantsList.Add($CompleteDependant)
        }
    }
    else
    {
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

#Get trigger dependants
ForEach($Resource in $Triggers)
{
    
    $ResourceName = CleanName -RawValue $Resource.name
    $ResourceType = CleanType -RawValue $Resource.type
    $CompleteResource =   $ResourceType + "|" + $ResourceName

    if($Resource.dependsOn.count -ge 1)
    {
        if(-not ($DependantsList -contains $CompleteResource))
        {
            [void]$DependantsList.Add($CompleteResource)
        }
    }
}

#Establish simple redundancy to use later
$RedundantResources = $ResourcesList | Where-Object {$DependantsList -notcontains $_}

#############################################################################################
#Check for pipeline without triggers
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Pipeline(s) without any triggers attached. Directly or indirectly."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"

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


#############################################################################################
#Check pipeline with an impossible execution chain.
#############################################################################################
# $CheckNumber += 1
# $CheckDetail = "Pipeline(s) with an impossible AND/OR activity execution chain."
# if($debug) {Write-Host "Running check... " $CheckDetail}
# $Severity = "High"
# ForEach($Pipeline in $Pipelines)
# {
#     $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
#     $ActivityFailureDependencies = New-Object System.Collections.ArrayList($null)
#     $ActivitySuccessDependencies = New-Object System.Collections.ArrayList($null)

#     #get upstream failure dependants
#     ForEach($Activity in $Pipeline.properties.activities)
#     {
#         if($Activity.dependsOn.Count -gt 1)
#         {
#             ForEach($UpStreamActivity in $Activity.dependsOn)
#             {
#                 if(($UpStreamActivity.dependencyConditions.Contains('Failed')) -or ($UpStreamActivity.dependencyConditions.Contains('Skipped')))
#                 {  
#                     if(-not ($ActivityFailureDependencies -contains $UpStreamActivity.activity))
#                     {
#                         [void]$ActivityFailureDependencies.Add($UpStreamActivity.activity)
#                     }
#                 }
#             }
#         }
#     }

#     #get downstream success dependants
#     ForEach($ActivityDependant in $ActivityFailureDependencies)
#     {
#         ForEach($Activity in $Pipeline.properties.activities | Where-Object {$_.name -eq $ActivityDependant})
#         {
#             if($Activity.dependsOn.Count -ge 1)
#             {
#                 ForEach($DownStreamActivity in $Activity.dependsOn)
#                 {
#                     if($DownStreamActivity.dependencyConditions.Contains('Succeeded'))
#                     {                  
#                         if(-not ($ActivitySuccessDependencies -contains $DownStreamActivity.activity))
#                         {
#                             [void]$ActivitySuccessDependencies.Add($DownStreamActivity.activity)
#                         }
#                     }
#                 }
#             }
#         }
#     }
    
#     #compare dependants - do they exist in both lists?
#     $Problems = $ActivityFailureDependencies | Where-Object {$ActivitySuccessDependencies -contains $_}
#     if($Problems.Count -gt 0)
#     {
#         $CheckCounter += 1
#         if($VerboseOutput -or ($Severity -eq "High"))
#         {  
#             $VerboseDetailTable += [PSCustomObject]@{
#                 Component = "Pipeline";
#                 Name = $PipelineName;
#                 CheckDetail = "Has an impossible AND/OR activity execution chain.";
#                 Severity = $Severity
#             }
#         }
#     }
# }
# $SummaryTable += [PSCustomObject]@{
#     IssueCount = $CheckCounter; 
#     CheckDetail = $CheckDetail;
#     Severity = $Severity
# }
# $CheckCounter = 0

#############################################################################################
#Check for pipeline descriptions
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Pipeline(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Pipeline in $Pipelines)
{
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    $PipelineDescription = $Pipeline.properties.description

    if(([string]::IsNullOrEmpty($PipelineDescription)))
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Does not have a description.";
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

#############################################################################################
#Check for pipelines not in folders
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Pipeline(s) not organised into folders."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Pipeline in $Pipelines)
{
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    $PipelineFolder = $Pipeline.properties.folder.name
    if(([string]::IsNullOrEmpty($PipelineFolder)))
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Not organised into a folder.";
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

#############################################################################################
#Check for pipelines without annotations
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Pipeline(s) without annotations."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"
ForEach ($Pipeline in $Pipelines)
{
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    $PipelineAnnotations = $Pipeline.properties.annotations.Count
    if($PipelineAnnotations -le 0)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Does not have any annotations.";
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

#############################################################################################
#Check for data flow descriptions
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Data Flow(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"

ForEach ($DataFlow in $DataFlows)
{
    $DataFlowName = (CleanName -RawValue $DataFlow.name.ToString())
    $DataFlowDescription = $DataFlow.properties.description

    if(([string]::IsNullOrEmpty($DataFlowDescription)))
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Data Flow";
                Name = $DataFlowName;
                CheckDetail = "Does not have a description.";
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

#############################################################################################
#Check activity timeout values
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Activitie(s) with timeout values still set to the service default value of 7 days."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "High"

ForEach ($Pipeline in $Pipelines){
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    ForEach ($Activity in $Pipeline.properties.activities) {
        $timeout = $Activity.policy.timeout
        if(-not ([string]::IsNullOrEmpty($timeout)))
        {        
            if($timeout -eq "7.00:00:00")
            {
                $CheckCounter += 1
                if($VerboseOutput -or ($Severity -eq "High"))
                {            
                    $VerboseDetailTable += [PSCustomObject]@{
                        Component = "Activity";
                        Name = $Activity.Name + " in " + $PipelineName;
                        CheckDetail = "Timeout policy still set to the service default value of 7 days.";
                        Severity = $Severity
                    }
                }
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

#############################################################################################
#Check activity descriptions
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Activitie(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Pipeline in $Pipelines){
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    ForEach ($Activity in $Pipeline.properties.activities) 
    {
        $ActivityDescription = $Activity.description
        if(([string]::IsNullOrEmpty($ActivityDescription)))
        {        
            $CheckCounter += 1
            if($VerboseOutput -or ($Severity -eq "High"))
            {            
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = $Activity.Name + " in " + $PipelineName;;
                    CheckDetail = "Does not have a description.";
                    Severity = $Severity
                }
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

#############################################################################################
#Check foreach activity batch size unset
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Activitie(s) ForEach iteration without a batch count value set."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "High"
ForEach ($Pipeline in $Pipelines){
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    ForEach ($Activity in $Pipeline.properties.activities | Where-Object {$_.type -eq "ForEach"})
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
                if($VerboseOutput -or ($Severity -eq "High"))
                {            
                    $VerboseDetailTable += [PSCustomObject]@{
                        Component = "Activity";
                        Name = $Activity.Name + " in " + $PipelineName;
                        CheckDetail = "ForEach does not have a batch count value set.";
                        Severity = $Severity
                    }
                }
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


#############################################################################################
#Check foreach activity batch size is less than the service maximum
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Activitie(s) ForEach iteration with a batch count size that is less than the service maximum."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Medium"
ForEach ($Pipeline in $Pipelines){
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    ForEach ($Activity in $Pipeline.properties.activities | Where-Object {$_.type -eq "ForEach"})
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
                if($VerboseOutput -or ($Severity -eq "High"))
                {            
                    $VerboseDetailTable += [PSCustomObject]@{
                        Component = "Activity";
                        Name = $Activity.Name + " in " + $PipelineName;;
                        CheckDetail = "ForEach has a batch size that is less than the service maximum.";
                        Severity = $Severity
                    }
                }
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

#############################################################################################
#Check linked service using key vault
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Linked Service(s) not using Azure Key Vault to store credentials."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"

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

if($VerboseOutput -or ($Severity -eq "High"))
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

#############################################################################################
#Check for linked services not in use
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Linked Service(s) not used by any other resource."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Medium"
ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "linkedServices*"})
{
    $Parts = $RedundantResource.Split('|')

    $CheckCounter += 1
    if($VerboseOutput -or ($Severity -eq "High"))
    {  
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Linked Service";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
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

#############################################################################################
#Check linked service descriptions
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Linked Service(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($LinkedService in $LinkedServices)
{
    $LinkedServiceName = (CleanName -RawValue $LinkedService.name.ToString())
    $LinkedServiceDescription = $LinkedService.properties.description
    if(([string]::IsNullOrEmpty($LinkedServiceDescription)))
    {        
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {            
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Linked Service";
                Name = $LinkedServiceName;
                CheckDetail = "Does not have a description.";
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

#############################################################################################
#Check for linked service without annotations
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Linked Service(s) without annotations."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"
ForEach ($Pipeline in $Pipelines)
{
    $LinkedServiceName = (CleanName -RawValue $LinkedService.name.ToString())
    $LinkedServiceAnnotations = $Pipeline.properties.annotations.Count
    if($LinkedServiceAnnotations -le 0)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Linked Service";
                Name = $LinkedServiceName;
                CheckDetail = "Does not have any annotations.";
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

#############################################################################################
#Check for datasets not in use
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Dataset(s) not used by any other resource."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Medium"
ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "datasets*"})
{
    $Parts = $RedundantResource.Split('|')

    $CheckCounter += 1
    if($VerboseOutput -or ($Severity -eq "High"))
    {  
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Dataset";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
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

#############################################################################################
#Check for dataset without description
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Dataset(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Dataset in $Datasets)
{
    $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
    $DatasetDescription = $Dataset.properties.description
    if(([string]::IsNullOrEmpty($DatasetDescription)))
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Does not have a description.";
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

#############################################################################################
#Check dataset not in folders
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Dataset(s) not organised into folders."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Dataset in $Datasets)
{
    $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
    $DatasetFolder = $Dataset.properties.folder.name
    if(([string]::IsNullOrEmpty($DatasetFolder)))
    {        
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {            
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Not organised into a folder.";
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

#############################################################################################
#Check for datasets without annotations
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Dataset(s) without annotations."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"
ForEach ($Dataset in $Datasets)
{
    $DatasetName = (CleanName -RawValue $Dataset.name.ToString())
    $DatasetAnnotations = $Dataset.properties.annotations.Count
    if($DatasetAnnotations -le 0)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Does not have any annotations.";
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

#############################################################################################
#Check for triggers not in use
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Trigger(s) not used by any other resource."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Medium"
ForEach($RedundantResource in $RedundantResources | Where-Object {$_ -like "triggers*"})
{
    $Parts = $RedundantResource.Split('|')

    $CheckCounter += 1
    if($VerboseOutput -or ($Severity -eq "High"))
    {  
        $VerboseDetailTable += [PSCustomObject]@{
            Component = "Trigger";
            Name = $Parts[1];
            CheckDetail = "Not used by any other resource.";
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

#############################################################################################
#Check for trigger descriptions
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Trigger(s) without a description value."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Trigger in $Triggers)
{
    $TriggerName = (CleanName -RawValue $Pipeline.name.ToString())
    $TriggerDescription = $Trigger.properties.description

    if(([string]::IsNullOrEmpty($TriggerDescription)))
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Trigger";
                Name = $TriggerName;
                CheckDetail = "Does not have a description.";
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

#############################################################################################
#Check for trigger without annotations
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Trigger(s) without annotations."
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Low"
ForEach ($Trigger in $Triggers)
{
    $TriggerName = (CleanName -RawValue $Trigger.name.ToString())
    $TriggerAnnotations = $Trigger.properties.annotations.Count

    if($TriggerAnnotations -le 0)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Trigger";
                Name = $TriggerName;
                CheckDetail = "Does not have any annotations.";
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

#############################################################################################
#Check for SQL lookup timeouts
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Activitie(s) SQL lookup timeout set to default"
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "High"
ForEach ($Pipeline in $Pipelines){
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    ForEach ($Activity in $Pipeline.properties.activities | Where-Object {$_.type -eq "Lookup"})
    {     
        if(($Activity.typeProperties.source.type -eq 'AzureSqlSource')) {
            if($Activity.typeProperties.source.queryTimeout -eq '02:00:00') {
                $CheckCounter += 1
                if($VerboseOutput -or ($Severity -eq "High"))
                {            
                    $VerboseDetailTable += [PSCustomObject]@{
                        Component = "Activity";
                        Name = $Activity.Name + " in " + $PipelineName;;
                        CheckDetail = "SQL query timeout is set to default value";
                        Severity = $Severity
                    }
                }
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

#############################################################################################
#Check naming conventions for pipelines and activites
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Naming conventions pipelines and activities"
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"

ForEach ($Pipeline in $Pipelines)
{
    $PipelineName = (CleanName -RawValue $Pipeline.name.ToString())
    $PipelineCheckPrefix = CheckPrefix -ObjectName $PipelineName -ObjectType "Pipeline"
    $PipelineCheckName = CheckName -ObjectName $PipelineName

    if(! $PipelineCheckPrefix)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Name does not adhere to naming convention (prefix)";
                Severity = $Severity
            }
        }
    }

    if(! $PipelineCheckName)
    {
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {  
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Pipeline";
                Name = $PipelineName;
                CheckDetail = "Name does not adhere to naming convention (characters)";
                Severity = $Severity
            }
        }
    }

    ForEach ($Activity in $Pipeline.properties.activities) {
        $ActivityCheckPrefix = CheckPrefix -ObjectName $Activity.Name -ObjectType $Activity.Type
        $ActivityCheckName = CheckName -ObjectName $Activity.Name

        if(! $ActivityCheckPrefix)
        {        
            $CheckCounter += 1
            if($VerboseOutput -or ($Severity -eq "High"))
            {            
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = "'" + $Activity.Name + "' in " + $PipelineName;
                    CheckDetail = "Name does not adhere to naming convention (prefix)";
                    Severity = $Severity
                }
            }
        }
        if(! $ActivityCheckName)
        {        
            $CheckCounter += 1
            if($VerboseOutput -or ($Severity -eq "High"))
            {            
                $VerboseDetailTable += [PSCustomObject]@{
                    Component = "Activity";
                    Name = "'" + $Activity.Name + "' in " + $PipelineName;
                    CheckDetail = "Name does not adhere to naming convention (characters)";
                    Severity = $Severity
                }
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

#############################################################################################
# Check naming conventions for datasets
#############################################################################################
$CheckNumber += 1
$CheckDetail = "Naming conventions datasets"
if($debug) {Write-Host "Running check... " $CheckDetail}
$Severity = "Info"
ForEach ($Dataset in $Datasets)
{
    $DatasetName = (CleanName -RawValue $Dataset.name.ToString())

    $CheckDatasetName = CheckName -ObjectName $DatasetName
    $CheckDatasetPrefix = CheckPrefix -ObjectName $DatasetName -ObjectType "Dataset"

    if(! $CheckDatasetName)
    {        
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {            
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Name does not adhere to naming convention (characters)";
                Severity = $Severity
            }
        }
    }

    if(! $CheckDatasetPrefix)
    {        
        $CheckCounter += 1
        if($VerboseOutput -or ($Severity -eq "High"))
        {            
            $VerboseDetailTable += [PSCustomObject]@{
                Component = "Dataset";
                Name = $DatasetName;
                CheckDetail = "Name does not adhere to naming convention (prefix)";
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
            'Low' {$color = "92"; break }
            'Medium' {$color = '93'; break }
            'High' {$color = "31"; break }
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
