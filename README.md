# Remote Deployment Script

This script automates the deployment of Docker images to a remote target. It builds the Docker images locally, tags them, creates an SSH tunnel to the target, pushes the images, and then deploys them using Docker Compose on the target.

The goal of this script is to ease the deployment of docker containers on a remote server that doesn't have access to the internet (can't pull images from the Docker Hub).

## Requirements

- PowerShell
- Docker and Docker Compose installed locally
- Docker and Docker Compose installed on the target server
- SSH access to the target server

## Setup

### Setting up the Docker Registry on the Remote Machine

To set up a Docker registry on the remote machine, you can run the following command:

```bash
docker run -d -p 5000:5000 --restart=always --name <INSERT NAME> registry:2
```

This command will run the Docker registry on port 5000. Make sure to replace `<INSERT NAME>` with a suitable name for your container.

If you want to store the Docker images on a separate drive with more space, you can create a volume and mount it to the registry container. For example:

```bash
docker run -d -p 5000:5000 --restart=always --name <INSERT NAME> -v /path/to/large/drive:/var/lib/registry registry:2
```

This command mounts the directory `/path/to/large/drive` to `/var/lib/registry` inside the container, ensuring that the images are stored on the larger drive.

### Setting up SSH keys for seamless access

[Please follow this guide about exchanging SSH keys for passwordless SSH entry.](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)

### Add a remote-compose file

The `remote-deploy`-utility requires there to be a file in the directory (next to the compose) called `remote-compose.yaml`. This file is used for remote deployment.

`remote-compose.yaml` should be written as if it is executed on the remote server (because it is). The images that it needs to `docker compose up` should be the same as in the regular compose file, just prefixed by `localhost:5000/`. 

So this:

```yaml
services:
  hello-world:
    image: hello-world
```

Becomes this:

```yaml
services:
  hello-world:
    image: localhost:5000/hello-world
```

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
2. Create a symbolic link to the script in a directory that is in your system's PATH.

```powershell
New-Item -ItemType SymbolicLink -Path "C:\Windows\System32\remote-deploy.ps1" -Target ".\remote-deploy.ps1"
```

After these steps, you can run `remote-deploy` from any directory in PowerShell.

### Uninstall
To uninstall the script globally, simply remove the symbolic link:

```powershell
Remove-Item -Path "C:\Windows\System32\remote-deploy.ps1" -Force
```

## Notes

- Ensure that Docker is running before executing the script.
- You must have SSH access to the target server.
- The script tags and pushes Docker images based on the configuration in the `docker-compose.yaml` file.

## Troubleshooting

- If the script fails to connect to the target host, verify the SSH connection and ensure the target host is reachable.
- Use the `-Debug` parameter to see more detailed messages about the script's progress and any issues.
