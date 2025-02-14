﻿#======================================================================================================================#
#                                                                                                                      #
#  AzureSynapseScriptsAndAccelerators - PowerShell and T-SQL Utilities                                                 #
#                                                                                                                      #
#  This utility was developed to aid SMP/MPP migrations to Azure Synapse Migration Practitioners.                      #
#  It is not an officially supported Microsoft application or tool.                                                    #
#                                                                                                                      #
#  The utility and any script outputs are provided on "AS IS" basis and                                                #
#  there are no warranties, express or implied, including, but not limited to implied warranties of merchantability    #
#  or fitness for a particular purpose.                                                                                #
#                                                                                                                      #                    
#  The utility is therefore not guaranteed to generate perfect code or output. The output needs carefully reviewed.    #
#                                                                                                                      #
#                                       USE AT YOUR OWN RISK.                                                          #
#                                                                                                                      #
#======================================================================================================================#
#
# =================================================================================================================================================
# Description:
#       Use this to map databases/schemas in DDL scripts extracted from SQL Server. 
#       Parameters driven configuration files are the input of this powershell scripts 
# =================================================================================================================================================
# =================================================================================================================================================
# 
# Authors: Andrey Mirskiy
# Tested with Azure Synaspe Analytics and SQL Server 2017 
# 
# Use this to set Powershell permissions (examples)
# Set-ExecutionPolicy Unrestricted -Scope CurrentUser 
# Unblock-File -Path .\MapDatabasesAndSchemas.ps1


#Requires -Version 5.1
#Requires -Modules SqlServer


##########################################################################################################

Function Get-AbsolutePath
{
    [CmdletBinding()] 
    param( 
        [Parameter(Position=0, Mandatory=$true)] [string]$Path
    ) 

    if ([System.IO.Path]::IsPathRooted($Path) -eq $false) {
        return [IO.Path]::GetFullPath( (Join-Path -Path $PSScriptRoot -ChildPath $Path) )
    } else {
        return $Path
    }
}

##########################################################################################################

