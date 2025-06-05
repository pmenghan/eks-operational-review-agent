#!/bin/bash

# Script to upload the EKS Operations Agent package to S3

# Configuration
S3_BUCKET="your-s3-bucket-name"
S3_KEY="eks-operations-agent.zip"
SOURCE_PATH="eks-operations-agent.zip"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Upload to S3
echo "Uploading package to S3..."
aws s3 cp $SOURCE_PATH s3://${S3_BUCKET}/${S3_KEY}

if [ $? -eq 0 ]; then
    echo "Upload successful!"
    echo "Package available at: s3://${S3_BUCKET}/${S3_KEY}"
    echo ""
    echo "To deploy on EC2, use the following command:"
    echo "aws s3 cp s3://${S3_BUCKET}/${S3_KEY} ."
    echo "unzip ${S3_KEY}"
    echo "cd eks-operations-agent"
    echo "sudo ./deploy_s3.sh"
else
    echo "Upload failed. Please check your AWS credentials and S3 bucket permissions."
fi
