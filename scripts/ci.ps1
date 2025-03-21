[CmdletBinding(SupportsShouldProcess)]
param(
)
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 6) {
    throw "This script requires at least powershell 6"
}

# The root directory of our repository:
$REPO_DIR = Split-Path $PSScriptRoot -Parent

# Import the utility modules
Import-Module (Join-Path $PSScriptRoot "cmt.psm1")

# Sanity check for yarn
$yarn = Find-Program yarn
if (! $yarn) {
    $npm = Find-Program npm
    if (! $npm ) {
        throw "No 'yarn' binary, and not 'npm' to install it. Cannot build."
    }
    else {
        try {
            Invoke-ChronicCommand "Install yarn" $npm install --global yarn
        }
        catch {
            Write-Error "Failed to install 'yarn' globally. Please install yarn to continue."
        }
        $yarn = Find-Program yarn
    }
}

$out_dir = Join-Path $REPO_DIR out
if (Test-Path $out_dir) {
    Write-Verbose "Removing out/ directory: $out_dir"
    Remove-Item -Recurse $out_dir
}

# Install dependencies for the project
Invoke-ChronicCommand "yarn install" $yarn install

# Now do the real compile
Invoke-ChronicCommand "Compiling TypeScript" $yarn run compile-production


# Get the CMake binary that we will use to run our tests
# The cmake server mode has been removed since CMake 3.20. Clients should use the cmake-file-api(7) instead.
$cmake_binary = Install-TestCMake -Version "3.18.2"
$Env:CMAKE_EXECUTABLE = $cmake_binary

# Add cmake to search path environment variable
if ($PSVersionTable.Platform -eq "Unix") {
    function set_cmake_in_path( $file, $cmake_path ) {
        $start = "export CMAKE_BIN_DIR="
        $content = Get-Content $file
        if ( $content -match "^$start" ) {
            $content -replace "^$start.*", "$start$cmake_path" |
            Set-Content $file
        } else {
            Add-Content $file "$start$cmake_path"
            Add-Content $file 'export PATH=$CMAKE_BIN_DIR:$PATH'
        }
    }
    set_cmake_in_path "~/.bashrc" (get-item $cmake_binary).Directory.FullName
} else {
    $Env:PATH = (get-item $cmake_binary).Directory.FullName + [System.IO.Path]::PathSeparator + $Env:PATH
}

# Get the Ninja binary that we will use to run our tests
$ninja_binary = Install-TestNinjaMakeSystem -Version "1.8.2"

# Add ninja to search path environment variable
$Env:PATH = (get-item $ninja_binary).Directory.FullName + [System.IO.Path]::PathSeparator + $Env:PATH

Invoke-ChronicCommand "yarn lint" $yarn run lint

# Run tests
Invoke-TestPreparation -CMakePath $cmake_binary

# A bug in yarn causes the contents of the NOTICE file to be inlined into an environment variable
# which causes msbuild to crash in some tests. Just remove it to avoid the problem.
# https://github.com/yarnpkg/yarn/issues/7783
if (Test-Path NOTICE.txt) {
    Remove-Item NOTICE.txt
}

Invoke-ChronicCommand "yarn backendTests" $yarn run backendTests
Invoke-ChronicCommand "yarn pretest" $yarn run pretest
Invoke-ChronicCommand "yarn smokeTests" $yarn run smokeTests
Invoke-ChronicCommand "yarn unitTests" $yarn run unitTests
Invoke-ChronicCommand "yarn extensionTestsSuccessfulBuild" $yarn run extensionTestsSuccessfulBuild
Invoke-ChronicCommand "yarn extensionTestsSingleRoot" $yarn run extensionTestsSingleRoot
Invoke-ChronicCommand "yarn extensionTestsMultiRoot" $yarn run extensionTestsMultiRoot
