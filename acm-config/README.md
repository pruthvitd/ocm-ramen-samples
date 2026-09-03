# ACM GitOps Configuration for DR-Aware VM Workloads

**Reference Architecture**: GitOps-driven DR-aware VM static IP translation using ACM Placement, ApplicationSets, cluster-specific overlays, and User Defined Networks (UDN).

---

## 🏗️ Two-Layer Architecture

### Layer 1: Network Infrastructure (Permanent)

**Purpose**: Deploy UDN to ALL DR clusters as a cluster prerequisite

**Location**: `acm-config/vm-network-infrastructure/`

**Characteristics**:
- ✅ Deployed ONCE
- ✅ Exists on ALL DR clusters permanently
- ✅ NOT deleted during DR operations
- ✅ NOT managed by Placement
- ✅ `prune: false` - never auto-deleted

**What it does**:
- Creates `vm-static-ip` namespace with UDN label on all clusters
- Deploys UDN with cluster-specific subnets:
  - `ammahapa-prd-c1`: 192.168.100.0/24
  - `ammahapa-prd-c2`: 192.168.200.0/24

---

### Layer 2: VM Workload (DR-Protected)

**Purpose**: Deploy VM workload controlled by Placement

**Location**: `acm-config/vm-workload-dr/`

**Characteristics**:
- ✅ Placement-controlled
- ✅ Deploys to ONE cluster at a time (active cluster)
- ✅ Ramen updates Placement during DR operations
- ✅ Cluster-specific overlays translate static IPs
- ✅ `prune: true` - safe to delete and recreate

**What it does**:
- Deploys VMs to the cluster selected by Placement
- Uses cluster-specific overlay for IP translation:
  - On `ammahapa-prd-c1`: VMs get 192.168.100.x IPs
  - On `ammahapa-prd-c2`: VMs get 192.168.200.x IPs

---

## 📊 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Hub Cluster (openshift-gitops namespace)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Layer 1: Infrastructure (One-Time)                         │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Bootstrap: vm-network-infrastructure               │    │
│  │   └─> ApplicationSet: vm-network-infrastructure    │    │
│  │         ├─> Application: vm-network-ammahapa-prd-c1│    │
│  │         └─> Application: vm-network-ammahapa-prd-c2│    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  Layer 2: Workload (DR-Protected)                           │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Bootstrap: vm-static-ip-workload                   │    │
│  │   ├─> Placement: vm-static-ip-placement            │    │
│  │   │      (Updated by Ramen during DR)              │    │
│  │   └─> ApplicationSet: vm-static-ip-vms             │    │
│  │         └─> Application: vm-static-ip-ammahapa-prd-c1   │
│  │             (Follows Placement decision)           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                       │                │
         ┌─────────────┘                └─────────────┐
         ▼                                            ▼
┌──────────────────────┐                  ┌──────────────────────┐
│ ammahapa-prd-c1      │                  │ ammahapa-prd-c2      │
├──────────────────────┤                  ├──────────────────────┤
│                      │                  │                      │
│ Layer 1 (Always):    │                  │ Layer 1 (Always):    │
│  • Namespace         │                  │  • Namespace         │
│  • UDN (100.0/24)    │                  │  • UDN (200.0/24)    │
│                      │                  │                      │
│ Layer 2 (Active):    │                  │ Layer 2 (Standby):   │
│  • VM-server (.10)   │                  │  (none - ready for   │
│  • VM-client (.11)   │                  │   DR failover)       │
│                      │                  │                      │
└──────────────────────┘                  └──────────────────────┘
```

---

## 🚀 Deployment Workflow

### Prerequisites

1. **ACM installed** on hub cluster
2. **Managed clusters** imported into ACM:
   - `ammahapa-prd-c1`
   - `ammahapa-prd-c2`
3. **ManagedClusterSet** exists (e.g., `clusterset-submariner-844b61f9678d4a62b0`)
4. **OpenShift GitOps** installed on hub (NOT on managed clusters)

### Step 1: Deploy Layer 1 (Infrastructure - One Time)

```bash
# Deploy network infrastructure to ALL DR clusters
oc apply -f acm-config/vm-network-infrastructure/bootstrap-infrastructure.yaml

