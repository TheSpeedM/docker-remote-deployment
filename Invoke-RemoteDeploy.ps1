param(
    [string]$TargetHost,
    [string]$TargetUser = "root",
    [int]$TargetPort = 5000,
    [string]$RemotePath = "/etc/docker-remote-deploy",
    [string[]]$FilesToCopy = @(),
    [switch]$Debug = $false,
    [switch]$Help = $false,
    [switch]$DryRun = $false
)

if ($Help -or -not $TargetHost) {
    Write-Host "Usage: remote-deploy -TargetHost <TargetHost> [-RemotePath <RemotePath>] [-TargetUser <TargetUser>] [-TargetPort <TargetPort>] [-FilesToCopy <FilesToCopy>] [-Debug] [-DryRun] [-Help]"
    Write-Host "- TargetHost: The target host for deployment (required)."
    Write-Host "- RemotePath: The path on the remote machine to copy files from (default: /etc/docker-remote-deploy)."
    Write-Host "- TargetUser: The target user for SSH connection (default: root)."
    Write-Host "- TargetPort: The port for the SSH tunnel and registry (default: 5000)."
    Write-Host "- FilesToCopy: List of local files to copy to the .docker-remote-deploy folder (default: none)."
    Write-Host "- Debug: Enable debug messages."
    Write-Host "- DryRun: Perform a dry run without making actual changes."
    Write-Host "- Help: Display this help message."
    exit 0
}

function Write-DebugMessage {
    param([string]$Message)
    if ($Debug) {
        Write-Host "[DEBUG] $Message"
    }
}

function New-DockerImages {
    Write-DebugMessage "Building Docker images..."
    try {
        docker compose build
        Write-DebugMessage "Docker images built successfully."
    } catch {
        Write-Host "Error: Failed to build Docker images. Ensure Docker is running and properly configured."
        exit 1
    }
}

function Get-LocalIPAddress {
    Write-DebugMessage "Getting local device IP..."
    try {
        $LOCAL_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.InterfaceAlias -notmatch 'Loopback' -and 
            $_.InterfaceAlias -notmatch 'vEthernet' -and 
            $_.InterfaceAlias -notmatch 'Teredo' -and 
            $_.InterfaceAlias -notmatch 'Wi-Fi Direct' -and 
            $_.InterfaceAlias -notmatch 'Bluetooth' -and 
            $_.InterfaceAlias -notmatch 'Docker' -and 
            $_.InterfaceAlias -notmatch 'VirtualBox' -and 
            $_.IPAddress -notlike '169.254.*'
        }).IPAddress | Select-Object -First 1

        if (-not $LOCAL_IP) {
            throw "No suitable IP address found."
        }

        Write-DebugMessage "Local IP: $LOCAL_IP"
        return $LOCAL_IP
    } catch {
        Write-Host "Error: $_"
        exit 1
    }
}

function Add-DockerImageTags {
    param($LOCAL_IP)
    Write-DebugMessage "Tagging images specified in compose file with local IP and port $TargetPort..."
    $images = (docker compose config | Select-String -Pattern "image:" | ForEach-Object { ($_ -split "image:")[1].Trim() }) | Where-Object { $_ -ne "" }
    $taggedImages = @()
    foreach ($image in $images) {
        $taggedImage = "$LOCAL_IP`:$TargetPort/$image"
        Write-DebugMessage "Tagging image: $image as $taggedImage"
        docker tag $image $taggedImage
        $taggedImages += $taggedImage
    }
    return $taggedImages
}

function New-SSHTunnel {
    Write-DebugMessage "Establishing SSH tunnel to target..."
    try {
        $sshProcess = Start-Process -NoNewWindow -PassThru -FilePath "ssh" -ArgumentList "-f -N -L *:$TargetPort`:localhost:$TargetPort $TargetUser@$TargetHost" -ErrorAction Stop
        Write-DebugMessage "SSH tunnel established successfully."
        return $sshProcess
    } catch {
        Write-Host "Error: Failed to establish SSH tunnel to $TargetUser@$TargetHost"
        exit 1
    }
}

function Test-LocalIPConnectivity {
    Write-DebugMessage "Testing if local IP is reachable on port $TargetPort..."
    Invoke-WebRequest -Uri "http://localhost:$TargetPort/v2/" -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-DebugMessage "Local IP is reachable on port $TargetPort."
}

function Push-TaggedImages {
    param($taggedImages)
    Write-DebugMessage "Pushing tagged images to local registry..."
    foreach ($image in $taggedImages) {
        Write-DebugMessage "Pushing image: $image"
        docker push $image
    }
}

