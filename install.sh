#!/bin/bash
set -e

# temporary file
TMP_SCRIPT=$(mktemp)

# download main installer script from GitHub
curl -fsSL https://raw.githubusercontent.com/Caleb-ne1/proxmox-gitea-lxc/main/gitea-installer.sh -o "$TMP_SCRIPT"

# make it executable
chmod +x "$TMP_SCRIPT"

# run it
bash "$TMP_SCRIPT"

# remove temp file
rm -f "$TMP_SCRIPT"