# Wait for UDN to deploy to both clusters (~1 minute)
watch 'oc get applications -n openshift-gitops | grep vm-network'
```

**Expected result**:
```
vm-network-infrastructure         Synced   Healthy
vm-network-ammahapa-prd-c1        Synced   Healthy
vm-network-ammahapa-prd-c2        Synced   Healthy
```

**Verify on clusters**:
```bash
# Check UDN on cluster 1
oc --context ammahapa-prd-c1 get udn -n vm-static-ip
# NAME          SUBNET
# primary-udn   192.168.100.0/24

# Check UDN on cluster 2
oc --context ammahapa-prd-c2 get udn -n vm-static-ip
# NAME          SUBNET
# primary-udn   192.168.200.0/24
```

---

### Step 2: Deploy Layer 2 (Workload - DR Protected)

```bash
# Deploy VM workload (goes to Placement-selected cluster)
oc apply -f acm-config/vm-workload-dr/bootstrap-workload.yaml

# Wait for VMs to deploy (~2 minutes)
watch 'oc get applications -n openshift-gitops | grep vm-static-ip'
```

**Expected result**:
```
vm-static-ip-workload             Synced   Healthy
vm-static-ip-ammahapa-prd-c1      Synced   Healthy
```

**Verify VMs**:
```bash
# Check VMs on active cluster (ammahapa-prd-c1)
oc --context ammahapa-prd-c1 get vm -n vm-static-ip

# NAME         AGE   STATUS    READY
# vm-server    2m    Running   True
# vm-client    2m    Running   True
```

---

## 🔄 DR Operations

### Enroll in Ramen DR Protection

After deploying Layer 2, enroll the workload in Ramen DR:

```bash
# Create DRPlacementControl
oc apply -f - <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPlacementControl
metadata:
  name: vm-static-ip-drpc
  namespace: openshift-gitops
spec:
  placementRef:
    name: vm-static-ip-placement
    kind: Placement
  drPolicyRef:
    name: your-dr-policy
  preferredCluster: ammahapa-prd-c1
  pvcSelector:
    matchLabels:
      appname: vm-cloudinit-static-ip
EOF
```

---

### Failover (c1 → c2)

**Trigger DR failover**:
```bash
# Update DRPC action to failover
oc patch drpc vm-static-ip-drpc -n openshift-gitops \
  --type merge \
  -p '{"spec":{"action":"Failover","failoverCluster":"ammahapa-prd-c2"}}'
```

**What happens automatically**:

1. **Ramen updates Placement**:
   ```yaml
   spec:
     predicates:
       - requiredClusterSelector:
           matchLabels:
             name: ammahapa-prd-c2  # ← Changed by Ramen
   ```

2. **ApplicationSet detects Placement change**:
   - Deletes Application for `ammahapa-prd-c1`
   - Creates Application for `ammahapa-prd-c2`

3. **Overlay automatically switches**:
   - Path changes to: `overlays/ammahapa-prd-c2-vms`
   - IPs translated to 192.168.200.x

4. **VMs restored on c2 with correct IPs**:
   ```
   vm-server: 192.168.200.10  (was 192.168.100.10)
   vm-client: 192.168.200.11  (was 192.168.100.11)
   ```

**UDN infrastructure remains on BOTH clusters** - no deletion, no finalizer issues! ✅

---

### Relocate (c2 → c1)

**Trigger DR relocate**:
```bash
# Update DRPC action to relocate
oc patch drpc vm-static-ip-drpc -n openshift-gitops \
  --type merge \
  -p '{"spec":{"action":"Relocate","preferredCluster":"ammahapa-prd-c1"}}'
