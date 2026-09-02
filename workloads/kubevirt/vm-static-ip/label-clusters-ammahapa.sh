#!/bin/bash
# Script to label ammahapa ManagedClusters for DR deployment
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Labeling ammahapa ManagedClusters ===${NC}\n"

# Label ammahapa-prd-c1
echo -e "${YELLOW}Labeling cluster: ammahapa-prd-c1${NC}"
oc label managedcluster ammahapa-prd-c1 \
    name=ammahapa-prd-c1 \
    --overwrite

echo -e "${GREEN}✓ Successfully labeled ammahapa-prd-c1${NC}\n"

# Label ammahapa-prd-c2
echo -e "${YELLOW}Labeling cluster: ammahapa-prd-c2${NC}"
oc label managedcluster ammahapa-prd-c2 \
    name=ammahapa-prd-c2 \
    --overwrite

echo -e "${GREEN}✓ Successfully labeled ammahapa-prd-c2${NC}\n"

echo -e "${GREEN}=== Cluster Labeling Complete ===${NC}"
echo -e "\nVerify labels with:"
echo "  oc get managedclusters -L name"
