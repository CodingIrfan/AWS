#!/bin/bash

set -euo pipefail

echo "Started script execution"
# ============================================================
# Configuration
# ============================================================

CLUSTER_NAME="eks-cluster-dev"
AWS_REGION="us-east-1"
VPC_ID="vpc-0ffcfab0b097f4503"

LBC_VERSION="v2.14.1"
HELM_CHART_VERSION="1.14.0"

IAM_POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
IAM_ROLE_NAME="AmazonEKSLoadBalancerControllerRole"

NAMESPACE="kube-system"
SERVICE_ACCOUNT="aws-load-balancer-controller"

POLICY_FILE="aws-load-balancer-controller-iam-policy.json"
TRUST_POLICY_FILE="aws-load-balancer-controller-trust-policy.json"

# ============================================================
# Validation
# ============================================================

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "ERROR: Cluster name is required."
    echo
    echo "Usage:"
    echo "  ./install-alb-controller.sh <cluster-name>"
    echo
    exit 1
fi

command -v aws >/dev/null 2>&1 || {
    echo "ERROR: AWS CLI is not installed."
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed."
    exit 1
}

command -v helm >/dev/null 2>&1 || {
    echo "ERROR: Helm is not installed."
    exit 1
}

echo "============================================================"
echo " AWS Load Balancer Controller Installation"
echo "============================================================"
echo
echo "Cluster : $CLUSTER_NAME"
echo "Region  : $AWS_REGION"
echo

# ============================================================
# Account information
# ============================================================

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

echo "AWS Account: $ACCOUNT_ID"
echo

# ============================================================
# Verify cluster exists
# ============================================================

echo "Checking EKS cluster..."

aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    >/dev/null

echo "EKS cluster found."
echo

# ============================================================
# Download AWS Load Balancer Controller IAM policy
# ============================================================

echo "Downloading IAM policy..."

curl -fsSL \
    "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json" \
    -o "$POLICY_FILE"

echo "IAM policy downloaded."
echo

# ============================================================
# Create IAM policy if it doesn't exist
# ============================================================

echo "Checking IAM policy..."

POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"

if aws iam get-policy \
    --policy-arn "$POLICY_ARN" \
    >/dev/null 2>&1; then

    echo "IAM policy already exists."

else

    echo "Creating IAM policy..."

    aws iam create-policy \
        --policy-name "$IAM_POLICY_NAME" \
        --policy-document "file://${POLICY_FILE}" \
        >/dev/null

    echo "IAM policy created."
fi

echo

# ============================================================
# Create IAM trust policy for EKS Pod Identity
# ============================================================

cat > "$TRUST_POLICY_FILE" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
EOF

# ============================================================
# Create IAM role if it doesn't exist
# ============================================================

echo "Checking IAM role..."

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${IAM_ROLE_NAME}"

if aws iam get-role \
    --role-name "$IAM_ROLE_NAME" \
    >/dev/null 2>&1; then

    echo "IAM role already exists."

else

    echo "Creating IAM role..."

    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document "file://${TRUST_POLICY_FILE}" \
        >/dev/null

    echo "IAM role created."
fi

echo

# ============================================================
# Ensure correct Pod Identity trust policy
# ============================================================

echo "Updating IAM role trust policy..."

aws iam update-assume-role-policy \
    --role-name "$IAM_ROLE_NAME" \
    --policy-document "file://${TRUST_POLICY_FILE}"

echo "Trust policy configured."
echo

# ============================================================
# Attach IAM policy to role
# ============================================================

echo "Checking IAM policy attachment..."

if aws iam list-attached-role-policies \
    --role-name "$IAM_ROLE_NAME" \
    --query "AttachedPolicies[?PolicyArn=='${POLICY_ARN}'].PolicyArn" \
    --output text | grep -q "$POLICY_ARN"; then

    echo "IAM policy already attached."

else

    echo "Attaching IAM policy..."

    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "$POLICY_ARN"

    echo "IAM policy attached."
fi

echo

