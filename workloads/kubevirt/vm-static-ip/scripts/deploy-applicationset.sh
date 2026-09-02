#!/bin/bash
# Script to deploy the ApplicationSet for DR-enabled VM workload
# This creates the ApplicationSet on the hub cluster which will then
# deploy the VMs to each labeled DR cluster with the correct overlay

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying ApplicationSet for VM Static IP DR ===${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="$(dirname "${SCRIPT_DIR}")"
APPSET_FILE="${WORKLOAD_DIR}/applicationset.yaml"

# Check if ApplicationSet file exists
if [[ ! -f "${APPSET_FILE}" ]]; then
    echo -e "${RED}Error: ApplicationSet file not found: ${APPSET_FILE}${NC}"
    exit 1
fi

# Check if user is logged into OpenShift
if ! oc whoami &>/dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift. Please login first.${NC}"
    exit 1
fi

# Check if openshift-gitops namespace exists
if ! oc get namespace openshift-gitops &>/dev/null; then
    echo -e "${YELLOW}Warning: openshift-gitops namespace not found${NC}"
    echo -e "${YELLOW}You may need to install OpenShift GitOps Operator first${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${BLUE}Applying ApplicationSet...${NC}"
oc apply -f "${APPSET_FILE}"

echo -e "\n${GREEN}✓ ApplicationSet deployed successfully${NC}\n"

echo -e "${YELLOW}Checking ApplicationSet status...${NC}"
sleep 2
oc get applicationset -n openshift-gitops vm-static-ip-dr

echo -e "\n${YELLOW}Generated Applications:${NC}"
oc get applications -n openshift-gitops -l app=vm-static-ip

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "\nNext steps:"
echo "  1. Monitor the Application sync status:"
echo "     oc get applications -n openshift-gitops -l app=vm-static-ip -w"
echo ""
echo "  2. Check the VMs on each cluster:"
echo "     oc get vms -n vm-static-ip --context dr1"
echo "     oc get vms -n vm-static-ip --context dr2"
echo ""
echo "  3. Verify the UDN configuration:"
echo "     oc get userdefinednetwork -n vm-static-ip --context dr1"
echo "     oc get userdefinednetwork -n vm-static-ip --context dr2"
