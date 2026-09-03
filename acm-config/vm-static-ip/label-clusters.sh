#!/bin/bash
# Script to label ManagedClusters for VM Static IP workload
# This enables dynamic cluster discovery by ApplicationSets
#
# Usage:
#   ./label-clusters.sh <cluster-name>
#
# Example:
#   ./label-clusters.sh ammahapa-prd-c1
#   ./label-clusters.sh ammahapa-prd-c3  # Adding a new cluster

set -e

CLUSTER_NAME="${1}"

if [ -z "${CLUSTER_NAME}" ]; then
    echo "Usage: $0 <cluster-name>"
    echo ""
    echo "Example:"
    echo "  $0 ammahapa-prd-c1"
    echo "  $0 ammahapa-prd-c2"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Labeling cluster: ${CLUSTER_NAME}${NC}"

# Check if cluster exists
if ! oc get managedcluster "${CLUSTER_NAME}" &>/dev/null; then
    echo -e "${RED}Error: ManagedCluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

# Apply labels
oc label managedcluster "${CLUSTER_NAME}" \
    dr-enabled=true \
    --overwrite

echo -e "${GREEN}✓ Successfully labeled ${CLUSTER_NAME}${NC}"
echo ""
echo "Labels applied:"
echo "  dr-enabled: true"
echo ""
echo "Verify:"
echo "  oc get managedcluster ${CLUSTER_NAME} --show-labels"
