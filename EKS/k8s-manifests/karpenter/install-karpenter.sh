#!/bin/bash
set -euo pipefail

export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.14.0"
export CLUSTER_NAME="eks-cluster-dev"
export AWS_REGION="us-east-1"

echo "======================================"
echo "Installing Karpenter ${KARPENTER_VERSION}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Region:  ${AWS_REGION}"
echo "======================================"

# --------------------------------------------------
# 1. Check prerequisites
# --------------------------------------------------

echo "Checking prerequisites..."

command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed."
    exit 1
}

command -v helm >/dev/null 2>&1 || {
    echo "ERROR: helm is not installed."
    exit 1
}

echo "kubectl: OK"
echo "helm:    OK"

# --------------------------------------------------
# 2. Check cluster connectivity
# --------------------------------------------------

echo "Checking Kubernetes connectivity..."

kubectl cluster-info

# --------------------------------------------------
# 3. Install Karpenter CRDs
# --------------------------------------------------

echo "Installing Karpenter CRDs..."

helm upgrade --install karpenter-crd \
  oci://public.ecr.aws/karpenter/karpenter-crd \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --create-namespace \
  --wait

echo "Karpenter CRDs installed."

# --------------------------------------------------
# 4. Install Karpenter controller
# --------------------------------------------------

echo "Installing Karpenter controller..."

helm upgrade --install karpenter \
  oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.enableZonalShift=false" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

echo "Karpenter controller installed."

# --------------------------------------------------
# 5. Wait for controller
# --------------------------------------------------

echo "Waiting for Karpenter controller..."

kubectl rollout status deployment/karpenter \
  -n "${KARPENTER_NAMESPACE}" \
  --timeout=5m

# --------------------------------------------------
# 6. Apply NodeClass
# --------------------------------------------------

echo "Applying EC2NodeClass..."

kubectl apply -f nodeclass.yaml

# --------------------------------------------------
# 7. Apply NodePool
# --------------------------------------------------

echo "Applying NodePool..."

kubectl apply -f nodepool.yaml

# --------------------------------------------------
# 8. Verify
# --------------------------------------------------

echo ""
echo "======================================"
echo "Karpenter installation completed!"
echo "======================================"

echo ""
echo "Karpenter pods:"
kubectl get pods -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter

echo ""
echo "NodePools:"
kubectl get nodepool

echo ""
echo "EC2NodeClasses:"
kubectl get ec2nodeclass