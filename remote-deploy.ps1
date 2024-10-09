param(
    [switch]$Debug
)

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
    $TARGET_HOST = "192.168.215.106"
    $TARGET_SUBNET = ($TARGET_HOST -split '\.')[0..2] -join '.'
    $LOCAL_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -like "$TARGET_SUBNET.*" }).IPAddress | Select-Object -First 1
    if (-not $LOCAL_IP) {
        throw "No suitable IP address found in the same subnet as the target host."
    }
    Write-DebugMessage "Local IP: $LOCAL_IP"
} catch {
    Write-Host "Error: $_"
    exit 1
}

# Step 3: Tag images specified in compose file with local IP and port 5000
Write-DebugMessage "Tagging images specified in compose file with local IP and port 5000..."
$composeFile = "docker-compose.yaml"
$images = (docker compose -f $composeFile config | Select-String -Pattern "image:" | ForEach-Object { ($_ -split "image:")[1].Trim() }) | Where-Object { $_ -ne "" }
foreach ($image in $images) {
    Write-DebugMessage "Tagging image: $image"
    docker tag $image "$LOCAL_IP`:5000/$image"
}

# Step 4: Establish SSH tunnel to target
Write-DebugMessage "Establishing SSH tunnel to target..."
$TARGET_USER = "root"
$TARGET_HOST = "192.168.215.106"
$TARGET_PORT = 5000
try {
    $sshProcess = Start-Process -NoNewWindow -PassThru -FilePath "ssh" -ArgumentList "-f -N -L *:$TARGET_PORT`:localhost:$TARGET_PORT $TARGET_USER@$TARGET_HOST" -ErrorAction Stop
    Write-DebugMessage "SSH tunnel established successfully."
} catch {
    Write-Host "Error: Failed to establish SSH tunnel to $TARGET_USER@$TARGET_HOST"
    exit 1
}

try {
    # Step 5: Test if local IP is reachable on port 5000
    Write-DebugMessage "Testing if local IP is reachable on port 5000..."
    Invoke-WebRequest -Uri "http://localhost:5000/v2/" -UseBasicParsing -ErrorAction Stop
    Write-DebugMessage "Local IP is reachable on port 5000."

    # Step 6: Push tagged images to local registry
    Write-DebugMessage "Pushing tagged images to local registry..."
    $taggedImages = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -like "$LOCAL_IP`:5000*" }
    foreach ($image in $taggedImages) {
        Write-DebugMessage "Pushing image: $image"
        docker push $image
    }

    # Step 7: Verify if image exists in repository
    Write-DebugMessage "Verifying if images exist in repository..."
    foreach ($image in $taggedImages) {
        try {
            $repositoryName = ($image -split '/')[1] -split ':' | Select-Object -First 1
            Invoke-WebRequest -Uri "http://localhost:5000/v2/$repositoryName/tags/list" -UseBasicParsing -ErrorAction Stop
            Write-DebugMessage "Image $image found in repository."
        } catch {
            Write-Host "Image $image not found in repository"
            exit 1
        }
    }

    # Step 8: Deploy using docker compose on target
    Write-DebugMessage "Deploying using docker compose on target..."
    docker --host "ssh://$TARGET_USER@$TARGET_HOST" compose --file "./remote-compose.yaml" up -d
} finally {
    # Step 9: Cleanup SSH tunnel
    Write-DebugMessage "Cleaning up SSH tunnel..."
    if ($sshProcess -and !$sshProcess.HasExited) {
        Stop-Process -Id $sshProcess.Id -Force
        Write-DebugMessage "SSH tunnel closed successfully."
    }
}

Write-Host "Deployment completed."