function AddMissingSchemas($query, $defaultSchema)
{
    # \s - single whitespace
    # [\s]* - any number of whitespace
    # [\s]+ - at least one whitespace
    # . - any character
    # [^\s] - anything except for whitespace
    # | - logical OR
    # ^ - start of the string / file

    $patterns = @()

    # Object name should be found in capture group #4 !!!

    # Object name without []
    $patterns += "(^|[\s]+)(FROM)([\s]+)([^'\s\.#\(\)\-\[\]]+?)(\)|[\s]+|[\s]*\r?$)"
    $patterns += "(^|[\s]+)(JOIN|EXEC|EXECUTE)([\s]+)([^'\s\.#\(\)\-\[\]]+?)([\s]+|[\s]*\r?$)"
    #????$patterns += "(?!\-\-)[.]*(^|[\s]+)(FROM|JOIN|EXEC|EXECUTE)([\s]+)([^'\s\.#\(\)\-\[\]]+?)([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(UPDATE)([\s]+)([^'\s\.#\(\)\-\[\]]+?)([\s]+)SET([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(DELETE)([\s]+)(?!FROM)([^'\s\.#\(\)\-\[\]]+?)([\s]+|[\s]*\r?$)"                         # DELETE FROM is processed as FROM pattern
    $patterns += "(^[\s]*)(INSERT[\s]+INTO)([\s]+)([^'\s\.#\(\)\-\[\]]+?)(\(|[\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(INSERT)([\s]+)(?!INTO)([^'\s\.#\(\)\-\[\]]+?)(\(|[\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(UPDATE[\s]+STATISTICS)([\s]+)([^'\s\.#\(\)\-\[\]]+?)([\s]+|[\s]*\r?$)"                  # exclude UPDATE STATISTICS '...' (dynamic SQL)
    $patterns += "(^[\s]*)(RENAME[\s]+OBJECT)([\s]+)([^'\s\.#\(\)\-\[\]]+?)([\s]+|[\s]*\r?$)"          
    $patterns += "(^.*)(OBJECT_ID)([\s]*\(')([^'\.#\(\)]+?)('\))"
    # Object name with []
    $patterns += "(^|[\s]+)(FROM)([\s]+)(\[[^'\.#\(\)]+?\])(\)|[\s]+|[\s]*\r?$)"
    $patterns += "(^|[\s]+)(JOIN|EXEC|EXECUTE)([\s]+)(\[[^'\.#\(\)]+?\])([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(UPDATE)([\s]+)(\[[^'\.#\(\)]+?\])([\s]+)SET([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(DELETE)([\s]+)(?!FROM)(\[[^'\.#\(\)]+?\])([\s]+|[\s]*\r?$)"                             # DELETE FROM is processed as FROM pattern
    $patterns += "(^[\s]*)(INSERT[\s]+INTO)([\s]+)(\[[^'\.#\(\)]+?\])(\(|[\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(INSERT)([\s]+)(?!INTO)(\[[^'\.#\(\)]+?\])(\(|[\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(UDPATE[\s]+STATISTICS)([\s]+)(\[[^'\.#\(\)]+?\])([\s]+|[\s]*\r?$)"                      # exclude UPDATE STATISTICS '...' (dynamic SQL)
    $patterns += "(^[\s]*)(RENAME[\s]+OBJECT)([\s]+)(\[[^'\.#\(\)]+?\])([\s]+|[\s]*\r?$)"             
    $patterns += "(^.*)(OBJECT_ID)([\s]*\(')(\[[^'\.#\(\)]+?\])('\))"

    # Object name without []
#    $patterns += "(^[\s]*)(CREATE|ALTER|DROP)[\s]+(TABLE|VIEW|PROC|PROCEDURE|FUNCTION)[\s]+(?<objectname>[^#\s\.]+?)([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(CREATE|ALTER|DROP)[\s]+(TABLE|VIEW|PROC|PROCEDURE|FUNCTION)[\s]+([^#\s\.]+?)(\s|[\s]*\r?$)"
#    $patterns += "(^[\s]*)(TRUNCATE)[\s]+(TABLE)[\s]+([^#\s\.]+?)([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(TRUNCATE)[\s]+(TABLE)[\s]+([^#\s\.]+?)(\s|[\s]*\r?$)"

    # Object name with []
#    $patterns += "(^[\s]*)(CREATE|ALTER|DROP)[\s]+(TABLE|VIEW|PROC|PROCEDURE|FUNCTION)[\s]+(?<objectname>\[[^#\.]+?\])([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(CREATE|ALTER|DROP)[\s]+(TABLE|VIEW|PROC|PROCEDURE|FUNCTION)[\s]+(?<objectname>\[[^#\.]+?\])(\s|[\s]*\r?$)"
#    $patterns += "(^[\s]*)(TRUNCATE)[\s]+(TABLE)[\s]+(\[[^#\.]+?\])([\s]+|[\s]*\r?$)"
    $patterns += "(^[\s]*)(TRUNCATE)[\s]+(TABLE)[\s]+(\[[^#\.]+?\])(\s|[\s]*\r?$)"

    foreach ($pattern in $patterns)
    {
        $regexOptions = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant, Multiline'
        $matches = [regex]::Matches($query, $pattern, $regexOptions)

        foreach ($match in $matches)
        {
            if ($match.Groups.Count -lt 5)
            {
                # Didn't find an object name
                continue
            }

            $oldValue = $match.Groups[0].Value
            $oldObjectName = $match.Groups[4].Value
            if ($defaultSchema.Contains(" ")) {
                $newObjectName = "[" + $defaultSchema + "]." + $oldObjectName
            } else {
                $newObjectName = $defaultSchema + "." + $oldObjectName
            }
            $newValue = $oldValue.Replace($oldObjectName, $newObjectName)
            $query = $query.Replace($match.Groups[0].Value, $newValue)
        }
    }

    return $query
}


##########################################################################################################


function AddMissingSchemasSimple($query, $defaultSchema)
{
    $patterns = @()

    # single object name per line, e.g. stored procedure
    $patterns += "^([^\s\.#]+?)$"

    foreach ($pattern in $patterns)
    {
        $regexOptions = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant, Multiline'
        $matches = [regex]::Matches($query, $pattern, $regexOptions)

        foreach ($match in $matches)
        {
            if ($match.Groups.Count -lt 2)
            {
                # Didn't find an object name
                continue
            }

            $oldValue = $match.Groups[0].Value
            $oldObjectName = $match.Groups[1].Value
            $newObjectName = "[" + $defaultSchema + "]." + $oldObjectName
            $newValue = $oldValue.Replace($oldObjectName, $newObjectName)
            $query = $query.Replace($match.Groups[0].Value, $newValue)
        }
    }

    return $query
}

##########################################################################################################


