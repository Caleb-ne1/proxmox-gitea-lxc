# Proxmox Gitea LXC Installer

A Proxmox LXC installer script to quickly deploy a **Gitea server** in a container.

This script automates the creation of an LXC container on Proxmox, installs all necessary dependencies, sets up Gitea as a systemd service, and provides access details.

---

## Requirements

- Proxmox VE 7+  
- Root access on the Proxmox host  
- Storage configured for LXC templates and container rootfs  
- Network access to your container subnet  

Dependencies that will be installed if missing:

- `whiptail`
- `pvesh`
- `pct`
- `pveam`
- `jq`
- `curl`

---

## Installation
### Option 1:  Clone repository

1. Clone this repository:

```bash
git clone https://github.com/Caleb-ne1/proxmox-gitea-lxc.git
cd proxmox-gitea-lxc
```

2. Make the installer script executable:

```bash
chmod +x gitea-installer.sh
```

3. Run the installer:

```bash
./gitea-installer.sh
```

4. Follow the interactive prompts

### Option 2: One-liner Installation

For convenience, you can also install Gitea LXC directly using a one-liner:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Caleb-ne1/proxmox-gitea-lxc/main/gitea-installer.sh)"

```


---

## Accessing Gitea

After installation, the script will show your container’s IP:

```
http://<container-ip>:3000
```

Log in using the `git` user or configure an admin user via the Gitea web setup.

---
## Author

Created by **Caleb Kibet**  
GitHub: [https://github.com/Caleb-ne1](https://github.com/Caleb-ne1)  