function Test-ImagesInRepository {
    param($taggedImages)
    Write-DebugMessage "Verifying if images exist in repository..."
    foreach ($image in $taggedImages) {
        try {
            $repositoryName = ($image -split '/')[1] -split ':' | Select-Object -First 1
            Invoke-WebRequest -Uri "http://localhost:$TargetPort/v2/$repositoryName/tags/list" -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-DebugMessage "Image $image found in repository."
        } catch {
            Write-Host "Image $image not found in repository"
            exit 1
        }
    }
}

function Copy-FilesFromRemote {
    Write-DebugMessage "Copying files from remote to local..."
    try {
        # Using SCP to copy files from remote to local
        $remotePath = "$TargetUser@$TargetHost`:$RemotePath/."
        $localPath = ".\.docker-remote-deploy"

        # Create local directory if it doesn't exist
        if (-not (Test-Path -Path $localPath)) {
            New-Item -ItemType Directory -Path $localPath -Force | Out-Null
        }

        # Execute SCP command
        $scpCommand = "scp -r $remotePath $localPath"
        Write-DebugMessage "Executing: $scpCommand"
        Invoke-Expression $scpCommand

        # Copy specified local files to the .docker-remote-deploy folder
        foreach ($file in $FilesToCopy) {
            if (Test-Path -Path $file) {
                Copy-Item -Path $file -Destination $localPath -Force
                Write-DebugMessage "Copied file: $file to $localPath"
            } else {
                Write-Host "Warning: File $file not found. Skipping."
            }
        }

        # Always copy remote-compose.yaml from the current directory to the .docker-remote-deploy folder
        if (Test-Path -Path "./remote-compose.yaml") {
            Copy-Item -Path "./remote-compose.yaml" -Destination "$localPath/docker-compose.yaml" -Force
            Write-DebugMessage "Copied remote-compose.yaml to $localPath and renamed to docker-compose.yaml"
        } else {
            Write-Host "Warning: remote-compose.yaml not found in the current directory."
        }

        Set-Location -Path $localPath
        Write-DebugMessage "Changed directory to $localPath"
    } catch {
        Write-Host "Error: $_"
        exit 1
    }
}

function Remove-LocalDirectory {
    if (Test-Path -Path ".\.docker-remote-deploy") {
        Write-DebugMessage "Removing local directory .docker-remote-deploy..."
        try {
            # Remove the directory and its contents
            Remove-Item -Path ".\.docker-remote-deploy" -Recurse -Force
            Write-DebugMessage "Removed .docker-remote-deploy and all its contents."
        } catch {
            Write-Host "Error: $_"
            exit 1
        }
    }
}

function Start-DockerComposeDeploy {
    param($Path)
    $stackName = (Split-Path -Leaf ($Path).Path) -replace '[^a-zA-Z0-9_-]', ''  # Get the stack name from the parent directory

    Write-DebugMessage "Deploying $stackName using docker compose on target..."

    $dryRunFlag = if ($DryRun) { "--dry-run" } else { "" }
    docker --host "ssh://$TargetUser@$TargetHost" compose -p "$stackName" up -d $dryRunFlag
}

function Clear-DockerResources {
    if (-not $DryRun) {
        Write-DebugMessage "Pruning unused Docker resources on target..."
        docker --host "ssh://$TargetUser@$TargetHost" system prune -a -f
        Write-DebugMessage "Docker system prune completed on target."
    }
}

function Remove-SSHTunnel {
    param($sshProcess)
    Write-DebugMessage "Cleaning up SSH tunnel..."
    if ($sshProcess -and !$sshProcess.HasExited) {
        Stop-Process -Id $sshProcess.Id -Force
        Write-DebugMessage "SSH tunnel closed successfully."
    }
}

function Remove-TaggedImages {
    param($taggedImages)
    Write-DebugMessage "Removing tagged images..."
    foreach ($image in $taggedImages) {
        Write-DebugMessage "Removing image: $image"
        docker rmi $image -f
    }
}

# Main script execution
$originalLocation = Get-Location
New-DockerImages
$LOCAL_IP = Get-LocalIPAddress
$taggedImages = Add-DockerImageTags -LOCAL_IP $LOCAL_IP
$sshProcess = New-SSHTunnel

try {
    Test-LocalIPConnectivity
    Push-TaggedImages -taggedImages $taggedImages
    Test-ImagesInRepository -taggedImages $taggedImages
    Copy-FilesFromRemote
    Start-DockerComposeDeploy -Path $originalLocation
    Clear-DockerResources
    Set-Location -Path $originalLocation
} finally {
    Remove-LocalDirectory
    Remove-SSHTunnel -sshProcess $sshProcess
    Remove-TaggedImages -taggedImages $taggedImages
}

Write-Host "Deployment completed."
