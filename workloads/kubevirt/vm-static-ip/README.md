# VM Static IP with UDN Primary - DR ApplicationSets

This directory contains ACM ApplicationSets for deploying KubeVirt VMs with static IPs on UDN (User Defined Network) Primary across DR clusters.

## 📚 Documentation

- **[Quick Start Guide](./QUICK_START.md)** - 5-minute deployment via UI (start here!)
- **[UI Deployment Guide](./DEPLOYMENT_GUIDE_UI.md)** - Complete step-by-step UI walkthrough
- **[Architecture Guide](./ARCHITECTURE.md)** - Pull model architecture (where components run)
- **Architecture & Details** - This document (technical reference)

## ❓ FAQ

**Q: Do DR clusters (dr1, dr2) need Argo CD / OpenShift GitOps installed?**  
**A:** ❌ **NO!** Only the **hub cluster** needs OpenShift GitOps. The hub's Argo CD deploys to managed clusters via Kubernetes API. See [ARCHITECTURE.md](./ARCHITECTURE.md) for details.

## Architecture

**Separation of Concerns**:
- **UDN Infrastructure**: Deployed to ALL DR clusters upfront (network foundation)
- **VM Application**: Deployed ONLY to the active cluster selected by Placement (follows DR decisions)

**Two ApplicationSets**:
1. `applicationset-udn.yaml` - Deploys UDN to both dr1 AND dr2
2. `applicationset-vms.yaml` - Deploys VMs to the cluster selected by Placement

**Automatic IP Assignment**: Each site gets its own overlay with:
- UDN subnet configuration (different per site)
- Static IP addresses for VMs (different per site)
- Persistent IPAM for IP retention across migrations

## Directory Structure

```
workloads/kubevirt/vm-static-ip/
├── applicationset-udn.yaml      # UDN infrastructure (ALL clusters)
├── applicationset-vms.yaml      # VM application (Placement cluster)
├── base/                        # Original combined base
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── udn.yaml
│   └── vm.yaml
├── base-udn/                    # UDN-only base
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── udn.yaml
├── base-vms/                    # VMs-only base
│   ├── kustomization.yaml
│   └── vm.yaml
├── overlays/
│   ├── dr1-udn/                 # DR1 network overlay
│   │   └── kustomization.yaml   # Subnet: 192.168.100.0/24
│   ├── dr1-vms/                 # DR1 application overlay
│   │   └── kustomization.yaml   # IPs: .10, .11
│   ├── dr2-udn/                 # DR2 network overlay
│   │   └── kustomization.yaml   # Subnet: 192.168.200.0/24
│   └── dr2-vms/                 # DR2 application overlay
│       └── kustomization.yaml   # IPs: .10, .11
└── scripts/
    ├── label-clusters.sh
    ├── verify-overlays.sh
    └── deploy-applicationset.sh
```

## IP Assignment

| Site | Cluster | Subnet           | vm-server       | vm-client       |
|------|---------|------------------|-----------------|-----------------|
| DR1  | dr1     | 192.168.100.0/24 | 192.168.100.10  | 192.168.100.11  |
| DR2  | dr2     | 192.168.200.0/24 | 192.168.200.10  | 192.168.200.11  |

## Deployment Steps

### 1. Label Your ManagedClusters

```bash
# Label clusters so ApplicationSets can find them
oc label managedcluster dr1 name=dr1 --overwrite
oc label managedcluster dr2 name=dr2 --overwrite

# Verify labels
oc get managedclusters -L name
```

### 2. Verify Overlays Locally (Optional)

```bash
# Test UDN overlays
kustomize build overlays/dr1-udn | grep -A1 "subnets:"
kustomize build overlays/dr2-udn | grep -A1 "subnets:"

# Test VM overlays
kustomize build overlays/dr1-vms | grep "network.kubevirt.io/addresses"
kustomize build overlays/dr2-vms | grep "network.kubevirt.io/addresses"
```

### 3. Deploy UDN Infrastructure (to ALL clusters)

```bash
# Deploy UDN to both dr1 and dr2
oc apply -f applicationset-udn.yaml

# Verify UDN Applications created
oc get applications -n openshift-gitops -l app=vm-static-ip-udn

# Wait for sync
oc get applications -n openshift-gitops -l app=vm-static-ip-udn -w
```

### 4. Create Placement (via UI or CLI)

This determines which cluster runs the VMs.

**Option A: CLI**
```bash
cat <<EOF | oc apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: vm-static-ip-placement
  namespace: vm-static-ip
spec:
  numberOfClusters: 1
  predicates:
    - requiredClusterSelector:
        labelSelector:
          matchLabels:
            name: dr1  # Start on dr1
EOF
```

**Option B: ACM UI**
1. Go to Applications → Placements
2. Create new Placement
3. Name: `vm-static-ip-placement`
4. Select cluster: `dr1`

### 5. Deploy VM Application (follows Placement)

```bash
# Deploy VMs (will go to cluster selected by Placement)
oc apply -f applicationset-vms.yaml

# Verify VM Application created
oc get applications -n openshift-gitops -l app=vm-static-ip-vms

# Check VMs on active cluster
oc --context dr1 get vms -n vm-static-ip
```

## DR Operations (via ACM UI)

### Setup (One-time)
1. Create **DRPolicy** (Infrastructure → Disaster Recovery)
   - Name: `dr1-dr2-policy`
   - Peer clusters: `dr1`, `dr2`
   - Replication interval: `5m`
   - PVC selector: `appname=vm-cloudinit-static-ip`

