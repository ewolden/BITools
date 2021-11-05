# Azure Data Factory/Azure Synapse Best Practice Analyzer
The best practice analyzer is meant as a tool to help keep code consistent and following a list of best practices. By changing the configuration, you can enable/disable tests, or adjust the checks to adhere to the naming conventions used in your project.

## Contents
[How to add as a submodule to a repository](#how-to-add-as-a-submodule-to-a-repository)  
[How to set up in Azure DevOps](#how-to-set-up-in-azure-devops)  
[Configuring the checks](#configuring-the-checks)  
[Credits](#credits)  

## How to add as a submodule to a repository 
Ref: [Git Tools- Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

First add the submodule:

`git submodule add https://github.com/ewolden/BITools`

Create a commit with the submodule:

`git commit -am 'Added BITools module'`

Finally, push changes to master:

`git push origin master`

To update the submodule at a later time, use:

`git submodule update --remote BITools`


## How to set up in Azure DevOps
Create a new build pipeline that uses yaml code.

### Pointing to ARMTemplate
This way of setting up the BPA relies on ADF or Synapse code that is compiled to an ARMTemplate (such as in the publish branch, default *adf_publish* or *workspace_publish* depending if this is ADF or synapse.)
```
# Run Best Practice checks
- task: PowerShell@2
  inputs:
    filePath: '$(Build.Repository.LocalPath)/BITools/bpacheck.ps1'
    arguments: '$(Build.Repository.LocalPath)/resourceName/ARMTemplateForFactory.json'
    errorActionPreference: 'stop'
  displayName: 'Run Best Practice Analyser'
```

Where *`resourceName`*  is the name of the resurouce that published this.

### Pointing to ADF/Synapse save folder
To point to a folder with precompiled json files (such as in the master branch.)

```
# Run Best Practice checks
- task: PowerShell@2
  inputs:
    filePath: '$(Build.Repository.LocalPath)/BITools/bpacheck.ps1'
    arguments: '$(Build.Repository.LocalPath)/resourceFolder'
    errorActionPreference: 'stop'
  displayName: 'Run Best Practice Analyser'
```

This assumes files are placed in a folder in the repository called *`resourceFolder`*.

## Configuring the checks
The file defaultconfig.json contains definitions of severity levels, which checks to run and rules for naming conventions.  
We recommend that you copy this to a new file, and modifies the copy to per your requirements. OBS! You will need to set up the path to your config file as a second parameter in the yaml definiton. This can be done by adding the path as part of the arguments in the yaml definition, like this:
```
# Run Best Practice checks
- task: PowerShell@2
  inputs:
    filePath: '$(Build.Repository.LocalPath)/BITools/bpacheck.ps1'
    arguments: '$(Build.Repository.LocalPath)/resourceName/ARMTemplateForFactory.json $(Build.Repository.LocalPath)/BITools/MySuperDuperConfig.json'
    errorActionPreference: 'stop'
  displayName: 'Run Best Practice Analyser'
```


The config consists of 4 parts:
### Severity
This is the definition of the severity levels. You can change the sort order (ie. the value), and the colors used. Please refer to 
https://docs.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences#span-idtextformattingspanspan-idtextformattingspanspan-idtextformattingspantext-formatting for more information.  

### CheckDetails
Has the definitions of each check and their severity.  

Severity level "ignore" disables the check.  
"info" outputs the results in the build pipeline log, but will not trigger any warnings or errors.  
"warning" outputs the results in the build pipeline log, and triggers the warning state of the pipeline.  
"error" outputs the results in the build pipeline log, and triggers an error in the pipeline.  

### NamingConvention
Should possibly been renamed to prefixNamingConvention, as this defines the prefixes we want to use for the different objects. If you want to use other prefixes, you can change them here. The CheckDetails section enables/disables checks for the main types of objects, but should there be a specific object you don't want to check, you can change the prefix to "".

### CharsNamingConvention
Defines which characters are allowed to use in the naming of objects. The string is used in a regex expression, so there are some limitations to the format. The default is any uppercase or lowercase letters, number and underscore. If you want to allow space in names, change the string to "a-zA-Z0-9_ " (ie. add a space after the underscore).

## Credits
Based on https://mrpaulandrew.com/2020/11/09/best-practices-for-implementing-azure-data-factory-auto-checker-script-v0-1/
