param(
    [string]$TargetHost,
    [string]$TargetUser = "root",
    [int]$TargetPort = 5000,
    [switch]$Debug = $false,
    [switch]$Help = $false,
    [switch]$DryRun = $false
)

if ($Help -or -not $TargetHost) {
    Write-Host "Usage: remote-deploy -TargetHost <TargetHost> [-TargetUser <TargetUser>] [-TargetPort <TargetPort>] [-Debug] [-DryRun] [-Help]"
    Write-Host "- TargetHost: The target host for deployment (required)."
    Write-Host "- TargetUser: The target user for SSH connection (default: root)."
    Write-Host "- TargetPort: The port for the SSH tunnel and registry (default: 5000)."
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
        $buildOutput = docker compose build 2>&1
        if ($buildOutput -match "The system cannot find the file specified." -or
            $buildOutput -match "error during connect") {
            throw "Docker is not running or improperly configured."
        }
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

function Start-DockerComposeDeploy {
    Write-DebugMessage "Deploying using docker compose on target..."
    $dryRunFlag = if ($DryRun) { "--dry-run" } else { "" }
    docker --host "ssh://$TargetUser@$TargetHost" compose --file "./remote-compose.yaml" up -d $dryRunFlag
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
New-DockerImages
$LOCAL_IP = Get-LocalIPAddress
$taggedImages = Add-DockerImageTags -LOCAL_IP $LOCAL_IP
$sshProcess = New-SSHTunnel

try {
    Test-LocalIPConnectivity
    Push-TaggedImages -taggedImages $taggedImages
    Test-ImagesInRepository -taggedImages $taggedImages
    Start-DockerComposeDeploy
    Clear-DockerResources
} finally {
    Remove-SSHTunnel -sshProcess $sshProcess
    Remove-TaggedImages -taggedImages $taggedImages
}

Write-Host "Deployment completed."
