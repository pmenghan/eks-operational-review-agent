#!/bin/bash

# EKS Operational Review Agent Deployment Script
# This script downloads the package from S3 and sets up the application

set -e  # Exit immediately if a command exits with a non-zero status

# Configuration
S3_BUCKET="your-s3-bucket-name"
S3_KEY="eks-operations-agent.zip"
APP_DIR="/opt/eks-ops-review"

# Print colored output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting EKS Operational Review Agent deployment...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}This script requires root privileges to install system packages.${NC}"
  echo -e "${YELLOW}Please run with sudo or as root.${NC}"
  exit 1
fi

# Update system packages
echo -e "${GREEN}Updating system packages...${NC}"
dnf update -y

# Install required system packages
echo -e "${GREEN}Installing required system packages...${NC}"
dnf install -y python3 python3-pip git wget unzip

# Install AWS CLI if not already installed
if ! command -v aws &> /dev/null; then
  echo -e "${GREEN}Installing AWS CLI...${NC}"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
  rm -rf aws awscliv2.zip
fi

# Download package from S3
echo -e "${GREEN}Downloading package from S3...${NC}"
aws s3 cp s3://${S3_BUCKET}/${S3_KEY} .

# Create application directory
echo -e "${GREEN}Creating application directory at ${APP_DIR}...${NC}"
mkdir -p $APP_DIR

# Extract package
echo -e "${GREEN}Extracting package...${NC}"
unzip -q ${S3_KEY} -d $APP_DIR
cd $APP_DIR

# Set up Python virtual environment
echo -e "${GREEN}Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies directly
echo -e "${GREEN}Installing Python dependencies...${NC}"
pip install --upgrade pip
pip install streamlit boto3 requests bs4 python-dotenv plotly reportlab urllib3 chardet charset-normalizer PyMuPDF hardeneks kubernetes

# Create a startup script
echo -e "${GREEN}Creating startup script...${NC}"
cat > $APP_DIR/start.sh << EOF
#!/bin/bash
source $APP_DIR/venv/bin/activate
cd $APP_DIR
streamlit run app.py --server.port=8501 --server.address=0.0.0.0
EOF
chmod +x $APP_DIR/start.sh

# Create systemd service file
echo -e "${GREEN}Creating systemd service file...${NC}"
cat > /etc/systemd/system/eks-ops-review.service << EOF
[Unit]
Description=EKS Operational Review Agent
After=network.target

[Service]
User=ec2-user
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/streamlit run $APP_DIR/app.py --server.port=8501 --server.address=0.0.0.0
Restart=always
Environment=PATH=$APP_DIR/venv/bin:$PATH

[Install]
WantedBy=multi-user.target
EOF

# Set appropriate permissions
echo -e "${GREEN}Setting appropriate permissions...${NC}"
chown -R ec2-user:ec2-user $APP_DIR
chmod -R 755 $APP_DIR

echo -e "${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}You can start the service with: sudo systemctl start eks-ops-review${NC}"
echo -e "${YELLOW}Enable it to start on boot with: sudo systemctl enable eks-ops-review${NC}"
echo -e "${GREEN}Or run it manually with: $APP_DIR/start.sh${NC}"
echo -e "${YELLOW}The application will be available at: http://your-server-ip:8501${NC}"
echo -e "${YELLOW}Make sure port 8501 is open in your security group.${NC}"
