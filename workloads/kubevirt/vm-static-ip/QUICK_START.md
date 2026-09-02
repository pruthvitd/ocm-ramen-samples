# Quick Start Guide - VM Static IP with UDN

## 5-Minute Deployment via UI

### Prerequisites Check
```bash
# Verify clusters labeled
oc get managedclusters -L name

# Should show:
# dr1   name=dr1
# dr2   name=dr2
```

### Step 1: Deploy UDN Infrastructure (Both Clusters)

**OpenShift Console → Operators → OpenShift GitOps → ApplicationSet → Create**

Paste this YAML:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: vm-static-ip-udn
  namespace: openshift-gitops
spec:
  generators:
    - clusters:
        selector:
          matchExpressions:
            - key: name
              operator: In
              values: [dr1, dr2]
  template:
    metadata:
      name: 'vm-static-ip-udn-{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/pruthvitd/ocm-ramen-samples.git
        targetRevision: gitops-udn-primary-vm
        path: 'workloads/kubevirt/vm-static-ip/overlays/{{name}}-udn'
      destination:
        server: '{{server}}'
        namespace: vm-static-ip
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

✅ **Verify**: `oc get applications -n openshift-gitops -l app=vm-static-ip-udn`  
Should see 2 apps (dr1 and dr2)

---

### Step 2: Create Placement

**Terminal**:
```bash
oc apply -f - <<EOF
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
            name: dr1
EOF
```

✅ **Verify**: `oc get placement -n vm-static-ip`

---

### Step 3: Deploy VM Application (Active Cluster Only)

**OpenShift Console → Operators → OpenShift GitOps → ApplicationSet → Create**

Paste this YAML:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: vm-static-ip-vms
  namespace: openshift-gitops
spec:
  generators:
    - clusterDecisionResource:
        configMapRef: acm-placement
        labelSelector:
          matchLabels:
            cluster.open-cluster-management.io/placement: vm-static-ip-placement
        requeueAfterSeconds: 30
  template:
    metadata:
      name: 'vm-static-ip-vms-{{clusterName}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/pruthvitd/ocm-ramen-samples.git
        targetRevision: gitops-udn-primary-vm
        path: 'workloads/kubevirt/vm-static-ip/overlays/{{clusterName}}-vms'
      destination:
        server: '{{server}}'
        namespace: vm-static-ip
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

✅ **Verify**: `oc --context dr1 get vms -n vm-static-ip`  
Should see `vm-server` and `vm-client` running

---

### Step 4: (Optional) Setup DR Protection

**ACM UI → Infrastructure → Disaster Recovery**

1. **Create DRPolicy**:
   - Name: `dr1-dr2-policy`
   - Clusters: `dr1`, `dr2`
   - Interval: `5m`

2. **Create DRPlacementControl**:
   - Name: `vm-static-ip-drpc`
   - Namespace: `vm-static-ip`
   - DRPolicy: `dr1-dr2-policy`
   - Placement: `vm-static-ip-placement`
   - PVC Selector: `appname=vm-cloudinit-static-ip`
   - Preferred: `dr1`

---

## What You Get

| Component | Location | Configuration |
|-----------|----------|---------------|
| **UDN on dr1** | dr1 cluster | 192.168.100.0/24 |
| **UDN on dr2** | dr2 cluster | 192.168.200.0/24 |
| **VMs active** | dr1 (per Placement) | .10, .11 IPs |
| **VMs standby** | dr2 (ready for failover) | .10, .11 IPs (different subnet) |

---

## Test DR Failover

**ACM UI → Infrastructure → Disaster Recovery → DRPlacementControl**

1. Click: `vm-static-ip-drpc`
2. Actions → **Failover**
3. Target: `dr2`
4. Click: **Initiate**

**What happens automatically**:
- Placement changes to dr2
- VM ApplicationSet detects change
- VMs deploy to dr2 with 192.168.200.x IPs
- No manual intervention needed!

---

## Verification Commands

```bash
# Check all Applications
oc get applications -n openshift-gitops

# Check UDN on both clusters
oc --context dr1 get udn -n vm-static-ip -o jsonpath='{.items[0].spec.layer2.subnets}'
oc --context dr2 get udn -n vm-static-ip -o jsonpath='{.items[0].spec.layer2.subnets}'

# Check active VMs
oc --context dr1 get vms -n vm-static-ip
oc --context dr2 get vms -n vm-static-ip

# Check VM IPs
oc get vm vm-server -n vm-static-ip -o jsonpath='{.spec.template.metadata.annotations.network\.kubevirt\.io/addresses}'
```

---

## Troubleshooting Quick Fixes

**Problem**: ApplicationSet created but no Applications generated  
**Fix**: Check cluster labels: `oc get managedclusters -L name`

**Problem**: Applications created but not syncing  
**Fix**: Check Git repo accessible and path exists

**Problem**: VMs not starting  
**Fix**: Verify UDN exists: `oc get udn -n vm-static-ip`

**Problem**: Wrong IPs after failover  
**Fix**: Check which overlay deployed: `oc get app <name> -o yaml | grep path`

---

## Full Documentation

- **UI Deployment Guide**: [DEPLOYMENT_GUIDE_UI.md](./DEPLOYMENT_GUIDE_UI.md)
- **Architecture & Details**: [README.md](./README.md)
- **CLI Scripts**: [scripts/](./scripts/)