```

**What happens**:
- Same automatic process in reverse
- Placement returns to `ammahapa-prd-c1`
- IPs translated back to 192.168.100.x

---

## 🎯 Key Benefits of Two-Layer Architecture

| Aspect | Single-Layer (Old) | Two-Layer (New) |
|--------|-------------------|-----------------|
| **UDN Lifecycle** | Deleted with workload | Permanent on all clusters |
| **Finalizer Issues** | ❌ Common | ✅ Eliminated |
| **DR Operations** | Deletes/recreates UDN | Only moves VMs |
| **Alignment** | Infrastructure moves | Infrastructure stays, workload moves |
| **Cleanup** | Complex | Simple |
| **Real-World** | ❌ Not typical | ✅ Matches customer usage |

---

## 📝 Static IP Translation (GitOps-Native)

**The overlay approach provides**:

✅ **GitOps-native**: All config in Git  
✅ **Reversible**: Rollback = Git revert  
✅ **Auditable**: Git history shows all changes  
✅ **No runtime patching**: No ConfigMap mutation or hooks  
✅ **Declarative**: Argo CD handles the rest  

**How it works**:

```yaml
# overlays/ammahapa-prd-c1-vms/kustomization.yaml
patches:
  - target:
      kind: VirtualMachine
      name: vm-server
    patch: |-
      - op: replace
        path: /spec/template/metadata/annotations/network.kubevirt.io~1addresses
        value: '{"primary-udn":["192.168.100.10"]}'
```

When Placement switches clusters:
- ApplicationSet path changes to `overlays/ammahapa-prd-c2-vms`
- Different overlay applied
- IP automatically translated to `192.168.200.10`

---

## 🧹 Cleanup

### Delete Workload Only (Preserve Infrastructure)

```bash
# Delete Layer 2 (VMs removed from active cluster)
oc delete application vm-static-ip-workload -n openshift-gitops

# UDN remains on both clusters - ready for re-deployment!
```

### Delete Everything (Complete Cleanup)

```bash
# Delete Layer 2 (workload)
oc delete application vm-static-ip-workload -n openshift-gitops

# Delete Layer 1 (infrastructure)
oc delete application vm-network-infrastructure -n openshift-gitops

# Wait for cascade deletion (~2 minutes)
# Both UDN and VMs removed from all clusters
```

---

## 🎓 Use Case Positioning

**Position this as**:

> A GitOps-driven reference architecture demonstrating DR-aware VM static IP translation using ACM Placement, ApplicationSets, cluster-specific overlays, and UDNs.

**Key value propositions**:

1. **Static IP preservation** across DR sites with different subnets
2. **GitOps-native** approach (no runtime patching)
3. **ACM integration** (Placement-driven deployment)
4. **DR automation** (Ramen updates Placement, IPs translate automatically)
5. **Two-layer separation** (infrastructure vs. workload)

---

## 🚀 Future: Ideal UX

**Vision for productization**:

```
ACM Console → Applications → Create Application
  
  Select Template: "VM with Static IP + DR"
  
  Configuration:
    ├─ Workload Name: my-vm-app
    ├─ Enable DR: ✓
    ├─ Primary Cluster: ammahapa-prd-c1
    ├─ Secondary Cluster: ammahapa-prd-c2
    ├─ Primary Subnet: 192.168.100.0/24
    └─ Secondary Subnet: 192.168.200.0/24
  
  Click: Create
  
  → Everything deployed automatically!
  → DR protection enabled!
  → Ready for failover/relocate!
```

---

## 📚 Additional Documentation

- **Sync Waves**: See `acm-config/vm-static-ip/SYNC_WAVES.md` (old single-layer approach)
- **Cluster Labeling**: See `acm-config/vm-static-ip/label-clusters.sh`
- **Workload Overlays**: See `workloads/kubevirt/vm-static-ip/overlays/`

---

## ✅ Summary

**Two layers**:
1. **Infrastructure** (permanent, all clusters)
2. **Workload** (DR-protected, Placement-controlled)

**Deploy order**:
1. Layer 1 first (infrastructure)
2. Layer 2 second (workload)

**DR operations**:
- Ramen updates Placement
- ApplicationSet follows Placement
- Overlay switches automatically
- IPs translated correctly

**No finalizer issues, clean lifecycle, production-ready!** 🎯
