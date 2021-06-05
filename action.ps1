#Requires -Version 7.0 -RunAsAdministrator
#------------------------------------------------------------------------------
# FILE:         action.ps1
# CONTRIBUTOR:  Jeff Lill
# COPYRIGHT:    Copyright (c) 2005-2021 by neonFORGE LLC.  All rights reserved.
#
# The contents of this repository are for private use by neonFORGE, LLC. and may not be
# divulged or used for any purpose by other organizations or individuals without a
# formal written and signed agreement with neonFORGE, LLC.

# Verify that we're running on a properly configured neonFORGE GitHub runner 
# and import the deployment and action scripts from neonCLOUD.

# NOTE: This assumes that the required [$NC_ROOT/Powershell/*.ps1] files
#       in the current clone of the repo on the runner are up-to-date
#       enough to be able to obtain secrets and use GitHub Action functions.
#       If this is not the case, you'll have to manually pull the repo 
#       first on the runner.

$nfRoot = $env:NF_ROOT
$ncRoot = $env:NC_ROOT

if ([System.String]::IsNullOrEmpty($ncRoot) -or ![System.IO.Directory]::Exists($ncRoot))
{
    throw "Runner Config: neonCLOUD repo is not present."
}

$ncPowershell = [System.IO.Path]::Combine($ncRoot, "Powershell")

Push-Location $ncPowershell | Out-Null
. ./includes.ps1
Pop-Location | Out-Null

# Read the inputs

$images      = Get-ActionInput "images"      $true
$options     = Get-ActionInput "options"     $false
$buildLog    = Get-ActionInput "build-log"   $true
$parallelism = Get-ActionInput "parallelism" $true

if ([System.String]::IsNullOrWhitespace($images))
{
    throw "The [options] input is required."
}

try
{
    # Scan the [options] input

    $clean   = $options.Contains("clean")
    $public  = $options.Contains("public")
    $prune   = $options.Contains("prune")
    $publish = $options.Contains("publish")

    # Scan the [images] input to determine which containers we're building

    $all     = $images.Contains("all")
    $base    = $images.Contains("base")
    $layer   = $images.Contains("layer")
    $other   = $images.Contains("other")
    $service = $images.Contains("service")
    $test    = $images.Contains("test")

    # Configure the [$/neonKUBE/Images/publish.ps1] script options

    $allOption         = ""
    $baseOption        = ""
    $layerOption       = ""
    $otherOption       = ""
    $serviceOption     = ""
    $testOption        = ""
    $noPruneOption     = ""
    $noPushOption      = ""
    $parallelismOption = "-parallelism $parallelism"

    if ($all)
    {
        $allOption = "-all"
    }

    if ($base)
    {
        $allOption = "-base"
    }

    if ($layer)
    {
        $layerOption = "-layers"
    }

    if ($other)
    {
        $allOption = "-other"
    }

    if ($service)
    {
        $serviceOption = "-services"
    }

    if ($test)
    {
        $allOption = "-test"
    }

    if (!$prune)
    {
        $noPruneOption = "-noprune"
    }

    if (!$publish)
    {
        $noPushOption = "-nopush"
    }

    # Fetch the current branch and commit from git

    Push-Cwd $ncRoot | Out-Null

        $branch = $(& git branch --show-current).Trim()
        ThrowOnExitCode

        $commit = $(& git rev-parse HEAD).Trim()
        ThrowOnExitCode

    Pop-Cwd | Out-Null

    # Set default outputs

    Set-ActionOutput "success"          "true"
    Set-ActionOutput "build-log"        $buildLog
    Set-ActionOutput "build-branch"     $branch
    Set-ActionOutput "build-config"     "release"
    Set-ActionOutput "build-commit"     $commit
    Set-ActionOutput "build-commit-uri" "https://github.com/$env:GITHUB_REPOSITORY/commit/$buildCommit"
    Set-ActionOutput "build-issue-uri"  ""

    # Identify the target package registry organizations

    if ($branch.StartsWith("release-"))
    {
        $neonkubeRegistry = "neonkube"
    }
    else
    {
        $neonkubeRegistry = "neonkube-dev"
    }

    # Retrieve the current neonKUBE version

    $neonKUBE_Version = $(& "$nfRoot\ToolBin\neon-build" read-version "$nfRoot\Lib\Neon.Common\Build.cs" NeonKubeVersion)
    ThrowOnExitCode

    # Delete all existing neonKUBE containers with the current neonKUBE Version
    
    # NOTE: This means that it's not possible to work on multiple versions of 
    #       neonKUBE at the same time.  I don't think this will impact is anytime
    #       soon.  The fix would be to delete only images tagged with thye current
    #       neonKUBE version.

    # $todo(jefflill):
    #
    # Container delete isn't working right now:
    #
    #   https://github.com/nforgeio/neonCLOUD/issues/149
    #
    # Remove this line when it does work:

    $clean = $false

    if ($clean)
    {
        # $todo(jefflill):
        #
        # I think we should be removing the setup and base containers, not 
        # the neonKUBE ocntainers here, right?

        # Remove-GitHub-Container $neonkubeRegistry "*"
    }

    # Execute the build/publish script

    $scriptPath = [System.IO.Path]::Combine($ncRoot, "Images", "publish.ps1")

    Write-ActionOutput "Building container images"
    pwsh -File $scriptPath -NonInteractive $allOption $baseOption $layerOption $otherOption $serviceOption $testOption $noPruneOption $noPushOption $parallelismOption > $buildLog 2>&1
Log-DebugLine "*** build-neonkube-containers: 1"
    ThrowOnExitCode
Log-DebugLine "*** build-neonkube-containers: 1"

    #------------------------------------------------------
    # Make all of the public images public when requested 

    # $debug(jefflill): SetVisibility isn't working either:
    #
    #   https://github.com/nforgeio/neonCLOUD/issues/149

    $public = $false
    #------------------------------------------------------

    # Make all of the public images public when requested 

Log-DebugLine "*** build-neonkube-containers: 2"
    if ($publish -and $public)
    {
Log-DebugLine "*** build-neonkube-containers: 3"
        Write-ActionOutput "Making neonCLOUD images public"
Log-DebugLine "*** build-neonkube-containers: 4"
        Set-GitHub-Container-Visibility $neonkubeRegistry "*" public
Log-DebugLine "*** build-neonkube-containers: 5"
    }
}
catch
{
#-------------------------------
# $debug(jefflill): REMOVE THIS!
$e = $_
Log-DebugLine "*** build-neonkube-containers: 6"
Log-DebugLine "*** build-neonkube-containers: 7: error: $e.Exception.message"
Log-DebugLine "*** build-neonkube-containers: 8: stack trace"
Log-DebugLine $e.ScriptStackTrace
#-------------------------------
    # Write-ActionException $_
    Set-ActionOutput "success" "false"
}
