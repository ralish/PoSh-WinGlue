Function Update-GitRepository {
    [CmdletBinding()]

    # The path to the Registry keys containing potential Git installation details
    $GitInstallRegPaths = @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1', # Native bitness
                            'HKCU:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1', # x86 on x64
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1', # Native bitness
                            'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1') # x86 on x64
    # The name of the Registry property that gives the installation location
    $GitInstallDirProp = 'InstallLocation'

    # Ensure that any errors we receive are considered fatal
    $ErrorActionPreference = 'Stop'

    Function Test-GitInstalled {
        Write-Verbose 'Testing Git is installed...'

        foreach ($GitInstallRegPath in $GitInstallRegPaths) {
            if (Test-Path $GitInstallRegPath -PathType Container) {
                $GitPath = (Get-ItemProperty -Path $GitInstallRegPath).$GitInstallDirProp
                break
            }
        }

        if (!$GitPath) {
            Write-Error 'Git does not appear to be installed on this system.'
        }

        if (!(Test-Path $GitPath -PathType Container)) {
            Write-Error 'The Git installation on this system appears to be damaged.'
        }

        # Amend the PATH variable to include the full set of Git utilities
        $Env:Path="$Env:Path;$GitPath\bin"

        # Setup the HOME environment variable needed by SSH (this caused some serious pain)
        #
        # More pain: if running as a Scheduled Task the user profile of the running account
        # may not yet be loaded on Windows 8 or Server 2012 and newer. As a result, the
        # USERPROFILE environment variable will point to the Default user profile. We can
        # seemingly work around this by using GetFolderPath() from the Environment class.
        #
        # See: https://support.microsoft.com/en-us/kb/2968540
        $Env:HOME = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
    }

    Function Test-GitRepository {
        Write-Verbose 'Testing current directory is a Git repository...'

        git rev-parse --git-dir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'The current directory is not part of a Git repository.'
        }
    }

    Function Test-Windows64bit {
        Write-Verbose 'Testing if we are running on 64-bit Windows...'

        if ((Get-WmiObject 'Win32_OperatingSystem').OSArchitecture -ne '64-bit') {
            Write-Error 'We only support running on 64-bit systems. Seriously, it is time to upgrade already!'
        }
    }

    Function Update-GitRepository {
        Write-Verbose 'Updating the Git repository...'

        git add --all
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Something went wrong updating the Git index with all changes."
        }

        # Check if the index is dirty indicating we have something to commit
        git diff-index --quiet --cached HEAD
        if ($LASTEXITCODE -ne 0) {
            $GitCommitDate = Get-Date -UFormat "%d/%m/%Y"
            git commit -m "Changes for $GitCommitDate"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Something went wrong committing all changes in the Git index."
            }
        }

        git pull
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Something went wrong pulling from the Git repository."
        }

        git push
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Something went wrong pushing to the Git repository."
        }
    }

    # Although technically we don't need x64 we have only tested on it
    Test-Windows64bit

    # Check Git is installed on the system and setup the environment
    Test-GitInstalled

    # Check we're currently operating within a Git repository
    Test-GitRepository

    # Commit all changes and update the Git repository
    Update-GitRepository
}
