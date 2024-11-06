#!/bin/bash

# Parameters
COMPOSE_FILE="$HOME/tora/docker-compose.yml"
CHECK_SCRIPT="/usr/local/bin/check_and_start_node.sh"
SERVICE_FILE="/etc/systemd/system/check_node.service"
TIMER_FILE="/etc/systemd/system/check_node.timer"
LOG_FILE="/var/log/check_node.log"

# Check if Docker Compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Docker Compose file not found: $COMPOSE_FILE"
  exit 1
fi

# Create the container status check script
echo "Creating container status check script..."
cat << EOF | sudo tee "$CHECK_SCRIPT" > /dev/null
#!/bin/bash

# Container names to check
containers=("ora-openlm" "ora-redis" "ora-tora" "diun")

# Log file
LOG_FILE="$LOG_FILE"

# Check each container
all_running=true
for container in "\${containers[@]}"; do
  if ! docker inspect --format='{{.State.Running}}' "\$container" 2>/dev/null | grep -q true; then
    echo "\$(date): Container \$container is not running." | tee -a "\$LOG_FILE"
    all_running=false
  fi
done

# Start configuration if not all containers are running
if [ "\$all_running" = true ]; then
  echo "\$(date): All containers are running." | tee -a "\$LOG_FILE"
else
  echo "\$(date): Not all containers are running. Starting Docker Compose configuration..." | tee -a "\$LOG_FILE"
  docker compose -f "$COMPOSE_FILE" up -d >> "\$LOG_FILE" 2>&1
fi
EOF

# Set execute permissions
sudo chmod +x "$CHECK_SCRIPT"

# Create systemd service if it doesn't exist
if [[ ! -f "$SERVICE_FILE" ]]; then
  echo "Creating systemd service..."
  cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Check and start Docker Compose containers
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$CHECK_SCRIPT

[Install]
WantedBy=multi-user.target
EOF
fi

# Create systemd timer if it doesn't exist
if [[ ! -f "$TIMER_FILE" ]]; then
  echo "Creating timer for periodic execution..."
  cat << EOF | sudo tee "$TIMER_FILE" > /dev/null
[Unit]
Description=Check and start containers every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=check_node.service

[Install]
WantedBy=timers.target
EOF
fi

# Reload systemd and activate timer and service
echo "Reloading systemd and enabling the timer and service..."
sudo systemctl daemon-reload
sudo systemctl enable --now check_node.timer

echo "Setup complete. Timer is set to check every 5 minutes."