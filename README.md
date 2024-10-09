# Remote Deployment Script

This script automates the deployment of Docker images to a remote target. It builds the Docker images locally, tags them, creates an SSH tunnel to the target, pushes the images, and then deploys them using Docker Compose on the target.

## Requirements

- PowerShell
- Docker and Docker Compose installed locally
- SSH access to the target server

## Usage

```powershell
remote-deploy -TargetHost <TargetHost> [-TargetUser <TargetUser>] [-TargetPort <TargetPort>] [-Debug] [-Help]
```

### Parameters

- `-TargetHost` (required): The target host for deployment.
- `-TargetUser` (optional, default: root): The target user for SSH connection.
- `-TargetPort` (optional, default: 5000): The port for the SSH tunnel and registry.
- `-Debug` (optional): Enable debug messages.
- `-Help` (optional): Display help message.

### Example

```powershell
remote-deploy 192.168.1.100
```

```powershell
remote-deploy -TargetHost 192.168.1.100 -TargetUser root -TargetPort 5000 -Debug
```

## Installing Globally

To make this script available system-wide, you can create a symbolic link to it in a directory that is in your system's PATH.

### Steps to Install Globally

1. Open a PowerShell prompt as an administrator.
2. Create a symbolic link to the script in a directory that is in your system's PATH. For example:

   ```powershell
   New-Item -ItemType SymbolicLink -Path "C:\Windows\System32\remote-deploy.ps1" -Target ".\remote-deploy.ps1"
   ```

After these steps, you can run `remote-deploy` from any directory in PowerShell.

## Notes

- Ensure that Docker is running before executing the script.
- You must have SSH access to the target server.
- The script tags and pushes Docker images based on the configuration in the `docker-compose.yaml` file.

## Troubleshooting

- If the script fails to connect to the target host, verify the SSH connection and ensure the target host is reachable.
- Use the `-Debug` parameter to see more detailed messages about the script's progress and any issues.
