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
dnf install -y git python3 python3-pip jq unzip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv ./kubectl /usr/local/bin

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Configure kubectl for EKS clusters
echo "Configuring kubectl for cluster ${EKSCluster1Name}"
aws eks update-kubeconfig --name "${EKSCluster1Name}" --region "${AWS_REGION}"

echo "Configuring kubectl for cluster ${EKSCluster2Name}"
aws eks update-kubeconfig --name "${EKSCluster2Name}" --region "${AWS_REGION}"

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

# Set AWS region in environment
export AWS_DEFAULT_REGION=${AWS_REGION}
echo "export AWS_REGION=${AWS_REGION}" >> /etc/profile
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" >> /etc/profile
echo "export AWS_REGION=${AWS_REGION}" >> /home/ec2-user/.bashrc
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" >> /home/ec2-user/.bashrc

# Create directory for the app
mkdir -p /home/ec2-user/eks-operational-review-agent

# Create a simple Streamlit app
cat > /home/ec2-user/eks-operational-review-agent/app.py << EOF
import streamlit as st
import boto3
import os

# Ensure region is set
region = os.environ.get('AWS_REGION', '${AWS_REGION}')
st.title("EKS Operational Review Agent")
st.write("Welcome to the EKS Operational Review Agent!")
st.write(f"Using AWS Region: {region}")

# Display EKS clusters
st.header("EKS Clusters")
eks = boto3.client('eks', region_name=region)
clusters = eks.list_clusters()['clusters']
for cluster in clusters:
    st.write(f"- {cluster}")
    
# Display cluster details
if clusters:
    selected_cluster = st.selectbox("Select a cluster to analyze", clusters)
    if st.button("Analyze Cluster"):
        st.write(f"Analyzing cluster: {selected_cluster}")
        cluster_info = eks.describe_cluster(name=selected_cluster)
        st.json(cluster_info)
EOF

# Install required packages
pip3 install --ignore-installed streamlit boto3

# Set proper permissions
chown -R ec2-user:ec2-user /home/ec2-user/eks-operational-review-agent/

# Set up systemd service for Streamlit app
cat > /etc/systemd/system/eks-review-agent.service << EOF
[Unit]
Description=EKS Operational Review Agent
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/eks-operational-review-agent
Environment="AWS_REGION=${AWS_REGION}"
Environment="AWS_DEFAULT_REGION=${AWS_REGION}"
ExecStart=/usr/bin/python3 -m streamlit run app.py --server.port=8501 --server.address=0.0.0.0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable eks-review-agent
systemctl start eks-review-agent

# Deploy NGINX to both clusters
echo "Deploying NGINX to ${EKSCluster1Name}"
kubectl config use-context "${EKSCluster1Name}" || echo "Failed to switch context to ${EKSCluster1Name}"
kubectl create deployment nginx --image=nginx --replicas=3 || echo "Failed to create nginx deployment in ${EKSCluster1Name}"
kubectl expose deployment nginx --port=80 --type=LoadBalancer || echo "Failed to expose nginx in ${EKSCluster1Name}"

echo "Deploying NGINX to ${EKSCluster2Name}"
kubectl config use-context "${EKSCluster2Name}" || echo "Failed to switch context to ${EKSCluster2Name}"
kubectl create deployment nginx --image=nginx --replicas=3 || echo "Failed to create nginx deployment in ${EKSCluster2Name}"
kubectl expose deployment nginx --port=80 --type=LoadBalancer || echo "Failed to expose nginx in ${EKSCluster2Name}"
