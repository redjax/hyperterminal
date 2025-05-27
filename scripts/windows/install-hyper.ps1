[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false, HelpMessage = "Name of a configuration directory to use. Must match a directory in config/")]
    [string]$Config = "default"
)

## Set path script was launched from as a variable
#  Use Set-Location to change to other paths, then
#  Set-Location $CWD to return to the originating path.
$CWD = $PWD.Path

## Paths to config files in repository
[string]$RepoConfigDir = (Join-Path -Path $CWD -ChildPath (Join-Path -Path "config" -ChildPath $Config))
[string]$RepoHyperJsFile = (Join-Path -Path $RepoConfigDir -ChildPath "hyper.js")

## Paths to config files on host
[string]$HyperConfigDir = "$env:APPDATA\Hyper"
[string]$HyperJsFile = (Join-Path -Path $HyperConfigDir -ChildPath ".hyper.js")

## Check if hyper terminal is installed
if ( -Not ( Get-Command hyper -ErrorAction SilentlyContinue ) ) {
    Write-Warning "Hyper terminal is not installed, or was not found in the PATH. Install Hyper and try again."
    exit 1
}

## Check that hyper config directory exists on host
if ( -Not ( Test-Path -Path $HyperConfigDir ) ) {
    Write-Warning "Hyper configuration directory not found at expected path: $HyperConfigDir"
    exit 1
}

## Check that -Config value exists in config directory
if ( -Not ( Test-Path -Path $RepoConfigDir ) ) {
    Write-Warning "Configuration directory '$Config' not found at expected path: $RepoConfigDir"
    exit 1
}

## Check that repo hyper.js file exists
if ( -Not ( Test-Path -Path $RepoHyperJsFile ) ) {
    Write-Warning "Hyper app configuration file not found at expected path: $RepoHyperJsFile"
    exit 1
}
else {
    Write-Host "[Repository] Hyper app configuration file found at: $RepoHyperJsFile" -ForegroundColor Green
}

## Check that host .hyper.js exists
if ( -Not ( Test-Path -Path $HyperJsFile ) ) {
    Write-Warning "[Host] Hyper app configuration file not found at expected path: $HyperJsFile"
    exit 1
}
else {
    Write-Host "[Host] Hyper app configuration file found at: $HyperJsFile" -ForegroundColor Green
}

function Test-IsAdmin {
    ## Check if the current process is running with elevated privileges (admin rights)
    $isAdmin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    return $isAdmin
}

function Invoke-AsAdmin {
    param (
        [string]$Command
    )

    # Check if the script is running as admin
    $isAdmin = [bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        # Prompt to run as administrator if not already running as admin
        $arguments = "-Command `"& {$command}`""
        Write-Debug "Running command: Start-Process powershell -ArgumentList $($arguments) -Verb RunAs"

        try {
            Start-Process powershell -ArgumentList $arguments -Verb RunAs
            return $true  # Indicate that the script was elevated and the command will run
        }
        catch {
            Write-Error "Error executing command as admin. Details: $($_.Exception.Message)"
        }
    }
    else {
        # If already running as admin, execute the command
        Invoke-Expression $command
        return $false  # Indicate that the command was run without elevation
    }
}

function New-HyperConfigSymlink {
    Param(
        [Parameter(Mandatory = $true, HelpMessage = "Path to source file to symlink")]
        [string]$Src,
        [Parameter(Mandatory = $true, HelpMessage = "Path to destination file to symlink")]
        [string]$Dst
    )

    if ( -Not ( Test-Path -Path $Src ) ) {
        Write-Error "Source file not found at expected path: $Src"
        exit 1
    }

    ## Check if destination file exists and is a symlink
    if ( -Not ( Test-Path -Path $Dst ) ) {
        Write-Warning "Destination file not found at expected path: $Dst"
    }
    else {
        Write-Debug "Testing if path $($Dst) is a symlink"
        ## Check if path is directory or junction
        $Item = Get-Item $Dst

        ## Check if path is a junction
        If ( $Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint ) {
            Write-Warning "Path is already a junction: $($Dst)"
            return $True
        }

        ## Path is a regular directory
        Write-Warning "Path already exists: $Dst. Moving to $($Dst).bak"
        If ( Test-Path "$($Dst).bak" ) { 
            Write-Warning "$($Dst).bak already exists. Overwriting backup."
            try {
                Remove-Item -Recurse "$($Dst).bak"
            }
            catch {
                Write-Error "Error removing existing backup (continuing anyway). Details: $($_.Exception.Message)"
            }
        }

        ## Move existing destination to .bak
        try {
            Move-Item -Path $Dst -Destination "$($Dst).bak"
        }
        catch {
            Write-Error "Error moving existing destination to .bak (continuing anyway). Details: $($_.Exception.Message)"
        }
    }

    Write-Host "Creating symlink from $Src to $Dst"

    $SymlinkCommand = "New-Item -Path $Dst -ItemType SymbolicLink -Target $Src"

    If ( -Not ( Test-IsAdmin ) ) {
        Write-Warning "Script was not run as administrator. Running symlink command as administrator."

        try {
            Invoke-AsAdmin -Command "$($SymlinkCommand)"
        }
        catch {
            Write-Error "Error creating symlink from $Src to $Dst. Details: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        try {
            Invoke-Expression $SymlinkCommand
        }
        catch {
            Write-Error "Error creating symlink from $Src to $Dst. Details: $($_.Exception.Message)"
            exit 1
        }
    }

    Write-Host "Symlink created from $Src to $Dst" -ForegroundColor Green
}

## Create symlinks

$HyperAppConfigSymlinkCreated = (New-HyperConfigSymlink -Src $RepoHyperJsFile -Dst $HyperJsFile)

if ( -Not $HyperAppConfigSymlinkCreated ) {
    Write-Error "Error creating symlink from $RepoHyperJsFile to $HyperJsFile. Details: $($_.Exception.Message)"
}
