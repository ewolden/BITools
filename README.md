# Azure Data Factory/Azure Synapse Best Practice Analyzer
The best practice analyzer is meant as a tool to help keep code consistent and following a list of best practices.


## How to add as a submodule to a repository [Git Tools- Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

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

#### Credits
Based on https://mrpaulandrew.com/2020/11/09/best-practices-for-implementing-azure-data-factory-auto-checker-script-v0-1/
