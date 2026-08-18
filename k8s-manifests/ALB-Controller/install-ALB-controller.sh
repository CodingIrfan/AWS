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

NAMESPACE="kube-system"
SERVICE_ACCOUNT="aws-load-balancer-controller"

# ============================================================
# Validation
# ============================================================

if [[ -z "$CLUSTER_NAME" ]]; then
    echo "ERROR: Cluster name is required."
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
# Kubernetes ServiceAccount
# ============================================================

echo "Checking Kubernetes ServiceAccount..."

if kubectl get serviceaccount "$SERVICE_ACCOUNT" \
    -n "$NAMESPACE" \
    >/dev/null 2>&1; then

    echo "ServiceAccount already exists."

else

    echo "Creating Kubernetes ServiceAccount..."

    kubectl create serviceaccount \
        "$SERVICE_ACCOUNT" \
        -n "$NAMESPACE"

    echo "ServiceAccount created."
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
echo "Managed by Terraform."
echo "Verify with:"
echo
echo "  terraform state list | grep aws_eks_pod_identity_association"
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