function ChangeSchemas($DatabaseName, $SchemaMappings, $DefaultSchema, $query, $useThreePartNames)
{
    $regexOptions = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant, Multiline'

    foreach ($schemaMapping in $SchemaMappings)
    {
        #if ($schemaMapping.TargetSchema.Contains(" ")) {
        #    $newSchema = "[" + $schemaMapping.TargetSchema + "]"
        #} else {
        #    $newSchema = $schemaMapping.TargetSchema
        #}

        # Always use quoted identifiers
        $newSchema = "[" + $schemaMapping.TargetSchema + "]"

        if ($useThreePartNames) {
            $newSchema = "[" + $schemaMapping.TargetDatabase + "]." + $newSchema                                                # [TargetDatabase].[TargetSchema].
        }

        $newPat = '${prefix}' + $newSchema + '.'                                                                                 # ==> [TargetDatabase].[TargetSchema].

        if ($schemaMapping.SourceSchema -eq $DefaultSchema)
        {
            $oldPat = "(?<prefix>^|[\s]+)(?<objectname>" + $schemaMapping.SourceDatabase + "\.\.)"                                    # SourceDatabase.. 
            $query = $query -replace $oldPat, $newPat

            $oldPat = "(?<prefix>^|[\s]+)(?<objectname>\[" + $schemaMapping.SourceDatabase + "\]\.\.)"                                # [SourceDatabase].. 
            $query = $query -replace $oldPat, $newPat
        }

        $oldPat = "(?<prefix>^|[\s]+)(?<objectname>\[" + $schemaMapping.SourceDatabase + "\]\.\[" + $schemaMapping.SourceSchema + "\]\.)"# [SourceDatabase].[SourceSchema]. 
        $query = $query -replace $oldPat, $newPat
        $oldPat = "(?<prefix>^|[\s]+)(?<objectname>" + $schemaMapping.SourceDatabase + "\.\[" + $schemaMapping.SourceSchema + "\]\.)"    # SourceDatabase.[SourceSchema]. 
        $query = $query -replace $oldPat, $newPat
        $oldPat = "(?<prefix>^|[\s]+)(?<objectname>\[" + $schemaMapping.SourceDatabase + "\]\." + $schemaMapping.SourceSchema + "\.)"    # [SourceDatabase].SourceSchema. 
        $query = $query -replace $oldPat, $newPat
        $oldPat = "(?<prefix>^|[\s]+)(?<objectname>" + $schemaMapping.SourceDatabase + "\." + $schemaMapping.SourceSchema + "\.)"        # SourceDatabase.SourceSchema. 
        $query = $query -replace $oldPat, $newPat


        # This is for OBJECT_ID('schema.table') scenarios
        $newPat = '''' + $newSchema + '.'                                                                                       # ==> '[SQLDWSchema
        $oldPat = "'(?<objectname>\[" + $schemaMapping.SourceDatabase + "\]\.\[" + $schemaMapping.SourceSchema + "\]\.)"                # '[SourceDatabase].[SourceSchema]. 
        $query = $query -replace $oldPat, $newPat
        $oldPat = "'(?<objectname>"+$schemaMapping.SourceDatabase + "\.\[" + $schemaMapping.SourceSchema + "\]\.)"                      # 'SourceDatabase.[SourceSchema]. 
        $query = $query -replace $oldPat, $newPat

        $newPat = '''' + $newSchema + '.'                                                                       # ==> '[SQLDWSchema
        $oldPat = "'(?<objectname>\[" + $schemaMapping.SourceDatabase + "\]\." + $schemaMapping.SourceSchema + "\.)"                    # '[SourceDatabase].SourceSchema. 
        $query = $query -replace $oldPat, $newPat
        $oldPat = "'(?<objectname>"+$schemaMapping.SourceDatabase + "\." + $schemaMapping.SourceSchema + "\.)"                          # 'SourceDatabase.SourceSchema. 
        $query = $query -replace $oldPat, $newPat


        if ($schemaMapping.SourceDatabase -eq $DatabaseName)
        {
            $newPat = '''' + $newSchema + '.'                                                                                   # ==> '[SQLDWSchema].
            $oldPat = "'(?<objectname>\[" + $schemaMapping.SourceSchema + "\]\.)"                                  # OBJECT_ID('[SourceSchema]. 
            $query = $query -replace $oldPat, $newPat

            $newPat = '''' + $newSchema + '.'                                                                      # ==> '[SQLDWSchema].
            $oldPat = "'(?<objectname>"+$schemaMapping.SourceSchema + "\.)"                                        # OBJECT_ID('SourceSchema.
            $query = $query -replace $oldPat, $newPat


            $newPat = '${prefix}' + $newSchema + '.'                                                                      # ==> [SQLDWSchema].
            $oldPat = "(?<prefix>^|[\s]+)(?<objectname>\[" + $schemaMapping.SourceSchema + "\]\.)"                                  # [SourceSchema]. 
            $query = $query -replace $oldPat, $newPat

            $newPat = '${prefix}' + $newSchema + '.'                                                                      # ==> [SQLDWSchema].
            $oldPat = "(?<prefix>^|[\s]+)(?<objectname>"+$schemaMapping.SourceSchema + "\.)"                                       # SourceSchema.
            $query = $query -replace $oldPat, $newPat
        }
    }

	return $query
}

##########################################################################################################

function FixTempTables($query)
{
    $patterns = @()
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)(?<location>[\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?HEAP[\s]*?,[\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)(?<location>[\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?HEAP[\s]*?,[\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?CLUSTERED[\s]+COLUMNSTORE[\s]+INDEX[\s]*?,[\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)(?<location>[\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?CLUSTERED[\s]+COLUMNSTORE[\s]+INDEX[\s]*?,[\s]*?DISTRIBUTION[\s]*?=[\s]*(?<replicate>REPLICATE)[\s]*?\)"

    $patterns += "[\s]*CREATE[\s]+TABLE[\s]+#[\S]+[\s]+WITH[\s]*\([\s]*CLUSTERED[\s]+COLUMNSTORE[\s]+INDEX[\s]*(?<location>[\s]*,[\s]*?LOCATION[\s]*=[\s]*USER_DB)[\s]*,[\s]*?DISTRIBUTION[\s]*=[\s]*(?<replicate>REPLICATE)[\s]*\)"
    $patterns += "[\s]*CREATE[\s]+TABLE[\s]+#[\S]+[\s]+WITH[\s]*\([\s]*HEAP[\s]*(?<location>[\s]*,[\s]*?LOCATION[\s]*=[\s]*USER_DB)[\s]*,[\s]*?DISTRIBUTION[\s]*=[\s]*(?<replicate>REPLICATE)[\s]*\)"


    $regexOptions = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'

    foreach ($pattern in $patterns){
        $matches = [regex]::Matches($query, $pattern, $regexOptions)

        foreach ($match in $matches)
        {            
            $oldValue = $match.Groups[0].Value
            $newValue = $oldValue.Replace($match.Groups["replicate"].Value,"ROUND_ROBIN")
            if ($match.Groups["location"].Success)
            {
                $newValue = $newValue.Replace($match.Groups["location"].Value, "")
            }
            $query = $query.Replace($oldValue, $newValue)
        }
    }


    $patterns = @()
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?HEAP[\s]*?(?<location>[\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"
    $patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]?\([\s]*?CLUSTERED[\s]+COLUMNSTORE[\s]+INDEX[\s]*?(?<location>[\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"
    #$patterns += "[\s]*CREATE[\s]+?TABLE[\s]+?#[\S]+?[\s]+?WITH[\s]*?\([\s]*?.*?([\s]*?,[\s]*?LOCATION[\s]*?=[\s]*?USER_DB)[\s]*?\)"

    foreach ($pattern in $patterns){
        $matches = [regex]::Matches($query, $pattern, $regexOptions)
        foreach ($match in $matches)
        {
            $oldValue = $match.Groups[0].Value
            if ($match.Groups["location"].Success)
            {
                $newValue = $oldValue.Replace($match.Groups["location"].Value, "")
                $query = $query.Replace($oldValue, $newValue)
            }
        }
    }

    return $query
}

##########################################################################################################

function CheckUnsupportedDataTypes {    
    Param(
        [string]$query = ""
    )

    $queryLines = $query -split "`r`n"

    # Unsupported data types - geometry geography hierarchyid image text ntext sql_variant table timestamp xml
    # Typical use cases: 
    #   1) CREATE TABLE (c1 geometry)
    #   2) CONVERT(geometry,c1), CAST(c1 as geometry)
    #   3) CREATE FUNCTION dbo.ufnName(@p1 geometry)
    #   4) CREATE PROCEDURE dbo.uspName @p1 geometry
    $patterns = @()
    $patterns += [PSCustomObject]@{name="geometry";    pattern="(^|\s)[\[]?geometry[\]]?(\s|,|\)|$)"    ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="geography";   pattern="(^|\s)[\[]?geography[\]]?(\s|,|\)|$)"   ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="hierarchyid"; pattern="(^|\s)[\[]?hierarchyid[\]]?(\s|,|\)|$)" ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="image";       pattern="(^|\s)[\[]?image[\]]?(\s|,|\)|$)"       ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="ntext";       pattern="(^|\s)[\[]?ntext[\]]?(\s|,|\)|$)"       ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="text";        pattern="(^|\s)[\[]?text[\]]?(\s|,|\)|$)"        ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="sql_variant"; pattern="(^|\s)[\[]?sql_variant[\]]?(\s|,|\)|$)" ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="timestamp";   pattern="(^|\s)[\[]?timestamp[\]]?(\s|,|\)|$)"   ; count=0; lines=@()} 
    $patterns += [PSCustomObject]@{name="xml";         pattern="(^|\s)[\[]?xml[\]]?(\s|,|\)|$)"         ; count=0; lines=@()} 

    $regexOptions = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'

    for ($i=0; $i -lt $queryLines.Count; $i+=1) {
        $queryLine = $queryLines[$i]
        # Ignore comment lines
        if ($queryLine.TrimStart().StartsWith("--")) {
            continue
        }
        foreach ($pattern in $patterns) {
            $matches = [regex]::Matches($queryLine, $pattern.pattern, $regexOptions)

            if ($matches.Count -gt 0) {
                $pattern.count += 1
                $pattern.lines += $i+1
            }
        }
    }

    $summary = ""
    $totalUnsupported = ($patterns | Measure-Object -Property count -Sum).Sum
    if ($totalUnsupported -gt 0) {
        $summary = "/*`r`n`tTotal unsupported data types found - $totalUnsupported`r`n"

        $patternText = @{label="patternText"; expression={"`t"+$_.name.PadRight(15)+" - "+$_.count.ToString() + $(if ($_.count -gt 0){" (lines - " + ($_.lines -join ", ") + ")"})}}
        $summary += ($patterns | Select $patternText | Select -ExpandProperty patternText) -join "`r`n"
        $summary += "`r`n*/"
        Write-Debug $summary
    }

    $unsupportedDataTypes = $patterns | Where-Object {$_.count -gt 0} | Select-Object -Property name, count

    return $summary, $unsupportedDataTypes
}

##########################################################################################################


########################################################################################
#
# Main Program Starts here
#
########################################################################################

$ProgramStartTime = Get-Date

$ScriptPath = $PSScriptRoot

$defaultConfigFileName = "cs_dirs.csv"
$configFileName = Read-Host -prompt "Enter the name of the Config file name file. Press [Enter] if it is [$($defaultConfigFileName)]"
if($configFileName -eq "" -or $configFileName -eq $null)
	{$configFileName = $defaultconfigFileName}

$defaultSchemasFileName = "schemas.csv"
$schemasFileName = Read-Host -prompt "Please enter the name of your Schema Mapping file. Press [Enter] if it is [$($defaultSchemasFileName)]"
if($schemasFileName -eq "" -or $schemasFileName -eq $null)
	{$schemasFileName = $defaultSchemasFileName}

$defaultUseThreePartNames = "Yes"
$useThreePartNamesPrompt = Read-Host -prompt "Do you want to use 3-part names - Yes or No? Press [Enter] if it is [$($defaultUseThreePartNames)]"
if($useThreePartNamesPrompt -eq "" -or $useThreePartNamesPrompt -eq $null) {
    $useThreePartNamesPrompt = $defaultUseThreePartNames 
} 
if ( ($useThreePartNamesPrompt.ToUpper() -eq "YES") -or ($useThreePartNamesPrompt.ToUpper() -eq "Y") ) {
	$useThreePartNames = $true
} else {
    $useThreePartNames = $false
}

$defaultAddMissingSchemas = "Yes"
$addMissingSchemasPrompt = Read-Host -prompt "Do you want to add missing schemas - Yes or No? Press [Enter] if it is [$($defaultAddMissingSchemas)]"
if($addMissingSchemasPrompt -eq "" -or $addMissingSchemasPrompt -eq $null) {
    $addMissingSchemasPrompt = $defaultAddMissingSchemas 
} 
if ( ($addMissingSchemasPrompt.ToUpper() -eq "YES") -or ($addMissingSchemasPrompt.ToUpper() -eq "Y") ) {
	$addMissingSchemas = $true
} else {
    $addMissingSchemas = $false
}


$configFilePath = Join-Path -Path $ScriptPath -ChildPath $configFileName
if (!(Test-Path $configFilePath )) {
    Write-Host "Could not find Config file: $configFilePath " -ForegroundColor Red
    break 
}

$schemasFilePath = Join-Path -Path $ScriptPath -ChildPath $schemasFileName
if (!(Test-Path $schemasFilePath )) {
    Write-Host "Could not find Schemas Mapping file: $schemasFilePath " -ForegroundColor Red
    break 
}

$configCsvFile = Import-Csv $configFilePath 
$schemaCsvFile = Import-Csv $schemasFilePath
 
$unsupportedDataTypesTotal = @()
$totalFiles = 0
$totalFilesUnsupportedDataTypes = 0

foreach ($configRow in $configCsvFile) 
{
    if ($configRow.Active -eq '1') 
	{
        $databaseName = $configRow.SourceDatabaseName  
        $sourceDir = Get-AbsolutePath $configRow.SourceDirectory
        $targetDir = Get-AbsolutePath $configRow.TargetDirectory
        $defaultSchema = $configRow.DefaultSchema
        
        if (!(Test-Path -Path $sourceDir)) {
            continue
        }

        foreach ($file in Get-ChildItem -Path $sourceDir -Filter *.sql)
        {
            $totalFiles += 1
            $sourceFilePath = $file.FullName
            $targetFilePath = Join-Path -Path $targetDir -ChildPath $file.Name
            (Get-Date -Format HH:mm:ss.fff)+" - "+$targetFilePath | Write-Host -ForegroundColor Yellow
            $content = Get-Content -Path $SourceFilePath -Raw

            $newContent = $content

            # Check for unsupported data types
            $unsupportedDataTypesSummary, $unsupportedDataTypes = CheckUnsupportedDataTypes -Query $newContent

            $newContent = FixTempTables -Query $newContent
            if ($addMissingSchemas) {
                # Add missing schemas to object references
                $newContent = AddMissingSchemas -Query $newContent -defaultSchema $defaultSchema
            }
            # Change schema in object references according to schema mapping
            $newContent = ChangeSchemas -DatabaseName $databaseName -SchemaMappings $schemaCsvFile -query $newContent -defaultSchema $defaultSchema -useThreePartNames $useThreePartNames

            # Create target folder if it does not exist
            $targetFolder = [IO.Path]::GetDirectoryName($targetFilePath)
            if (!(Test-Path $targetFolder))
            {
	            New-item -Path $targetFolder -ItemType Dir | Out-Null
            }

            # if there are unsupported data types found we add a comment to the script
            if ($unsupportedDataTypesSummary) {
                $newContent = $unsupportedDataTypesSummary + "`r`n`r`n" + $newContent
                $unsupportedDataTypesTotal += $unsupportedDataTypes
                $totalFilesUnsupportedDataTypes += 1
            }

            $newContent | Out-File $targetFilePath
        }
	}
}


$totalOccurencesUnsupportedDataTypes = ($unsupportedDataTypesTotal | Measure-Object -Property count -Sum).Sum
if ($totalOccurencesUnsupportedDataTypes -eq $null) {
    $totalOccurencesUnsupportedDataTypes = 0
}

$ProgramFinishTime = Get-Date

Write-Host "Total Files Analyzed:   ", $totalFiles -ForegroundColor DarkYellow
Write-Host "Total Files w/ Unsupported Data Types:   ", $totalFilesUnsupportedDataTypes -ForegroundColor DarkYellow
Write-Host "Total Unsupported Data Types Occurences:   ", $totalOccurencesUnsupportedDataTypes -ForegroundColor DarkYellow

$unsupportedDataTypesReport = $unsupportedDataTypesTotal | Group-Object name | %{
    New-Object PSObject -Property @{
        DataType = $_.Name
        Count = ($_.Group | Measure-Object Count -Sum).Sum
    }
}
$unsupportedDataTypesReport | Format-Table #-Property Name, Count  -HideTableHeaders

Write-Host "Program Start Time:   ", $ProgramStartTime -ForegroundColor Magenta
Write-Host "Program Finish Time:  ", $ProgramFinishTime -ForegroundColor Magenta
Write-Host "Program Elapsed Time: ", ($ProgramFinishTime-$ProgramStartTime) -ForegroundColor Magenta