# ============================================================
# Create Kubernetes ServiceAccount
# ============================================================

echo "Creating Kubernetes ServiceAccount..."

if kubectl get serviceaccount "$SERVICE_ACCOUNT" \
    -n "$NAMESPACE" \
    >/dev/null 2>&1; then

    echo "ServiceAccount already exists."

else

    kubectl create serviceaccount \
        "$SERVICE_ACCOUNT" \
        -n "$NAMESPACE"

    echo "ServiceAccount created."
fi

echo

# ============================================================
# Create EKS Pod Identity association
# ============================================================

echo "Checking EKS Pod Identity association..."

ASSOCIATION_ID=$(aws eks list-pod-identity-associations \
    --cluster-name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query "associations[?namespace=='${NAMESPACE}' && serviceAccount=='${SERVICE_ACCOUNT}'].associationId" \
    --output text)

if [[ -n "$ASSOCIATION_ID" && "$ASSOCIATION_ID" != "None" ]]; then

    echo "Pod Identity association already exists:"
    echo "  $ASSOCIATION_ID"

else

    echo "Creating EKS Pod Identity association..."

    aws eks create-pod-identity-association \
        --cluster-name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --role-arn "$ROLE_ARN" \
        --namespace "$NAMESPACE" \
        --service-account "$SERVICE_ACCOUNT"

    echo "Pod Identity association created."
fi

echo

# ============================================================
# Helm repository
# ============================================================

echo "Configuring Helm repository..."

if helm repo list | awk '{print $1}' | grep -qx "eks"; then
    echo "EKS Helm repository already exists."
else
    helm repo add eks https://aws.github.io/eks-charts
fi

helm repo update eks

echo

# ============================================================
# Install / Upgrade AWS Load Balancer Controller
# ============================================================

echo "Installing AWS Load Balancer Controller..."

if helm status aws-load-balancer-controller \
    -n "$NAMESPACE" \
    >/dev/null 2>&1; then

    echo "Controller already installed. Running Helm upgrade..."

    helm upgrade aws-load-balancer-controller \
        eks/aws-load-balancer-controller \
        --namespace "$NAMESPACE" \
        --set region="$AWS_REGION" \
        --set vpcId="$VPC_ID" \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name="$SERVICE_ACCOUNT" \
        --version "$HELM_CHART_VERSION"

else

    helm install aws-load-balancer-controller \
        eks/aws-load-balancer-controller \
        --namespace "$NAMESPACE" \
        --set region="$AWS_REGION" \
        --set vpcId="$VPC_ID" \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name="$SERVICE_ACCOUNT" \
        --version "$HELM_CHART_VERSION"

fi

echo

# ============================================================
# Wait for deployment
# ============================================================

echo "Waiting for AWS Load Balancer Controller..."

kubectl rollout status \
    deployment/aws-load-balancer-controller \
    -n "$NAMESPACE" \
    --timeout=180s

echo

# ============================================================
# Verification
# ============================================================

echo "============================================================"
echo " Installation completed"
echo "============================================================"
echo

echo "Deployment:"
kubectl get deployment \
    aws-load-balancer-controller \
    -n "$NAMESPACE"

echo
echo "Pods:"
kubectl get pods \
    -n "$NAMESPACE" \
    -l app.kubernetes.io/name=aws-load-balancer-controller \
    -o wide

echo
echo "ServiceAccount:"
kubectl get serviceaccount \
    "$SERVICE_ACCOUNT" \
    -n "$NAMESPACE"

echo
echo "Pod Identity Association:"
aws eks list-pod-identity-associations \
    --cluster-name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query "associations[?namespace=='${NAMESPACE}' && serviceAccount=='${SERVICE_ACCOUNT}']" \
    --output table

echo
echo "Controller logs:"
kubectl logs \
    -n "$NAMESPACE" \
    -l app.kubernetes.io/name=aws-load-balancer-controller \
    --tail=20

echo
echo "============================================================"
echo " AWS Load Balancer Controller is ready"
echo "============================================================"