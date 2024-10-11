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

### Adding insecure registry

Assuming your machine has an ip address in the range `192.168.x.x`.

#### Linux
Edit `/etc/docker/daemon.json` to include:
```json
{
    "insecure-registries": ["192.168.0.0/16"]
}
```
#### Windows
For Docker Desktop on Windows, go to the **Settings** >> **Docker Engine**, and modify the `daemon.json` configuration to include:
```json
{
    "insecure-registries": ["192.168.0.0/16"]
}
```

### Setting up SSH keys for seamless access

[Please follow this guide about exchanging SSH keys for passwordless SSH entry.](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)

### Add a remote-compose file

The `Invoke-RemoteDeploy`-utility requires there to be a file in the directory (next to the compose) called `remote-compose.yaml`. This file is used for remote deployment.

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

> [!NOTE]
> A service with a build stage should still have an image name specified (in  `docker-compose.yaml`) like above, otherwise the script can not find the final image. This image name should then be prefixed with `localhost:5000/` in `remote-compose.yaml`.

## Usage

```powershell
Invoke-RemoteDeploy -TargetHost <TargetHost> [-TargetUser <TargetUser>] [-TargetPort <TargetPort>] [-Debug] [-Help]
```

### Parameters

- `-TargetHost` (required): The target host for deployment.
- `-TargetUser` (optional, default: root): The target user for SSH connection.
- `-TargetPort` (optional, default: 5000): The port for the SSH tunnel and registry.
- `-Debug` (optional): Enable debug messages.
- `-Help` (optional): Display help message.

### Example

```powershell
Invoke-RemoteDeploy 192.168.1.100
```

```powershell
Invoke-RemoteDeploy -TargetHost 192.168.1.100 -TargetUser root -TargetPort 5000 -Debug
```

## Installing Globally

To make this script available system-wide, you can create a symbolic link to it in a directory that is in your system's PATH.

### Steps to Install Globally

1. Open a PowerShell prompt as an administrator.
2. Create a symbolic link to the script in a directory that is in your system's PATH.

```powershell
New-Item -ItemType SymbolicLink -Path "C:\Windows\System32\Invoke-RemoteDeploy.ps1" -Target ".\Invoke-RemoteDeploy.ps1"
```

After these steps, you can run `Invoke-RemoteDeploy` from any directory in PowerShell.

### Uninstall
To uninstall the script globally, simply remove the symbolic link:

```powershell
Remove-Item -Path "C:\Windows\System32\Invoke-RemoteDeploy.ps1" -Force
```

## Notes

- Ensure that Docker (Desktop) is running before executing the script.
- In it's current state the script assumes you share a subnet with the server you're trying to SSH into, so it (probably) won't work for named URLs (e.g. server01.local).
- You must have SSH access to the target server, on a level you can run Docker commands (probably root).
- The script tags and pushes Docker images based on the configuration in the `docker-compose.yaml` file.

## Troubleshooting

- If the script fails to connect to the target host, verify the SSH connection and ensure the target host is reachable.
- Make sure the insecure-registries are correctly set.
- Use the `-Debug` parameter to see more detailed messages about the script's progress and any issues.
