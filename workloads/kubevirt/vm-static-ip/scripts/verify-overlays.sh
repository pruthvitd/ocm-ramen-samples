#!/bin/bash
# Script to verify that kustomize overlays generate correct manifests
# This validates that each overlay produces the expected IP addresses and subnets

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Verifying Kustomize Overlays ===${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="$(dirname "${SCRIPT_DIR}")"

# Function to verify an overlay
verify_overlay() {
    local overlay_name=$1
    local expected_subnet=$2
    local expected_server_ip=$3
    local expected_client_ip=$4

    echo -e "${BLUE}Verifying overlay: ${overlay_name}${NC}"

    local overlay_path="${WORKLOAD_DIR}/overlays/${overlay_name}"

    if [[ ! -d "${overlay_path}" ]]; then
        echo -e "${RED}Error: Overlay directory not found: ${overlay_path}${NC}"
        return 1
    fi

    # Build the overlay
    local manifest
    manifest=$(kustomize build "${overlay_path}" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Failed to build overlay${NC}"
        echo "${manifest}"
        return 1
    fi

    # Check subnet
    if echo "${manifest}" | grep -q "subnets:" && echo "${manifest}" | grep -A1 "subnets:" | grep -q "${expected_subnet}"; then
        echo -e "${GREEN}✓ Subnet correct: ${expected_subnet}${NC}"
    else
        echo -e "${RED}✗ Subnet mismatch! Expected: ${expected_subnet}${NC}"
        return 1
    fi

    # Check VM server IP
    if echo "${manifest}" | grep -q "vm-server" && echo "${manifest}" | grep -A20 "name: vm-server" | grep -q "${expected_server_ip}"; then
        echo -e "${GREEN}✓ VM Server IP correct: ${expected_server_ip}${NC}"
    else
        echo -e "${RED}✗ VM Server IP mismatch! Expected: ${expected_server_ip}${NC}"
        return 1
    fi

    # Check VM client IP
    if echo "${manifest}" | grep -q "vm-client" && echo "${manifest}" | grep -A20 "name: vm-client" | grep -q "${expected_client_ip}"; then
        echo -e "${GREEN}✓ VM Client IP correct: ${expected_client_ip}${NC}"
    else
        echo -e "${RED}✗ VM Client IP mismatch! Expected: ${expected_client_ip}${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Overlay ${overlay_name} verified successfully${NC}\n"
}

# Verify DR1 overlay
verify_overlay "dr1" "192.168.100.0/24" "192.168.100.10" "192.168.100.11"

# Verify DR2 overlay
verify_overlay "dr2" "192.168.200.0/24" "192.168.200.10" "192.168.200.11"

echo -e "${GREEN}=== All Overlays Verified Successfully ===${NC}"
