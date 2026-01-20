# build.ps1
param($Task = "Build")


# ===================[ CONFIG ]============================

$Root = $PSScriptRoot

# clone common repos if not already present
# ---
$clones = @(
    @{ source='gitlab'; repo='/phellams-utils'; dest="$Root\phellams-utils" }
)

# define links to create links are setup as symlinks
# targets are auto . sourced into memory
# ---
$clone_links = @(
    @{ source = "$Root\phellams-utils\helpers\log_utils\kvstring.ps1";        target = "$Root\src\private\kvstring.ps1" }
    @{ source = "$Root\phellams-utils\helpers\log_utils\ctstring.ps1";        target = "$Root\src\private\ctstring.ps1" }
    @{ source = "$Root\phellams-utils\helpers\datetime\Format-DateTime.ps1";  target = "$Root\src\private\Format-DateTime.ps1" }
    @{ source = "$Root\phellams-utils\helpers\semver\Get-GitAutoVersion.ps1"; target = "$Root\src\private\Get-GitAutoVersion.ps1"}
    @{ source = "$Root\phellams-utils\helpers\log_utils\write-logr.ps1";      target = "$Root\src\private\write-logr.ps1" }
)

# Dot source files into memory
# ---
$public_links = @(
    "$Root\src\public\Invoke-FusePS.ps1"
)

# ===================[ CONFIG ]============================

# ----

# ===================[ LOGIC ]=============================

# 1. BOOTSTRAP: Load the compiler's own logic into memory
#    This bypasses the need for the module to be installed.

Write-Host "-{ BOOTSTRAPPING Development Environment }" -ForegroundColor Magenta
$indent = " " * 4
$sep = " •-"
foreach ($clone in $clones) {
    if((Test-Path -Path $clone.dest -erroraction silentlycontinue)) {
        Write-Host "$indent$sep Cloning $($clone.repo) to $($clone.dest)" -ForegroundColor DarkYellow
        cd $clone.dest
        git pull
        cd ../
    }else{
        Write-Host "$indent$sep Cloning $($clone.repo) to $($clone.dest)" -ForegroundColor Green
        git clone "https://$($clone.source).com/$($clone.repo).git" $clone.dest
    }
}

foreach ($link in $clone_links) {
    $source = $link.source
    $target = $link.target

    if (-Not (Test-Path $target -erroraction silentlycontinue)) {
        New-Item -ItemType SymbolicLink -Path $target -Target $source
        write-host "$indent$sep Creating symlinks from $source to $target" -ForegroundColor green
    }else{
        write-host "$indent$sep $target already exists, skipping" -ForegroundColor DarkYellow
    }

    # dot source
    write-host "$indent$sep Dotsourcing clone link into memory: $target" -ForegroundColor Green

    . $target
}

foreach ($public in $public_links) {
    write-host "$indent$sep Dotsourcing public link into memory: $public" -ForegroundColor Green
    . "$public"

}

# 2. RUN
if ($Task -eq "Build") {
    Invoke-FusePS -ProjectPath $Root
}

# ===================[ LOGIC ]=============================