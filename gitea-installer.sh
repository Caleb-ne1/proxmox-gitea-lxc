#!/bin/bash
set -e

# helper functions 
info()    { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[✔]\033[0m $1"; }
warn()    { echo -e "\033[1;33m[⚠]\033[0m $1"; }
error()   { echo -e "\033[1;31m[✖]\033[0m $1"; }


# check dependencies and install if missing
for cmd in whiptail pvesh pct pveam jq curl; do
    if ! command -v $cmd &> /dev/null; then
        warn "$cmd not found, installing..."
        apt-get update && apt-get install -y whiptail jq curl
    fi
done

# banner
echo -e "\033[1;36m===================================\033[0m"
echo -e "\033[1;36m        GITEA LXC INSTALLER        \033[0m"
echo -e "\033[1;36m===================================\033[0m"
echo -e "\033[1;33mCreated by: @Caleb Kibet\033[0m"
echo ""


# select template storage
TEMPLATE_STORAGES=($(pvesh get /nodes/localhost/storage --output-format=json \
  | jq -r '.[] | select(.content | test("vztmpl")) | .storage'))

if [ ${#TEMPLATE_STORAGES[@]} -eq 0 ]; then
    error "No storage supports LXC templates."
    exit 1
fi

OPTIONS=()
for s in "${TEMPLATE_STORAGES[@]}"; do OPTIONS+=("$s" "" OFF); done
TEMPLATE_STORAGE=$(whiptail --title "Select Template Storage" \
  --radiolist "Choose storage for LXC template:" 15 60 5 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

# select container storage
CT_STORAGES=($(pvesh get /nodes/localhost/storage --output-format=json \
  | jq -r '.[] | select(.content | test("rootdir")) | .storage'))

if [ ${#CT_STORAGES[@]} -eq 0 ]; then
    error "No storage supports container rootfs."
    exit 1
fi

OPTIONS=()
for s in "${CT_STORAGES[@]}"; do OPTIONS+=("$s" "" OFF); done
CT_STORAGE=$(whiptail --title "Select Container Storage" \
  --radiolist "Choose storage for LXC rootfs:" 15 60 5 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)

# gather input with  defaults

# VMID
if command -v pvesh &> /dev/null; then
    DEFAULT_VMID=$(pvesh get /cluster/nextid)
else
    DEFAULT_VMID=105
fi
VMID=$(whiptail --inputbox "Enter VMID" 8 60 "$DEFAULT_VMID" 3>&1 1>&2 2>&3)

# hostname
DEFAULT_HOSTNAME="gitea"
HOSTNAME=$(whiptail --inputbox "Enter Hostname" 8 60 "$DEFAULT_HOSTNAME" 3>&1 1>&2 2>&3)

# root password
PASSWORD=$(whiptail --passwordbox "Enter Root Password" 8 60 3>&1 1>&2 2>&3)

# memory and cpu cores
MEMORY=$(whiptail --inputbox "Enter Memory (MB)" 8 60 2048 3>&1 1>&2 2>&3)
CORES=$(whiptail --inputbox "Enter CPU Cores" 8 60 $(nproc) 3>&1 1>&2 2>&3)


# disk
DISK="10G"
DISK_NUMBER=10

# default IP and Gateway
DEFAULT_IP="10.0.0.$((100 + VMID))/24"   # Adjust subnet as needed
DEFAULT_GW=$(ip route show default | awk '/default/ {print $3}')

IP=$(whiptail --inputbox "Enter IP address (CIDR)" 8 60 "$DEFAULT_IP" 3>&1 1>&2 2>&3)
GW=$(whiptail --inputbox "Enter Gateway" 8 60 "$DEFAULT_GW" 3>&1 1>&2 2>&3)

# confirm settings
whiptail --title "Confirm Settings" --yesno "VMID: $VMID
Hostname: $HOSTNAME
Memory: $MEMORY MB
CPU: $CORES
Disk: $DISK
IP: $IP
Gateway: $GW
Continue?" 20 60 || exit 1

# download template if needed
TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

if [ ! -f "$TEMPLATE_PATH" ]; then
    info "Downloading Debian 12 template..."
    pveam update && pveam download $TEMPLATE_STORAGE $TEMPLATE
fi

success "Template ready."

# detect storage type for rootfs
STORAGE_TYPE=$(pvesh get /nodes/localhost/storage --output-format=json \
    | jq -r ".[] | select(.storage==\"$CT_STORAGE\") | .type")

if [ "$STORAGE_TYPE" = "lvmthin" ] || [ "$STORAGE_TYPE" = "lvm" ]; then
    ROOTFS_PARAM="$CT_STORAGE:$DISK_NUMBER"
elif [ "$STORAGE_TYPE" = "dir" ] || [ "$STORAGE_TYPE" = "nfs" ] || [ "$STORAGE_TYPE" = "cifs" ]; then
    ROOTFS_PARAM="$CT_STORAGE:$DISK"
elif [ "$STORAGE_TYPE" = "zfspool" ]; then
    ROOTFS_PARAM="$CT_STORAGE:size=$DISK"
else
    error "Unsupported storage type: $STORAGE_TYPE"; exit 1
fi


# create LXC container
info "Creating LXC container..."
pct create $VMID $TEMPLATE_PATH \
    --hostname $HOSTNAME \
    --rootfs $ROOTFS_PARAM \
    --memory $MEMORY \
    --cores $CORES \
    --net0 name=eth0,bridge=vmbr0,ip=$IP,gw=$GW \
    --password $PASSWORD \
    --features nesting=1 \
    --unprivileged 0
success "Container $VMID created."

# Start container
pct start $VMID
success "Container started."

# Install Gitea inside container
info "Installing Gitea inside container..."
pct exec $VMID -- bash -c "
set -e
apt-get update && apt-get install -y git curl wget openssh-server
adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git
wget -O /usr/local/bin/gitea https://dl.gitea.io/gitea/1.22.0/gitea-1.22.0-linux-amd64
chmod +x /usr/local/bin/gitea
mkdir -p /var/lib/gitea/{custom,data,log}
chown -R git:git /var/lib/gitea && chmod -R 750 /var/lib/gitea
mkdir /etc/gitea && chown root:git /etc/gitea && chmod 770 /etc/gitea
cat >/etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gitea
"

success "Gitea installed and running!"


# message with access info
IP_NO_MASK=${IP%/*}
whiptail --msgbox "Gitea LXC container created!\n\nVMID: $VMID\nHostname: $HOSTNAME\nIP: $IP_NO_MASK\n\nAccess Gitea at: http://$IP_NO_MASK:3000" 12 60

echo -e "\033[1;32m[✔] Gitea container setup complete.\033[0m"
echo -e "\033[1;34mAccess Gitea at: http://$IP_NO_MASK:3000\033[0m"