2. Create **DRPlacementControl** (Infrastructure → Disaster Recovery)
   - Name: `vm-static-ip-drpc`
   - Namespace: `vm-static-ip`
   - Link to DRPolicy: `dr1-dr2-policy`
   - Link to Placement: `vm-static-ip-placement`
   - Preferred cluster: `dr1`

### Failover (Unplanned DR Event)
1. Go to DRPlacementControl: `vm-static-ip-drpc`
2. Click **Failover**
3. Select target cluster: `dr2`
4. Confirm

**What happens**:
- Placement updates to point to `dr2`
- ApplicationSet-VMs sees the Placement change
- Deploys `overlays/dr2-vms` to dr2
- VMs come up with `192.168.200.x` IPs (dr2 subnet)
- UDN already exists on dr2 (was pre-deployed)

### Relocate (Planned Migration)
1. Go to DRPlacementControl: `vm-static-ip-drpc`
2. Click **Relocate**
3. Select target cluster: `dr2` (or back to `dr1`)
4. Confirm

**Result**: Graceful migration with correct IPs for destination site

## How It Works

### UDN ApplicationSet (Infrastructure)
```yaml
# Deploys to ALL clusters (dr1 AND dr2)
generators:
  - clusters:
      selector:
        matchExpressions:
          - key: name
            operator: In
            values: [dr1, dr2]

template:
  spec:
    source:
      path: 'workloads/kubevirt/vm-static-ip/overlays/{{name}}-udn'
```

**Result**: Both clusters get UDN with their respective subnets

### VM ApplicationSet (Application)
```yaml
# Deploys ONLY to Placement decision cluster
generators:
  - clusterDecisionResource:
      labelSelector:
        matchLabels:
          cluster.open-cluster-management.io/placement: vm-static-ip-placement

template:
  spec:
    source:
      path: 'workloads/kubevirt/vm-static-ip/overlays/{{clusterName}}-vms'
```

**Result**: VMs deploy only to active cluster with correct IPs

### DR Failover Flow
1. **Before**: VMs on dr1 (192.168.100.x), UDN on both clusters
2. **Failover**: Placement changes dr1 → dr2
3. **ApplicationSet-VMs**: Detects Placement change
4. **Auto-deploy**: Applies `overlays/dr2-vms` to dr2
5. **Result**: VMs on dr2 with 192.168.200.x IPs

## Customization

### Adding More DR Sites

1. **Create UDN overlay**:
   ```bash
   mkdir -p overlays/dr3-udn
   # Copy and modify kustomization.yaml with new subnet
   ```

2. **Create VM overlay**:
   ```bash
   mkdir -p overlays/dr3-vms
   # Copy and modify kustomization.yaml with new IPs
   ```

3. **Update UDN ApplicationSet**:
   ```yaml
   values: [dr1, dr2, dr3]
   ```

### Changing IP Addresses

Edit the overlay's `kustomization.yaml` and update the patch values:
- UDN overlay: Change subnet
- VM overlay: Change individual VM IPs

## Monitoring & Troubleshooting

### Check Deployment Status
```bash
# UDN Applications (should see 2: dr1 and dr2)
oc get applications -n openshift-gitops -l app=vm-static-ip-udn

# VM Application (should see 1: on active cluster)
oc get applications -n openshift-gitops -l app=vm-static-ip-vms

# Check which cluster has VMs
oc --context dr1 get vms -n vm-static-ip
oc --context dr2 get vms -n vm-static-ip
```

### Verify UDN Configuration
```bash
# Check UDN on both clusters
oc --context dr1 get userdefinednetwork -n vm-static-ip primary-udn -o yaml
oc --context dr2 get userdefinednetwork -n vm-static-ip primary-udn -o yaml

# Verify subnets are different
oc --context dr1 get userdefinednetwork -n vm-static-ip primary-udn -o jsonpath='{.spec.layer2.subnets}'
oc --context dr2 get userdefinednetwork -n vm-static-ip primary-udn -o jsonpath='{.spec.layer2.subnets}'
```

### Common Issues

**VMs not starting after failover**:
- Verify UDN exists on target cluster: `oc get userdefinednetwork -n vm-static-ip`
- Check VM events: `oc describe vm -n vm-static-ip vm-server`
- Verify namespace has UDN annotation: `oc get ns vm-static-ip -o yaml | grep primary-user-defined-network`

**Wrong IPs after DR migration**:
- Check which overlay is deployed: `oc get application -n openshift-gitops <app-name> -o yaml | grep path`
- Verify VM annotations: `oc get vm vm-server -n vm-static-ip -o jsonpath='{.spec.template.metadata.annotations}'`

**ApplicationSet not creating VM Application**:
- Check Placement exists: `oc get placement -n vm-static-ip`
- Verify PlacementDecision: `oc get placementdecision -n vm-static-ip`
- Check ApplicationSet status: `oc describe applicationset -n openshift-gitops vm-static-ip-vms`

## References

- [ACM ApplicationSet Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/)
- [ACM ClusterDecisionResource Generator](https://argocd-applicationset.readthedocs.io/en/stable/Generators-Cluster-Decision-Resource/)
- [Ramen DR Documentation](https://ramendr.github.io/ramen/)
- [KubeVirt UDN Documentation](https://kubevirt.io/user-guide/network/user_defined_networks/)
