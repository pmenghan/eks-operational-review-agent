#!/bin/bash -e
# Check for required environment variables
if [ -z "$AWS_REGION" ] || [ -z "$EKSCluster1Name" ] || [ -z "$EKSCluster2Name" ]; then
  echo "ERROR: Required environment variables not set"
  echo "Please set the following variables before running this script:"
  echo "  - AWS_REGION"
  echo "  - EKSCluster1Name"
  echo "  - EKSCluster2Name"
  exit 1
fi

echo "Using AWS_REGION: $AWS_REGION"
echo "Using EKSCluster1Name: $EKSCluster1Name"
echo "Using EKSCluster2Name: $EKSCluster2Name"

# Update system
dnf update -y
dnf install -y git nodejs npm python3 python3-pip jq unzip

# Set AWS region in environment
export AWS_DEFAULT_REGION=${AWS_REGION}
echo "export AWS_REGION=${AWS_REGION}" >> /etc/profile
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" >> /etc/profile

# Create user directories and set permissions
mkdir -p /home/ec2-user/.kube
mkdir -p /home/ec2-user/.config
mkdir -p /home/ec2-user/.aws

# Set up bash profile and bashrc for ec2-user
echo "export AWS_REGION=${AWS_REGION}" >> /home/ec2-user/.bash_profile
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" >> /home/ec2-user/.bash_profile
echo "export PATH=\$PATH:/usr/local/bin" >> /home/ec2-user/.bash_profile

echo "export AWS_REGION=${AWS_REGION}" >> /home/ec2-user/.bashrc
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" >> /home/ec2-user/.bashrc

# Install kubectl from Amazon EKS
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv ./kubectl /usr/local/bin

# Verify kubectl installation
kubectl version --client || echo "ERROR: kubectl not installed correctly"

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Configure AWS CLI for ec2-user
cat > /home/ec2-user/.aws/config << EOF
[default]
region = ${AWS_REGION}
output = json
EOF

# Use aws eks update-kubeconfig with explicit parameters
echo "Configuring kubectl for cluster ${EKSCluster1Name}"
aws eks update-kubeconfig --name "${EKSCluster1Name}" --region "${AWS_REGION}" --kubeconfig /home/ec2-user/.kube/config

echo "Configuring kubectl for cluster ${EKSCluster2Name}"
aws eks update-kubeconfig --name "${EKSCluster2Name}" --region "${AWS_REGION}" --kubeconfig /home/ec2-user/.kube/config

# Verify EKS access configuration
echo "Verifying EKS access configuration for ${EKSCluster1Name}"
aws eks describe-access-entries --cluster-name "${EKSCluster1Name}" --region "${AWS_REGION}" || echo "Unable to verify access entries for ${EKSCluster1Name}"

echo "Verifying EKS access configuration for ${EKSCluster2Name}"
aws eks describe-access-entries --cluster-name "${EKSCluster2Name}" --region "${AWS_REGION}" || echo "Unable to verify access entries for ${EKSCluster2Name}"

# Verify EKS Pod Identity Agent add-on
echo "Verifying EKS Pod Identity Agent add-on for ${EKSCluster1Name}"
aws eks describe-addon --cluster-name "${EKSCluster1Name}" --addon-name eks-pod-identity-agent --region "${AWS_REGION}" || echo "Pod Identity Agent add-on not found for ${EKSCluster1Name}"

echo "Verifying EKS Pod Identity Agent add-on for ${EKSCluster2Name}"
aws eks describe-addon --cluster-name "${EKSCluster2Name}" --addon-name eks-pod-identity-agent --region "${AWS_REGION}" || echo "Pod Identity Agent add-on not found for ${EKSCluster2Name}"

# Update aws-auth ConfigMap to add EC2InstanceRole with system:masters permissions
if [ -z "$EC2InstanceRoleArn" ]; then
  echo "WARNING: EC2InstanceRoleArn not set, skipping aws-auth ConfigMap update"
