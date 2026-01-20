function Invoke-FusePS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $false)]
        [switch]$EnableParserOutput
    )

    # -------------------------------------------------------------------------
    # 0. INTERNAL HELPERS
    # -------------------------------------------------------------------------
    $script:__logging = $true # enable logging for write-logr

    # Internal Logger: Uses Write-logr if available, falls back to Write-Host
    function _Log {
        param($Msg, $action, $Type = "inf")
        if (Get-Command "Write-logr" -ErrorAction SilentlyContinue) {
            Write-logr -Message $Msg -Action $action -Type $Type -LogName "FusePS"
        }else {
            Write-Host "[FusePS] $Type - $action -> $Msg"
        }
    }

    # AST Manifest Updater
    function _Update-Psd1 { 
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Path, 
            
            [Parameter(Mandatory)]
            [string]$Key, 
            
            [Parameter(Mandatory)]
            [AllowNull()]
            [psobject]$Val
        )

        # 1. File Safety
        if (-not (Test-Path -LiteralPath $Path)) {
            _Log "Manifest not found: $Path" 'update' 'err'
            return
        }
        
        $Item = Get-Item -LiteralPath $Path
        if ($Item.IsReadOnly) { $Item.IsReadOnly = $false }

        $C = Get-Content -LiteralPath $Path -Raw
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($C, [ref]$null, [ref]$null)
        
        # 2. LOGIC FIX: Find the Hashtable Container, not the Entry
        #    We look for the FIRST Hashtable in the file (Standard for .psd1)
        $RootHash = $Ast.FindAll({ $args[0].GetType().Name -eq 'HashtableAst' }, $true) | Select-Object -First 1
        
        if (-not $RootHash) {
            _Log "Invalid PSD1: Could not find a Hashtable structure in $Path" 'update' 'err'
            return
        }

        # 3. Iterate the properties manually to find our Key
        #    KeyValuePairs is a list of [Tuple<KeyAst, ValueAst>]
        $TargetPair = $null
        
        foreach ($pair in $RootHash.KeyValuePairs) {
            # Check if the Key matches (Case Insensitive)
            if ($pair.Item1.Value -eq $Key) {
                $TargetPair = $pair
                break
            }
        }

        if ($TargetPair) {
            $NewVal = $null

            # --- Formatting Logic ---
            if ($null -eq $Val) {
                $NewVal = '$null'
            }
            elseif ($Val -is [bool]) {
                $NewVal = $Val.ToString().ToLower()
            }
            elseif ($Val -is [int] -or $Val -is [long] -or $Val -is [double]) {
                $NewVal = "$Val"
            }
            elseif ($Val -is [array] -or $Val -is [System.Collections.IEnumerable] -and $Val -isnot [string]) {
                if ($Val.Count -eq 0) {
                    $NewVal = "@()"
                } else {
                    $EscapedItems = $Val | ForEach-Object { 
                        if ($null -eq $_) { '$null' } 
                        else { "'" + $_.ToString().Replace("'", "''") + "'" } 
                    }
                    $NewVal = "@(" + ($EscapedItems -join ", ") + ")"
                }
            }
            else {
                $EscapedString = $Val.ToString().Replace("'", "''")
                $NewVal = "'$EscapedString'"
            }

            # 4. Replace content safely
            #    Item2 is the VALUE part of the tuple. We want to replace that.
            $Start = $TargetPair.Item2.Extent.StartOffset
            $Len   = $TargetPair.Item2.Extent.EndOffset - $Start
            
            $C = $C.Remove($Start, $Len).Insert($Start, $NewVal)
            
            $C | Set-Content -LiteralPath $Path -Encoding UTF8 -Force
            
            _Log "Updated Manifest {kv:key=$Key} to {kv:val=$NewVal}" 'update' 'chk' 
        }
        else {
            _Log "Manifest Key {kv:key=$Key} not found in root hashtable." 'update' 'wrn'
        }
    }

    function Move-UsingToTop {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$ScriptContent
        )

        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$null, [ref]$null)

        # 1. Find all 'using' statements
        $UsingNodes = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.UsingStatementAst] }, $true)

        if ($UsingNodes.Count -eq 0) {
            return $ScriptContent
        }

        # 2. Extract the text of the using statements
        #    We use a HashSet to dedup (e.g. avoid 5 copies of "using namespace System.Collections")
        $UniqueUsing = [System.Collections.Generic.HashSet[string]]::new()
        $UsingLines  = [System.Collections.Generic.List[string]]::new()

        foreach ($node in $UsingNodes) {
            $text = $node.Extent.Text.Trim()
            if ($UniqueUsing.Add($text)) {
                $UsingLines.Add($text)
            }
        }

        # 3. Remove them from the body
        #    CRITICAL: We must delete from Bottom to Top (Reverse Order) 
        #    so that offsets don't shift while we are working.
        $SortedNodes = $UsingNodes | Sort-Object { $_.Extent.StartOffset } -Descending

        foreach ($node in $SortedNodes) {
            $Start = $node.Extent.StartOffset
            $Len   = $node.Extent.EndOffset - $Start
            
            # Remove the statement
            $ScriptContent = $ScriptContent.Remove($Start, $Len)
            
            # Optional: Clean up empty newlines left behind (simple regex check)
            # (This prevents huge gaps in code where the using statement used to be)
        }

        # 4. Reconstruct: Usings + Newlines + Body
        $Header = $UsingLines -join [Environment]::NewLine
        
        # Trim leading whitespace from the body so it sits flush against the headers
        $Body = $ScriptContent.TrimStart()

        return $Header + [Environment]::NewLine + [Environment]::NewLine + $Body
    }
    # -------------------------------------------------------------------------
    # 1. SETUP & CONFIGURATION
    # -------------------------------------------------------------------------
    $ConfigPath = Join-Path $ProjectPath "build_config.json"
    if (-not (Test-Path $ConfigPath)) { 
        _Log "Config not found at: $ConfigPath" 'config' 'err' ; return 
    }
    
    $Json = Get-Content $ConfigPath | ConvertFrom-Json
    $Config = $Json.psmcompiler

    $SourceRoot = Join-Path $ProjectPath $Config.SourcePath
    $DistRoot = Join-Path $ProjectPath $Config.DistPath
    $ModuleDist = Join-Path $DistRoot $Config.ModuleName
    
    _Log "Initializing build for {kv:module=$($Config.ModuleName)}" 'config' 'inf' 

    # -------------------------------------------------------------------------
    # 2. ANALYSIS PHASE (AST Scanning)
    # -------------------------------------------------------------------------
    $ExportedFunctions = @()
    $ExportedAliases   = @()
    $PublicPath = Join-Path $SourceRoot "Public"

    if (Test-Path $PublicPath) {
        _Log "Analyzing Public functions and Aliases..." 'test' 'chk'
        
        Get-ChildItem -Path $PublicPath -Filter *.ps1 -Recurse | ForEach-Object {
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content $_.FullName -Raw), [ref]$null, [ref]$null)
            
            # Find ALL Function Definitions (including nested ones)
            $FuncDefs = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            
            foreach ($Def in $FuncDefs) {
                # --- FIX: NESTING CHECK ---
                # Walk up the AST tree. If we hit another FunctionDefinition, this is a nested function.
                $Parent   = $Def.Parent
                $IsNested = $false
                
                while ($Parent) {
                    if ($Parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                        $IsNested = $true
                        break
                    }
                    $Parent = $Parent.Parent
                }

                # Skip if it's nested (or if it's a private function starting with _)
                if ($IsNested -or ($Def.Name -match '^_')) { 
                    continue 
                }

                # If we made it here, it's a Top-Level Public Function
                $ExportedFunctions += $Def.Name
                
                # --- ALIAS SCANNING ---
                # Safety: ParamBlock can be null, so check before accessing .Attributes
                $ParamAttrs = if ($Def.Body.ParamBlock) { $Def.Body.ParamBlock.Attributes } else { @() }
                $AllAttributes = $Def.Attributes + $ParamAttrs

                foreach ($Attr in $AllAttributes) {
                    if ($Attr.TypeName.Name -match 'Alias') {
                        foreach ($Arg in $Attr.PositionalArguments) { 
                            # Value can be a bare string or StringConstantExpression
                            $ExportedAliases += $Arg.Value 
                        }
                    }
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # 3. COMPILATION PHASE (The Stitching)
    # -------------------------------------------------------------------------
    $sb = [System.Text.StringBuilder]::new()
    
    # Header
    [void]$sb.AppendLine("# ---------------------------------------------------")
    [void]$sb.AppendLine("# Fused by FusePS at $(Get-Date)")
    [void]$sb.AppendLine("# Module: $($Config.ModuleName)")
    [void]$sb.AppendLine("# ---------------------------------------------------")
    [void]$sb.AppendLine('$Script:FuseState = @{}')
    [void]$sb.AppendLine("")

    # A. ASSEMBLY LOADER (DLLs)
    $AssemblyPath = Join-Path $SourceRoot "Assemblies"
    if (Test-Path $AssemblyPath) {
        _Log "Processing Assemblies (DLLs)..." 'test' 'chk'
        
        # Create bin directory in Dist
        $BinDist = Join-Path $ModuleDist "bin"
        if (-not (Test-Path $BinDist)) { New-Item -Path $BinDist -ItemType Directory -Force | Out-Null }
        
        Get-ChildItem -Path $AssemblyPath -Filter *.dll | ForEach-Object {
            # Copy DLL to dist/bin
            Copy-Item $_.FullName $BinDist -Force
            
            # Inject Loader Code
            [void]$sb.AppendLine("# [Region: Assembly Loader ($($_.Name))]")
            [void]$sb.AppendLine('$DllPath = Join-Path $PSScriptRoot "bin" "' + $_.Name + '"')
            [void]$sb.AppendLine('Add-Type -Path $DllPath')
            [void]$sb.AppendLine("# [EndRegion]")
            [void]$sb.AppendLine("")
        }
    }

    # Helper for Script Regions
    $AddRegion = { param($Title, $Path)
        [void]$sb.AppendLine("# ____/[ Region: $Title ]\____")
        Get-ChildItem $Path -Filter *.ps1 -Recurse | Sort-Object Name | ForEach-Object {
            [void]$sb.AppendLine((Get-Content $_.FullName -Raw))
        }
        [void]$sb.AppendLine("")
    }

    # B. CLASSES (Sorted Alphabetically for basic dependencies)
    if (Test-Path "$SourceRoot/Classes") { & $AddRegion "Classes & Enums" "$SourceRoot/Classes" }

    # C. PRIVATE (Helpers)
    if (Test-Path "$SourceRoot/Private") { & $AddRegion "Private Helpers" "$SourceRoot/Private" }

    # D. PUBLIC (Exported)
    if (Test-Path "$SourceRoot/Public") { & $AddRegion "Public API" "$SourceRoot/Public" }

    # -------------------------------------------------------------------------
    # 4. VALIDATION & ARTIFACT GENERATION
    # -------------------------------------------------------------------------
    $FinalCode = $sb.ToString()
    $FinalCode = Move-UsingToTop -ScriptContent $FinalCode
    
    # Syntax Check
    $ParseErrors = $null
    if($EnableParserOutput) {
        [System.Management.Automation.Language.Parser]::ParseInput($FinalCode, [ref]$null, [ref]$ParseErrors)
    }
    
    if ($ParseErrors) { 
        _Log "COMPILATION FAILED: Syntax Errors Detected" 'config' 'err'
        $ParseErrors | ForEach-Object { Write-Error $_ }
        return # Abort
    }

    # Write .psm1
    if (-not (Test-Path $ModuleDist)) { New-Item -Path $ModuleDist -ItemType Directory -Force | Out-Null }
    $Psm1Path = Join-Path $ModuleDist "$($Config.ModuleName).psm1"
    $FinalCode | Set-Content $Psm1Path -Encoding UTF8
    
    _Log "Created Artifact: $Psm1Path" 'create' 'inf'

    # -------------------------------------------------------------------------
    # 5. ASSET MANAGEMENT & MANIFEST
    # -------------------------------------------------------------------------
    
    # Copy implicit Data folder
    if (Test-Path "$SourceRoot/Data") { 
        Copy-Item "$SourceRoot/Data" "$ModuleDist" -Recurse -Force 
        _Log "Copied Data directory" 'create' 'inf'
    }
    
    # Copy Configured Assets (License, Readme, etc.)
    if ($Config.CopyPaths) {
        foreach ($PathEntry in $Config.CopyPaths) {
            $Src = Join-Path $ProjectPath $PathEntry
            if (Test-Path $Src) { 
                Copy-Item $Src $ModuleDist -Recurse -Force 
                _Log "Copied Asset: $PathEntry" 'create' 'inf'
            }
            else {
                _Log "Missing Asset: $PathEntry" 'create' 'wrn' 
            }
        }
    }

    # Handle Manifest (.psd1)
    $ManifestSrc = Join-Path $SourceRoot "$($Config.ModuleName).psd1"
    $ManifestDest = Join-Path $ModuleDist "$($Config.ModuleName).psd1"
    
    if (Test-Path $ManifestSrc) {

        _log "Updating Manifest {kv:path=$ManifestDest}" 'update' 'inf'

        Copy-Item $ManifestSrc $ManifestDest -Force

        $semver = "$((Get-GitAutoVersion).Version)"
        
        # 1. Update Exports
        _Update-Psd1 -Path $ManifestDest -Key "FunctionsToExport" -val $ExportedFunctions
        _Update-Psd1 -Path $ManifestDest -Key "AliasesToExport" -val $ExportedAliases
        _Update-Psd1 -Path $ManifestDest -Key "ModuleVersion" -val $semver
        
        # 2. NEW: Update RequiredAssemblies
        # We get the list of DLL names we copied to 'bin'
        if (Test-Path "$SourceRoot/Assemblies") {
            $DllNames = Get-ChildItem "$SourceRoot/Assemblies" -Filter *.dll | ForEach-Object { 
                # We list them as relative paths: 'bin/MyLib.dll'
                "bin/$($_.Name)" 
            }
            if ($DllNames) {
                _Update-Psd1 -Path $ManifestDest -Key "RequiredAssemblies" -val $DllNames
                _Log "Updated Manifest RequiredAssemblies" 'update' 'inf'
            }
        }
    }
    else {
        _Log "No .psd1 manifest found in source!" 'config' 'wrn'
    }

    _Log "BUILD COMPLETE." 'success' 'inf'
}