#!/bin/bash

# Script to update the aws-auth ConfigMap to add the WSParticipantRole

# Check if cluster name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <cluster-name>"
  exit 1
fi

CLUSTER_NAME=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION=$(aws configure get region)

echo "Updating aws-auth ConfigMap for cluster $CLUSTER_NAME in account $ACCOUNT_ID"

# Get the current aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml

# Check if WSParticipantRole is already in the ConfigMap
if grep -q "rolearn: arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole" aws-auth.yaml; then
  echo "WSParticipantRole is already in the aws-auth ConfigMap"
  exit 0
fi

# Add WSParticipantRole to the ConfigMap
cat > aws-auth-patch.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/WSParticipantRole
      username: workshop-user
      groups:
        - system:masters
EOF

# Apply the patch
kubectl patch configmap aws-auth -n kube-system --patch "$(cat aws-auth-patch.yaml)"

echo "aws-auth ConfigMap updated successfully"
