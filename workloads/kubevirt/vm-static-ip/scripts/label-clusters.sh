#!/bin/bash
# Script to label ManagedClusters for DR deployment
# This script adds the necessary labels to your DR clusters so that
# the ApplicationSet can properly identify and configure them.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== DR Cluster Labeling Script ===${NC}\n"

# Function to label a cluster
label_cluster() {
    local cluster_name=$1
    local site=$2
    local vm_server_ip=$3
    local vm_client_ip=$4

    echo -e "${YELLOW}Labeling cluster: ${cluster_name}${NC}"
    echo "  Site: ${site}"
    echo "  VM Server IP: ${vm_server_ip}"
    echo "  VM Client IP: ${vm_client_ip}"

    # Check if cluster exists
    if ! oc get managedcluster "${cluster_name}" &>/dev/null; then
        echo -e "${RED}Error: ManagedCluster '${cluster_name}' not found${NC}"
        return 1
    fi

    # Apply labels
    oc label managedcluster "${cluster_name}" \
        site="${site}" \
        vm-server-ip="${vm_server_ip}" \
        vm-client-ip="${vm_client_ip}" \
        --overwrite

    echo -e "${GREEN}✓ Successfully labeled ${cluster_name}${NC}\n"
}

# Label DR1 (Primary Site)
label_cluster "dr1" "primary" "192.168.100.10" "192.168.100.11"

# Label DR2 (Secondary Site)
label_cluster "dr2" "secondary" "192.168.200.10" "192.168.200.11"

echo -e "${GREEN}=== Cluster Labeling Complete ===${NC}"
echo -e "\nYou can verify the labels with:"
echo "  oc get managedclusters -L site,vm-server-ip,vm-client-ip"
