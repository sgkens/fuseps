@{
    RootModule         = 'fuseps.psm1'
    ModuleVersion      = '0.2.7'
    GUID               = '019bd9b6-4e52-7ce9-aab8-d4df434d7a42'
    Author             = 'Garvey k. Snow'
    CompanyName        = 'Phellams'
    Copyright          = '(c) 2026 Garvey k. Snow. All rights reserved.'
    Description        = 'FusePS is a static analysis and bundling engine. It merges split-source PowerShell modules into single-file artifacts (.psm1) for zero-overhead startup and simplified distribution.'
    FunctionsToExport  = @()
    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags                     = @('PSModule', 'wsl', 'windows', 'linux', 'virtualization', 'subsystem', 'wsl2', 'distribution', 'powershell', 'automation', 'tool', 'utility', 'wrapper')
            ReleaseNotes             = @{ 
                # '1.2.1' = 'Initial release with New-PHWriter cmdlet for custom help formatting and enhanced layout.'
            }
            RequireLicenseAcceptance = $false
            LicenseUri               = 'https://choosealicense.com/licenses/mit'
            ProjectUri               = 'https://gitlab.com/phellams/fuseps.git'
            IconUri                  = 'https://raw.githubusercontent.com/phellams/phellams-general-resources/main/logos/fuseps/dist/png/fuseps-128x128.png'
            # CHOCOLATE ---------------------
            ChocoDescription         = 'A wrapper for `wsl.exe`. It parses WSL output into standard PowerShell objects, provides safety checks for destructive operations, and automates the migration of distributions between drives.'
            LicenseUrl               = 'https://choosealicense.com/licenses/mit'
            ProjectUrl               = 'https://gitlab.com/phellams/fuseps'
            IconUrl                  = 'https://raw.githubusercontent.com/phellams/phellams-general-resources/main/logos/fuseps/dist/png/fuseps-128x128.png'
            Docsurl                  = 'https://gitlab.com/phellams/fuseps#core-features'
            MailingListUrl           = 'https://gitlab.com/phellams/fuseps/issues'
            projectSourceUrl         = 'https://gitlab.com/phellams/fuseps'
            bugTrackerUrl            = 'https://gitlab.com/phellams/fuseps/issues'
            Summary                  = 'FusePS is a static analysis and bundling engine. It merges split-source PowerShell modules into single-file artifacts (.psm1) for zero-overhead startup and simplified distribution.'
            # CHOCOLATE ---------------------
            Prerelease               = ''

        }        
    }
    RequiredModules    = @()
    RequiredAssemblies = @()
    FormatsToProcess   = @()
    TypesToProcess     = @()
    NestedModules      = @()
    ScriptsToProcess   = @()
}
