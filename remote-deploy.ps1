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

# Step 1: Build Docker images
Write-DebugMessage "Building Docker images..."
docker compose build

# Step 2: Get local device IP
Write-DebugMessage "Getting local device IP..."
try {
    $TARGET_SUBNET = ($TargetHost -split '\.')[0..2] -join '.'
    $LOCAL_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -like "$TARGET_SUBNET.*" }).IPAddress | Select-Object -First 1
    if (-not $LOCAL_IP) {
        throw "No suitable IP address found in the same subnet as the target host."
    }
    Write-DebugMessage "Local IP: $LOCAL_IP"
} catch {
    Write-Host "Error: $_"
    exit 1
}

# Step 3: Tag images specified in compose file with local IP and port
Write-DebugMessage "Tagging images specified in compose file with local IP and port $TargetPort..."
$composeFile = "docker-compose.yaml"
$images = (docker compose -f $composeFile config | Select-String -Pattern "image:" | ForEach-Object { ($_ -split "image:")[1].Trim() }) | Where-Object { $_ -ne "" }
$taggedImages = @()
foreach ($image in $images) {
    $taggedImage = "$LOCAL_IP`:$TargetPort/$image"
    Write-DebugMessage "Tagging image: $image as $taggedImage"
    docker tag $image $taggedImage
    $taggedImages += $taggedImage
}

# Step 4: Establish SSH tunnel to target
Write-DebugMessage "Establishing SSH tunnel to target..."
try {
    $sshProcess = Start-Process -NoNewWindow -PassThru -FilePath "ssh" -ArgumentList "-f -N -L *:$TargetPort`:localhost:$TargetPort $TargetUser@$TargetHost" -ErrorAction Stop
    Write-DebugMessage "SSH tunnel established successfully."
} catch {
    Write-Host "Error: Failed to establish SSH tunnel to $TargetUser@$TargetHost"
    exit 1
}

try {
    # Step 5: Test if local IP is reachable on port
    Write-DebugMessage "Testing if local IP is reachable on port $TargetPort..."
    Invoke-WebRequest -Uri "http://localhost:$TargetPort/v2/" -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-DebugMessage "Local IP is reachable on port $TargetPort."

    # Step 6: Push tagged images to local registry
    Write-DebugMessage "Pushing tagged images to local registry..."
    foreach ($image in $taggedImages) {
        Write-DebugMessage "Pushing image: $image"
        docker push $image
    }

    # Step 7: Verify if image exists in repository
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

    # Step 8: Deploy using docker compose on target
    Write-DebugMessage "Deploying using docker compose on target..."
    $dryRunFlag = if ($DryRun) { "--dry-run" } else { "" }
    docker --host "ssh://$TargetUser@$TargetHost" compose --file "./remote-compose.yaml" up -d $dryRunFlag

    # Step 9: Prune unused Docker resources on target (skip if dry run)
    if (-not $DryRun) {
        Write-DebugMessage "Pruning unused Docker resources on target..."
        docker --host "ssh://$TargetUser@$TargetHost" system prune -a -f
        Write-DebugMessage "Docker system prune completed on target."
    }
} finally {
    # Step 10: Cleanup SSH tunnel
    Write-DebugMessage "Cleaning up SSH tunnel..."
    if ($sshProcess -and !$sshProcess.HasExited) {
        Stop-Process -Id $sshProcess.Id -Force
        Write-DebugMessage "SSH tunnel closed successfully."
    }

    # Untag/remove the images it tagged in this script
    Write-DebugMessage "Removing tagged images..."
    foreach ($image in $taggedImages) {
        Write-DebugMessage "Removing image: $image"
        docker rmi $image -f
    }
}

Write-Host "Deployment completed."
