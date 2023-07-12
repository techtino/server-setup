#!/bin/bash

CONTAINER_DIR=$HOME/containers/
CONTAINER_BACKUP_DIR=/mnt/nas/Backups/containers/
NAS_IP=192.168.0.132
green='\033[0;32m'
clear_colour='\033[0m'

# Install dependencies (and nala because fast)
echo -e "${green}Installing dependencies${clear_colour} \n"
sudo apt-get update
sudo apt-get -y install nala
sudo nala install -y nfs-common docker docker-compose rsync

# Have the docker container service ready beforehand (It's a dependency of the mnt-nas). Service will fail as the files are not there yet, deploy these later.
echo -e "${green}Setting up container startup service:${clear_colour} \n"
cat << EOF | sudo tee '/etc/systemd/system/start-containers.service'
[Unit]
Description=Run Docker Containers
AFter=docker.service

[Service]
Type=simple
WorkingDir=$CONTAINER_DIR
ExecStart=docker-compose up --remove-orphans
ExecStop=docker-compose down

[Install]
WantedBy=default.target
EOF
echo -e "\n"

# Setup our mount via systemd, fstab is annoying as can't easily make it depend on network being available/make sure it runs before docker.
echo -e "${green}Setting up NAS mount service:${clear_colour}\n"
cat << EOF | sudo tee '/etc/systemd/system/mnt-nas.mount'
[Unit]
Description=Mount TechTino TrueNAS
After=network-online.target
After=start-containers.service

[Mount]
What=$NAS_IP:/mnt/NAS/Storage
Where=/mnt/nas
Type=nfs
TimeoutSec=60
Options=_netdev,auto,rw,hard,x-gvfs-show

[Install]
WantedBy=multi-user.target
EOF
echo -e "\n"

# Setup new backups via systemd timer.
echo -e "${green}Creating container snapshot script, systemd service and timer: ${clear_colour}\n"
cat << EOF | sudo tee '/usr/local/bin/snapshot-containers'
#!/bin/bash

# Get current date
DATE=\$(date +'%d-%m-%Y')

# Create backup directory for today
mkdir -p $CONTAINER_BACKUP_DIR\$DATE

# Use rsync to backup, using hard links for unchanged files
rsync -avP --link-dest=$CONTAINER_BACKUP_DIR\$(date -d '1 day ago' +'%d-%m-%Y') $CONTAINER_DIR $CONTAINER_BACKUP_DIR\$DATE/containers/

# Update 'latest' symlink to point to the most recent backup
ln -sfn $CONTAINER_BACKUP_DIR\$DATE $CONTAINER_BACKUP_DIRlatest
EOF

sudo chmod +x /usr/local/bin/snapshot-containers

echo -e "${green}Creating container snapshot systemd service and timer: ${clear_colour}\n"
cat << EOF | sudo tee '/etc/systemd/system/snapshot-containers.service'
[Unit]
Description=Daily backup of docker container data

[Service]
ExecStart=/usr/local/bin/snapshot-containers
EOF

cat << EOF | sudo tee '/etc/systemd/system/snapshot-containers.timer'
[Unit]
Description=Run backup daily at 10am

[Timer]
OnCalendar=*-*-* 10:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Mounting the NAS and enabling the backup timer.
echo -e "${green}Mounting NAS and enabling backup timer (10am daily backups).${clear_colour}\n"
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-nas.mount

# We enable the snapshot timer here, but starting it right now is pointless as the containers aren't setup
sudo systemctl enable snapshot-containers.timer

# If the container directory already exists, then lets not retrieve from backups.
if [ -d "$CONTAINER_DIR" ]; 
then
    echo -e "${green}Container directory already setup, will not copy from backup.${clear_colour}"
else
    echo -e "${green}Retrieving latest backup of containers and deploying.${clear_colour}"
    rsync -avP $CONTAINER_BACKUP_DIR/latest/containers $CONTAINER_DIR
fi

# After the container directory is setup, we want to enable and start the docker containers.
echo -e "${green}Starting the docker containers, and enabling the systemd service for next boot."

sudo systemctl enable --now start-containers
