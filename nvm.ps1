<#
Copyright 2017 Nicolas Noble

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

if ((-not (Get-Variable PSVersionTable -Scope Global -ErrorAction SilentlyContinue)) -or ($PSVersionTable.PSVersion.Major -lt 5)) {
    Write-Host "Your version of PowerShell is too old."
    Write-Host "nvm-ps requires a least PowerShell 5.0"
    Write-Host "You need to download and install Windows Management Framework 5.0+"
    exit
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-AbsolutePath($Path) {
    $Path = [System.IO.Path]::Combine(((pwd).path), ($Path))
    $Path = [System.IO.Path]::GetFullPath($Path)
    return $Path.TrimEnd("\/")
}

# Adds a path to the user's PATH environment variable.
function Add-Path($Path) {
    $UserPath = [environment]::GetEnvironmentVariable("PATH", "User")
    if ($UserPath -eq $NULL) {
        return
    }
    foreach ($Fragment in $UserPath.split(";")) {
        if ($Fragment -like $Path) {
            return
        }
    }
    [environment]::SetEnvironmentVariable("PATH", $UserPath + ";" + $Path, "User")
}

function MkDir-p($Path) {
    $FullPath = "\\?\" + $Path
    if (-not (Test-Path -Path $FullPath)) {
        New-Item -ItemType directory -Path $FullPath | Out-Null
    }
}

function Usage() {
    Write-Host "Usage:" 
    Write-Host "  nvm install <version>"
    Write-Host "  nvm use <version>"
    Write-Host "  nvm ls"
    Write-Host "  nvm ls-remote"
    Write-Host "  nvm version"
    Write-Host "  nvm self-install"

    exit
}

function Download-Index($Path) {
    $IndexFile = $Path + "/index.json"
    $FullURL = $NodeBaseURL + "/index.json"
    Invoke-WebRequest -ContentType "application/octet-stream" -Uri $FullURL -OutFile $IndexFile
}

function Sort-Versions($Data) {
    $Versions = @()
    ForEach ($Version in $Data) {
        [Int]$Major, [Int]$Minor, [Int]$Patch = $Version.version.TrimStart("v").Split(".")
        $Key = $Major * 10000 + $Minor * 100 + $Patch
        $Version | Add-Member Key $Key
        $Versions += $Version
    }
    return $Versions | Sort-Object -Descending -Property Key
}

# Downloads the index, and assign a version number to it that can be easily sorted.
# This way doing npm install 8 will install the latest version of 8.
function Load-Index($Path) {
    $IndexFile = $Path + "/index.json"
    if (-not (Test-Path $IndexFile)) {
        Download-Index($Path)
    }
    $RawData = (Get-Content $IndexFile) -join "`n" | ConvertFrom-Json
    return Sort-Versions $RawData
}

function New-TempDir {
    $TempDir = [System.IO.Path]::GetTempPath()
    [string]$Random = [System.Guid]::NewGuid()
    $TempDir = Join-Path $TempDir $Random
    New-Item -ItemType Directory -Path $TempDir | Out-Null
    return $TempDir
}

# Downloads the list of node releases, and attempts to find a version that matches the
# one specified by $Version. Returns a structure with the information for that specific
# version. The index is this one: https://nodejs.org/download/release/index.json
function Locate-Version($Version) {
    $VersionString = "v" + $Version
    $Version = $NULL
    For ($run = 0; $run -le 1; $run++) {
        $Index = Load-Index $cwd
        ForEach ($Iterator in $Index) {
            if ($Iterator.version.StartsWith($VersionString)) {
                ForEach ($FileIterator in $Iterator.files) {
                    if ($HasX64) {
                        if ($FileIterator -eq "win-x64-exe") {
                            $Version = $Iterator
                            $File = "win-x64"
                            break
                        }
                    }
                    if ($FileIterator -eq "win-x86-exe") {
                        $Version = $Iterator
                        $File = "win-x86"
                        break
                    }
                }
                if ($Version -ne $NULL) {
                    break
                }
            }
        }
        if ($Version -eq $NULL) {
            Download-Index $cwd
        } else {
            $Version | Add-Member File $File
            return $Version
        }
    }

    Write-Host "NodeJS version $VersionString not found"
    return $NULL
}

# Will change the symlink to another version of node. We're currently not checking if that
# version is indeed installed. TODO: check if the version is actually there.
function Use($Version) {
    [string]$Version = $Version
    if (!$Version.StartsWith("v")) {
        $Installed = Get-ChildItem $VersionsPath | Select-Object Name
        $Versions = @()
        ForEach ($Iterator in $Installed) {
            $Object = New-Object PSObject
            $Object | Add-Member version $Iterator.Name
            $Versions += $Object
        }
        $Versions = Sort-Versions $Versions
        $Version = "v" + $Version
        ForEach ($Iterator in $Versions) {
            if ($Iterator.version.StartsWith($Version)) {
                $Version = $Iterator.version
                break
            }
        }
    }
    $VersionPath = $VersionsPath + "/" + $Version
    if (Test-Path -Path $symlink) {
        Remove-Item -Path $symlink -Recurse -Force
    }
    New-Item -Force -Path $symlink -ItemType Junction -Value $VersionPath
}

# Will attempt to download and install the version of node specified by $Version.
function Install($Version) {
    $Version = Locate-Version $Version
    if ($Version -eq $NULL) {
        return $FALSE
    }

    $NodeURL = $NodeBaseURL + $Version.version + "/" + $Version.File + "/node.exe"
    $OutputDir = $cwd + "/versions/" + $Version.version
    MkDir-p $OutputDir
    $Output = $OutputDir + "/node.exe"
    $NodeRuntime = $Output
    Write-Host "Downloading node.exe..."
    Invoke-WebRequest -ContentType "application/octet-stream" -Uri $NodeURL -OutFile $Output

    $NPMURL = $NPMBaseURL + "v" + $Version.npm + ".zip"
    $TempDir = New-TempDir
    $Output = $TempDir + "/npm.zip"
    Write-Host "Downloading npm.zip..."
    Invoke-WebRequest -ContentType "application/octet-stream" -Uri $NPMURL -OutFile $Output

    Write-Host "Extracting npm bootstrap..."
    $ZipFile = [System.IO.Compression.ZipFile]::OpenRead($Output)
    $NPMDir = $OutputDir + "/node_modules/npm-bootstrap"

    # That extraction method may seem a bit weird, but it's to counter the effects of the
    # built-in Zip code not able to handle paths that are too long. So we extract each files
    # manually to a temporary directory, then we move it where it's supposed to go using
    # the \\?\ prefix that can handle long filenames.
    ForEach ($Entry in $ZipFile.Entries) {
        if ($Entry.FullName.EndsWith("/") -or $Entry.Fullname.EndsWith("\")) {
            continue
        }
        $TempFile = [System.IO.Path]::GetTempFileName()
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $TempFile, $true)
        $TrimmedName = $Entry.FullName.SubString(("npm-" + $Version.npm + "/").Length)
        $DestPath = $NPMDir + "/" + $TrimmedName
        $DestDir = Split-Path $DestPath
        MkDir-p $DestDir
        Move-Item -Force -Path $TempFile -Destination ("\\?\" + $DestPath)
    }
    $ZipFile.Dispose()
    Remove-Item -Path $Output -Force | Out-Null
    Remove-Item -Path $TempDir -Force | Out-Null
    $VersionString = $Version.version

    $NPMCLI = $NPMDir + "/bin/npm-cli.js"
    $NPMVersion = $Version.npm

    Write-Host "Adjusting npm bootstrap..."
    $WorkspacesConfig = $NPMDir + "/workspaces/config"
    if (Test-Path -Path $WorkspacesConfig) {
        $DestDir = $NPMDir + "/node_modules/@npmcli"
        Copy-Item -Recurse -Force -Path ("\\?\" + $WorkspacesConfig) -Destination ("\\?\" + $DestDir)
    }
    $WorkspacesLibnpmfund = $NPMDir + "/workspaces/libnpmfund"
    if (Test-Path -Path $WorkspacesLibnpmfund) {
        $DestDir = $NPMDir + "/node_modules"
        Copy-Item -Recurse -Force -Path ("\\?\" + $WorkspacesLibnpmfund) -Destination ("\\?\" + $DestDir)
    }
    $WorkspacesArborist = $NPMDir + "/workspaces/arborist"
    if (Test-Path -Path $WorkspacesArborist) {
        $DestDir = $NPMDir + "/node_modules/@npmcli"
        Copy-Item -Recurse -Force -Path ("\\?\" + $WorkspacesArborist) -Destination ("\\?\" + $DestDir)
    }

    Write-Host "Re-installing npm with itself..."
    Invoke-Expression -Command "$NodeRuntime $NPMCLI install -g npm@$NPMVersion"

    Write-Host "Removing bootstrap..."
    Remove-Item ("\\?\" + $NPMDir) -Force -Recurse

    Write-Host "Done - NodeJS $VersionString installed."
    Use $VersionString
    return $TRUE
}

$dest = Get-AbsolutePath ([Environment]::GetFolderPath('ApplicationData') + "/nvm-ps")
$me = $MyInvocation.Value.MyCommand
if ($me -eq $NULL) {
    $me = $MyInvocation.InvocationName
}
$HasX64 = [Environment]::Is64BitOperatingSystem
$NodeBaseURL = "https://nodejs.org/download/release/"
$NPMBaseURL = "https://github.com/npm/cli/archive/"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$MyURI = "https://raw.githubusercontent.com/grumpycoders/nvm-ps/master/nvm.ps1"

# If we're invoked from the installer shortcut, we're going to redownload ourselves
# and install ourselves. That's a bit redundant, but, sure.
if ($me -eq "&") {
    $me = [System.IO.Path]::GetTempFileName()
    Invoke-WebRequest -Uri $MyURI -OutFile $me
    $cmd = "self-install"
    $symlink = $dest + "/nodejs"
    $VersionsPath = $dest + "/versions"
} else {
    $cwd = Get-AbsolutePath (Split-Path $me)
    $symlink = $cwd + "/nodejs"
    $VersionsPath = $cwd + "/versions"

    $cmd = $args[0]
    if ($args.Length -eq 0) {
        Usage
        return
    }
}

# Globals for PowerShell behavior
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "stop"

switch ($cmd) {
    "install" {
        if ($args[1] -eq $NULL) {
            Usage
        }
        Install $args[1] | Out-Null
    }
    "use" {
        if ($args[1] -eq $NULL) {
            Usage
        }
        Use $args[1] | Out-Null
    }
    "ls" {
        Get-ChildItem $VersionsPath | Select-Object Name
    }
    "ls-remote" {
        Download-Index $cwd
        if ($args[1] -eq $NULL) {
            Load-Index $cwd | Sort-Object -Property Key | Select-Object version
        } else {
            Load-Index $cwd | Sort-Object -Property Key | Where-Object {$_.lts} | Select-Object version
        }
    }
    "version" {
        Write-Host "v0.1.0"
    }
    "self-install" {
        if ($cwd -like $dest) {
            Write-Host "This is already installed."
        } else {
            Write-Host "Installing..."
            MkDir-p $dest
            MkDir-p $VersionsPath
            Copy-Item -Force $me $dest/nvm.ps1
            Set-Content -Path $dest/nvm.cmd -Value "@PowerShell -ExecutionPolicy Unrestricted %~dp0/nvm.ps1 %*"
            Add-Path $dest
            Add-Path $symlink
            Write-Host "Done. Open a new console and type nvm."
        }
    }
    default {
        Write-Host "Unknown command $cmd"
        Usage
    }
}
