# wget -L http://raw.github.com/dakotaeye/sledgehammer/main/docker-services-installer.sh
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a container is running
container_running() {
    docker ps --format "table {{.Names}}" | grep -q "^$1$"
}

# Function to wait for a port to be available
wait_for_port() {
    local port=$1
    local service=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service to be ready on port $port..."
    while ! nc -z localhost $port 2>/dev/null; do
        if [ $attempt -eq $max_attempts ]; then
            print_warning "$service may not be fully ready yet. You can check manually."
            return 1
        fi
        sleep 2
        ((attempt++))
    done
    print_status "$service is ready!"
    return 0
}

# Main script starts here
echo "========================================="
echo "Docker Services Installation Script"
echo "Installing: Portainer, PowerShell Universal, and Rundeck"
echo "========================================="
echo

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run this script with sudo or as root"
    exit 1
fi

# Step 1: Install Docker if not present
print_status "Checking for Docker installation..."

if ! command_exists docker; then
    print_status "Docker not found. Installing Docker..."
    
    # Update package index
    apt update -y
    
    # Install prerequisites
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_status "Docker installed successfully!"
else
    print_status "Docker is already installed"
fi

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
    print_status "Starting Docker service..."
    systemctl start docker
fi

# Get the current user (who ran sudo)
CURRENT_USER=${SUDO_USER:-$USER}

# Add user to docker group
if ! groups $CURRENT_USER | grep -q docker; then
    print_status "Adding $CURRENT_USER to docker group..."
    usermod -aG docker $CURRENT_USER
    print_warning "You'll need to log out and back in for group changes to take effect"
fi

echo
print_status "Installing services..."
echo

# Step 2: Install Portainer
print_status "Installing Portainer..."

# Check if Portainer is already running
if container_running "portainer"; then
    print_warning "Portainer container already exists. Removing old container..."
    docker stop portainer >/dev/null 2>&1
    docker rm portainer >/dev/null 2>&1
fi

# Create volume for Portainer data
docker volume create portainer_data >/dev/null 2>&1

# Run Portainer container
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_status "Portainer installed successfully!"
else
    print_error "Failed to install Portainer"
fi

# Step 3: Install PowerShell Universal
print_status "Installing PowerShell Universal..."

# Check if PSU is already running
if container_running "PSU"; then
    print_warning "PowerShell Universal container already exists. Removing old container..."
    docker stop PSU >/dev/null 2>&1
    docker rm PSU >/dev/null 2>&1
fi

# Create volume for PowerShell Universal data
docker volume create psu_data >/dev/null 2>&1

# Run PowerShell Universal container
docker run -d \
  --name PSU \
  -p 5000:5000 \
  --restart unless-stopped \
  -v psu_data:/root \
  ironmansoftware/universal:latest >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_status "PowerShell Universal installed successfully!"
else
    print_error "Failed to install PowerShell Universal"
fi

# Step 4: Install Rundeck
print_status "Installing Rundeck..."

# Check if Rundeck is already running
if container_running "rundeck"; then
    print_warning "Rundeck container already exists. Removing old container..."
    docker stop rundeck >/dev/null 2>&1
    docker rm rundeck >/dev/null 2>&1
fi

# Pull Rundeck image
print_status "Pulling Rundeck image..."
docker pull rundeck/rundeck:5.12.0 >/dev/null 2>&1

# Create volume for Rundeck data
docker volume create rundeck_data >/dev/null 2>&1

# Run Rundeck container
docker run -d \
  --name rundeck \
  -p 4440:4440 \
  --restart unless-stopped \
  -v rundeck_data:/home/rundeck/server/data \
  rundeck/rundeck:5.12.0 >/dev/null 2>&1

if [ $? -eq 0 ]; then
    print_status "Rundeck installed successfully!"
else
    print_error "Failed to install Rundeck"
fi

# Wait a moment for containers to start
sleep 5

# Step 5: Verify all services are running
echo
print_status "Verifying all services..."
echo

# Check container status
PORTAINER_STATUS=$(docker ps --filter "name=portainer" --format "{{.Status}}" | head -n1)
PSU_STATUS=$(docker ps --filter "name=PSU" --format "{{.Status}}" | head -n1)
RUNDECK_STATUS=$(docker ps --filter "name=rundeck" --format "{{.Status}}" | head -n1)

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Display results
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo

# Portainer status
if [ -n "$PORTAINER_STATUS" ]; then
    echo -e "Portainer:    ${GREEN}Running${NC} - $PORTAINER_STATUS"
    echo "  Access URL: https://$SERVER_IP:9443"
    echo "  Note: First access will prompt you to create an admin user"
else
    echo -e "Portainer:    ${RED}Not Running${NC}"
fi
echo

# PowerShell Universal status
if [ -n "$PSU_STATUS" ]; then
    echo -e "PowerShell Universal: ${GREEN}Running${NC} - $PSU_STATUS"
    echo "  Access URL: http://$SERVER_IP:5000"
    echo "  Default login: username 'admin' (set password on first login)"
else
    echo -e "PowerShell Universal: ${RED}Not Running${NC}"
fi
echo

# Rundeck status
if [ -n "$RUNDECK_STATUS" ]; then
    echo -e "Rundeck:      ${GREEN}Running${NC} - $RUNDECK_STATUS"
    echo "  Access URL: http://$SERVER_IP:4440"
    echo "  Default credentials: username 'admin', password 'admin'"
else
    echo -e "Rundeck:      ${RED}Not Running${NC}"
fi

echo
echo "========================================="
echo "Useful Commands:"
echo "========================================="
echo "View all running containers:  docker ps"
echo "View container logs:          docker logs <container-name>"
echo "Stop a container:             docker stop <container-name>"
echo "Start a container:            docker start <container-name>"
echo "Remove a container:           docker rm <container-name>"
echo

# Check if all services are running
if [ -n "$PORTAINER_STATUS" ] && [ -n "$PSU_STATUS" ] && [ -n "$RUNDECK_STATUS" ]; then
    print_status "All services installed and running successfully!"
else
    print_warning "Some services may not be running. Check the status above."
fi

# Create docker-compose file for future management
print_status "Creating docker-compose.yml for easier management..."

cat > /opt/docker-services-compose.yml << 'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "8000:8000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

  powershell-universal:
    image: ironmansoftware/universal:latest
    container_name: PSU
    restart: unless-stopped
    ports:
      - "5000:5000"
    volumes:
      - psu_data:/root

  rundeck:
    image: rundeck/rundeck:5.12.0
    container_name: rundeck
    restart: unless-stopped
    ports:
      - "4440:4440"
    volumes:
      - rundeck_data:/home/rundeck/server/data

volumes:
  portainer_data:
    external: true
  psu_data:
    external: true
  rundeck_data:
    external: true
EOF

print_status "Docker Compose file created at: /opt/docker-services-compose.yml"
echo "You can use 'docker-compose -f /opt/docker-services-compose.yml [command]' to manage all services"

echo
print_status "Installation complete!"

# Final reminder about docker group
if ! groups $CURRENT_USER | grep -q docker; then
    echo
    print_warning "Remember to log out and back in for docker group changes to take effect"
    print_warning "This will allow you to run docker commands without sudo"
fi