else
  echo "Updating aws-auth ConfigMap with role: $EC2InstanceRoleArn"
  
  cat > /tmp/aws-auth-patch.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${EC2InstanceRoleArn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
        - system:masters
EOF

  # Apply the patch to both clusters
  echo "Applying aws-auth patch to ${EKSCluster1Name}"
  kubectl config use-context "${EKSCluster1Name}"
  kubectl patch configmap aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yaml)" || echo "Failed to patch aws-auth for ${EKSCluster1Name}"

  echo "Applying aws-auth patch to ${EKSCluster2Name}"
  kubectl config use-context "${EKSCluster2Name}"
  kubectl patch configmap aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yaml)" || echo "Failed to patch aws-auth for ${EKSCluster2Name}"
fi

# Create a script to refresh EKS tokens
cat > /home/ec2-user/refresh-eks-token.sh << 'EOF'
#!/bin/bash
aws eks update-kubeconfig --name eks-cluster-1 --region $AWS_REGION --kubeconfig ~/.kube/config
aws eks update-kubeconfig --name eks-cluster-2 --region $AWS_REGION --kubeconfig ~/.kube/config
echo "EKS tokens refreshed"
EOF

chmod +x /home/ec2-user/refresh-eks-token.sh

# Set proper ownership
chown -R ec2-user:ec2-user /home/ec2-user/

# Install code-server (VS Code in browser)
curl -fsSL https://code-server.dev/install.sh > /tmp/install-code-server.sh
chmod +x /tmp/install-code-server.sh
/tmp/install-code-server.sh

# Verify code-server is installed
which code-server || echo "ERROR: code-server not installed"

# Generate self-signed certificate for code-server
mkdir -p /home/ec2-user/.config/code-server/certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /home/ec2-user/.config/code-server/certificates/code-server.key \
  -out /home/ec2-user/.config/code-server/certificates/code-server.crt \
  -subj "/C=US/ST=CA/L=San Francisco/O=AWS/OU=EKS Workshop/CN=code-server"

# Configure code-server
mkdir -p /home/ec2-user/.config/code-server
cat > /home/ec2-user/.config/code-server/config.yaml << EOF
bind-addr: 0.0.0.0:3000
auth: password
password: workshop
cert: true
cert-host: code-server
cert-key: /home/ec2-user/.config/code-server/certificates/code-server.key
cert-file: /home/ec2-user/.config/code-server/certificates/code-server.crt
EOF

# Create systemd service for code-server
cat > /etc/systemd/system/code-server.service << EOF
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
Environment="AWS_REGION=${AWS_REGION}"
Environment="AWS_DEFAULT_REGION=${AWS_REGION}"
ExecStart=/usr/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start code-server
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

# Verify code-server is running
sleep 5
systemctl status code-server

# Create welcome page
mkdir -p /home/ec2-user/workshop
cat > /home/ec2-user/workshop/README.md << EOF
# EKS Operations Review Workshop

Welcome to the EKS Operations Review with GenAI workshop!

## Getting Started

1. Open a terminal in this IDE
2. Run the following commands to verify access to your EKS clusters:

\`\`\`bash
kubectl config get-contexts
kubectl config use-context ${EKSCluster1Name}
kubectl get nodes
\`\`\`

3. Access the EKS Operational Review Agent at: http://${EC2InstancePublicDNS:-<EC2_INSTANCE_DNS>}:8501
   Access this IDE at: https://localhost:3000 (password: workshop)

## Workshop Resources

- EKS Cluster 1: ${EKSCluster1Name}
- EKS Cluster 2: ${EKSCluster2Name}
- Knowledge Base Bucket: ${KnowledgeBaseBucketName:-<KNOWLEDGE_BASE_BUCKET>}
- AWS Region: ${AWS_REGION}

Enjoy the workshop!
EOF

# Set ownership
chown -R ec2-user:ec2-user /home/ec2-user/workshop
