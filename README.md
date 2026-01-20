# **FusePS**

Zero-Overhead Compilation for High-Performance Modules.

**FusePS** is a PowerShell Module Bundler. It takes a development environment consisting of scattered functions, classes, and assemblies, and "fuses" them into a single, high-performance artifact (`.psm1`) optimized for fast loading and easy distribution.

It is not a transpiler. It is a static analysis and bundling engine that enforces industry-standard architecture while eliminating the runtime cost of dot-sourcing files.

## **Core Features**

* **Single-File Artifacts**: Compiles hundreds of `.ps1` files into one `.psm1`, reducing module load time by up to 90%.
* **Smart Scoping & Exports**: Automatically detects `FunctionsToExport` and `AliasesToExport` (via `[Alias()]` attributes). It intelligently ignores private functions (prefixed with `_`) and nested helper functions, ensuring only your public API is exposed.
* **Namespace Hoisting**: Scans all source files for `using namespace` statements and automatically hoists them to the top of the compiled artifact, preventing syntax errors in merged files.
* **Surgical Manifest Updates**: Updates your `.psd1` manifest using AST splicing. This allows it to update version numbers and export lists while guaranteeing that your **comments and custom formatting are preserved 100%**.
* **Smart DLL Injection**: Drop `.dll` files into `src/Assemblies`. FusePS creates a `bin/` folder in the output and injects a loader at the top of your module automatically.
* **Visual Build Logs**: Features a high-contrast, ANSI 256-color logging system with distinct badges for status updates, errors, and git operations.
* **Syntax Safety**: Performs a full AST syntax check on the compiled code before saving. It will never overwrite a valid build with broken code.
* **Asset Mirroring**: Automatically copies `src/Data` and configured assets (Licenses, Readmes) to the distribution folder.

## **Project Structure**

FusePS relies on a specific "**Convention over Configuration**" directory layout.

```text
MyProject/
├── build.ps1                 # The Bootstrapper (Entry point)
├── build_config.json         # Build Configuration
├── src/
│   ├── MyModule.psd1         # Manifest Template
│   ├── Classes/              # [Optional] PowerShell Classes & Enums (Loaded 1st)
│   ├── Assemblies/           # [Optional] C# .dll files (Loaded 0th)
│   ├── Private/              # [Optional] Internal Helper Functions
│   ├── Public/               # [Required] Exported Functions
│   └── Data/                 # [Optional] JSON/XML/Assets (Copied to dist)
└── dist/                     # [Generated] Final Build Artifacts

```
> Note: Files in `Classes/`, `Private/`, and `Public/` are sorted alphabetically before merging. If **Class B** depends on **Class A**, name them **01_ClassA.ps1** and **02_ClassB.ps1**.

---

## Configuration (`build_config.json`)

Create a `build_config.json` in your project root.

```json
{
    "psmcompiler": {
        "ModuleName": "MyModule",
        "SourcePath": "./src",
        "DistPath": "./dist",
        "VersionStrategy": "GitAuto",
        "Options": {
            "StripComments": false,
            "RegionSeparators": true,
            "AutoExport": true
        },
        "CopyPaths": [
            "LICENSE",
            "README.md",
            "docs/"
        ]
    }
}

```

### Configuration Key Reference

| Key  | Description
|---|---|
|*ModuleName*| The name of the module (Must match `.psd1` filename). |
|*VersionStrategy*| SemVer Auto Version or `Manual` (Reads from manifest). |
|*CopyPaths*| Array of file/folder paths (relative to root) to copy to `dist/.` |
|*RegionSeparators*| Adds `# ____/[ Region ]____` headers to the compiled file for readability. |



## **Usage Workflow**

1️⃣ ***The Bootstrapper***

FusePS is designed to build itself. You do not need the module installed to run the build. Use the provided build.ps1 script to shim the compiler into memory.

> **RUN**: `build.ps1`

```Powershell
# build.ps1
param($Task = "Build")

$Root = $PSScriptRoot

# 1. BOOTSTRAP: Load the compiler's own logic into memory
#    This bypasses the need for the module to be installed.
$Source = Join-Path $Root "src"
. (Join-Path $Source "private/Write-Logr.ps1")      # Load Logger first
. (Join-Path $Source "private/kvinc.ps1")           # Load the AST Helper above
. (Join-Path $Source "public/Invoke-FusePS.ps1")    # Load the Compiler/Builder

# 2. RUN
if ($Task -eq "Build") {
    Invoke-PsmCompile -ProjectPath $Root
}
```

2️⃣ ***The Development Loop (Dev Mode)***


```powershell
# Run this in your console to load the "Raw" module for testing
$Root = "C:\Projects\MyModule"
Get-ChildItem "$Root/src/Classes/*.ps1" | ForEach { . $_.FullName }
Get-ChildItem "$Root/src/Private/*.ps1" | ForEach { . $_.FullName }
Get-ChildItem "$Root/src/Public/*.ps1"  | ForEach { . $_.FullName }
```

Do not build the module every time you change a line of code. Use a "Dev Loader" snippet in your profile or test script to load the raw source files into memory instantly.

3️⃣ ***The Release Loop (Build Mode)***

When you are ready to ship, push, or verify:

1. Run `./build.ps1`.
2. Inspect the `dist/MyModule` folder.
3. Test the artifact in a fresh **PowerShell** session:
    ```powershell
    pwsh -NoProfile -Command "Import-Module ./dist/MyModule/MyModule.psd1; Get-Help Get-MyFunction"
    ```

## **Advanced Features**

**C# Assemblies** (`src/Assemblies`)

If your module relies on compiled **C#** code:

1. Place your `.dll` files in `src/Assemblies/`.
2. **FusePS Action**:
    1. Creates `dist/MyModule/bin/`.
    2. Copies the **DLLs** there.
    3. Injects `Add-Type -Path "$PSScriptRoot/bin/MyLib.dll"` at the very top of your compiled `.psm1`.

**Data & Assets** (`src/Data`)

If your module needs to read **JSON** configuration or templates at runtime:

1. Place files in `src/Data/`.
2. FusePS Action: Copies the folder to `dist/MyModule/Data/`.
3. **Accessing it in code**:
    ```powershell
    $Config = Get-Content (Join-Path $PSScriptRoot "Data/config.json") | ConvertFrom-Json
    ```
## **Technical Notes**

- **Load Order**:
    1. Assemblies (DLLs)
    2. Classes & Enums
    3. Private Functions
    4. Public Functions

- **Manifest Updates**: FusePS uses the AST to locate the FunctionsToExport hashtable key. If your manifest is missing this key, the auto-export feature will skip the update (and warn you).

- **Aliases**: FusePS scans for [Alias('Name')] attributes on your functions and automatically adds them to AliasesToExport in the manifest.


## How to handle Dependencies

If you have a shared library (e.g., `Logr`), do not copy-paste code.

1. **Repo Structure:** Keep `Logr` in a separate repo or a `libs/` folder.
2. **Symlink (Advanced):** Symlink the file into `src/Private/`.
3. **Injector (FusePS V2 Feature):** Eventually add a `Libraries` array to `build_config.json` that FusePS reads and injects text content from external paths directly into the build stream.

## Troubleshooting

* **Syntax Errors:** FusePS parses the final string before saving. If you miss a closing bracket `}` in one file, the build will fail and tell you.
* **Missing Exports:** Ensure your public functions are in `src/Public`. FusePS only auto-exports functions found in that folder.
* **Class Order:** If `Class B` uses `Class A`, rename the files: `src/Classes/01_ClassA.ps1`, `src/Classes/02_ClassB.ps1`. FusePS sorts alphabetically.