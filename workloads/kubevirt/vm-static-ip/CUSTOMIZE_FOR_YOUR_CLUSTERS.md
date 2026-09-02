# Customizing for Your Cluster Names

This guide shows how to adapt the ApplicationSets and overlays for your actual ManagedCluster names.

## Your Cluster Names

- **Cluster 1**: `ammahapa-prd-c1`
- **Cluster 2**: `ammahapa-prd-c2`

These are the names that will appear in your DRPolicy:

```yaml
spec:
  drClusters:
    - ammahapa-prd-c1
    - ammahapa-prd-c2
```

---

## Option 1: Use Full Cluster Names (Recommended)

This approach uses your actual cluster names throughout.

### Step 1: Label ManagedClusters

```bash
# Label with actual cluster names
oc label managedcluster ammahapa-prd-c1 name=ammahapa-prd-c1 --overwrite
oc label managedcluster ammahapa-prd-c2 name=ammahapa-prd-c2 --overwrite

# Verify
oc get managedclusters -L name
```

Expected output:
```
NAME                HUB ACCEPTED   NAME
ammahapa-prd-c1     true           ammahapa-prd-c1
ammahapa-prd-c2     true           ammahapa-prd-c2
```

### Step 2: Create Overlays with Your Cluster Names

```bash
# Create overlay directories matching your cluster names
mkdir -p overlays/{ammahapa-prd-c1-udn,ammahapa-prd-c1-vms}
mkdir -p overlays/{ammahapa-prd-c2-udn,ammahapa-prd-c2-vms}

# Copy existing overlays as templates
cp overlays/dr1-udn/kustomization.yaml overlays/ammahapa-prd-c1-udn/
cp overlays/dr1-vms/kustomization.yaml overlays/ammahapa-prd-c1-vms/
cp overlays/dr2-udn/kustomization.yaml overlays/ammahapa-prd-c2-udn/
cp overlays/dr2-vms/kustomization.yaml overlays/ammahapa-prd-c2-vms/
```

Overlay directory structure will be:
```
overlays/
├── ammahapa-prd-c1-udn/    # Cluster 1 network
├── ammahapa-prd-c1-vms/    # Cluster 1 VMs
├── ammahapa-prd-c2-udn/    # Cluster 2 network
└── ammahapa-prd-c2-vms/    # Cluster 2 VMs
```

### Step 3: Update ApplicationSet - UDN

Update the cluster values in `applicationset-udn.yaml`:

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
              values:
                - ammahapa-prd-c1    # ← Your cluster name
                - ammahapa-prd-c2    # ← Your cluster name

  template:
    metadata:
      name: 'vm-static-ip-udn-{{name}}'
      labels:
        app: vm-static-ip-udn
        cluster: '{{name}}'

    spec:
      project: default

      source:
        repoURL: https://github.com/pruthvitd/ocm-ramen-samples.git
        targetRevision: gitops-udn-primary-vm
        # This will generate:
        # - overlays/ammahapa-prd-c1-udn for cluster 1
        # - overlays/ammahapa-prd-c2-udn for cluster 2
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

### Step 4: Update Placement

```yaml
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
            name: ammahapa-prd-c1  # ← Start on cluster 1
```

### Step 5: ApplicationSet for VMs (No Change Needed!)

The VM ApplicationSet uses `{{clusterName}}` which automatically picks up the cluster name from PlacementDecision:

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
        # {{clusterName}} will be ammahapa-prd-c1 or ammahapa-prd-c2
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

---

## Option 2: Use Shorter Aliases (Alternative)

If you prefer shorter names in overlays, use label aliases:

### Step 1: Label with Aliases

```bash
# Label with shorter aliases
oc label managedcluster ammahapa-prd-c1 site=c1 --overwrite
oc label managedcluster ammahapa-prd-c2 site=c2 --overwrite
```

### Step 2: Update ApplicationSet Selector

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          site: c1  # or site: c2
```

### Step 3: Keep Existing Overlays

Rename existing overlays:
```bash
mv overlays/dr1-udn overlays/c1-udn
mv overlays/dr1-vms overlays/c1-vms
mv overlays/dr2-udn overlays/c2-udn
mv overlays/dr2-vms overlays/c2-vms
```

**Note**: This approach separates the ManagedCluster name (used in DRPolicy) from the overlay path, which can be confusing.

---

## Recommended: Option 1 (Full Names)

Use **Option 1** for clarity and consistency:

| Component | Value |
|-----------|-------|
| ManagedCluster name | `ammahapa-prd-c1`, `ammahapa-prd-c2` |
| Label | `name=ammahapa-prd-c1`, `name=ammahapa-prd-c2` |
| Overlay path | `overlays/ammahapa-prd-c1-udn`, `overlays/ammahapa-prd-c1-vms` |
| DRPolicy clusters | `ammahapa-prd-c1`, `ammahapa-prd-c2` |

**Advantages**:
- ✅ Consistent naming everywhere
- ✅ Easy to trace from ApplicationSet → Overlay → Cluster
- ✅ DRPolicy cluster names match exactly
- ✅ No confusion between aliases and actual names

---

## Complete Example with Your Cluster Names

### Directory Structure

```
workloads/kubevirt/vm-static-ip/
├── overlays/
│   ├── ammahapa-prd-c1-udn/
│   │   └── kustomization.yaml    # 192.168.100.0/24
│   ├── ammahapa-prd-c1-vms/
│   │   └── kustomization.yaml    # IPs: .10, .11
│   ├── ammahapa-prd-c2-udn/
│   │   └── kustomization.yaml    # 192.168.200.0/24
│   └── ammahapa-prd-c2-vms/
│       └── kustomization.yaml    # IPs: .10, .11
```

### What Gets Deployed

**When Placement selects ammahapa-prd-c1**:
```
ApplicationSet-UDN generates:
  - vm-static-ip-udn-ammahapa-prd-c1 → overlays/ammahapa-prd-c1-udn
  - vm-static-ip-udn-ammahapa-prd-c2 → overlays/ammahapa-prd-c2-udn

ApplicationSet-VMs generates:
  - vm-static-ip-vms-ammahapa-prd-c1 → overlays/ammahapa-prd-c1-vms
```

**After DR Failover to ammahapa-prd-c2**:
```
ApplicationSet-VMs updates:
  - vm-static-ip-vms-ammahapa-prd-c2 → overlays/ammahapa-prd-c2-vms
```

---

## DRPolicy Configuration

Your DRPolicy will look like this:

```yaml
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPolicy
metadata:
  name: ammahapa-prd-policy
spec:
  schedulingInterval: 5m
  
  drClusters:
    - ammahapa-prd-c1    # ← Exact ManagedCluster name
    - ammahapa-prd-c2    # ← Exact ManagedCluster name
  
  pvcSelector:
    matchLabels:
      appname: vm-cloudinit-static-ip
```

**Important**: The names in `drClusters` MUST match the ManagedCluster resource names exactly.

---

## Verification Steps

### 1. Verify Cluster Labels

```bash
oc get managedclusters ammahapa-prd-c1 -o yaml | grep -A5 "labels:"
```

Expected:
```yaml
labels:
  name: ammahapa-prd-c1
```

### 2. Test Overlay Builds

```bash
# Test cluster 1 UDN overlay
kustomize build overlays/ammahapa-prd-c1-udn | grep -A1 "subnets:"

# Test cluster 1 VMs overlay
kustomize build overlays/ammahapa-prd-c1-vms | grep "network.kubevirt.io/addresses"
```

### 3. Check ApplicationSet Generation

After deploying ApplicationSet-UDN:

```bash
oc get applications -n openshift-gitops -l app=vm-static-ip-udn
```

Expected:
```
NAME                               SYNC STATUS
vm-static-ip-udn-ammahapa-prd-c1   Synced
vm-static-ip-udn-ammahapa-prd-c2   Synced
```

### 4. Verify Resources on Clusters

```bash
# On cluster 1
oc --context ammahapa-prd-c1 get udn -n vm-static-ip

# On cluster 2
oc --context ammahapa-prd-c2 get udn -n vm-static-ip
```

---

## Quick Migration Script

If you want to rename the existing overlays:

```bash
#!/bin/bash
# Rename overlays for your cluster names

cd workloads/kubevirt/vm-static-ip/overlays

# Rename dr1 overlays to ammahapa-prd-c1
mv dr1-udn ammahapa-prd-c1-udn
mv dr1-vms ammahapa-prd-c1-vms

# Rename dr2 overlays to ammahapa-prd-c2
mv dr2-udn ammahapa-prd-c2-udn
mv dr2-vms ammahapa-prd-c2-vms

echo "✅ Overlays renamed successfully"
ls -la
```

Then update your ApplicationSets to use the new cluster names as shown above.

---

## Summary

**Yes, label your ManagedClusters with their actual names**:

```bash
oc label managedcluster ammahapa-prd-c1 name=ammahapa-prd-c1
oc label managedcluster ammahapa-prd-c2 name=ammahapa-prd-c2
```

**Then**:
1. Create/rename overlays to match: `ammahapa-prd-c1-{udn,vms}`, `ammahapa-prd-c2-{udn,vms}`
2. Update ApplicationSet generators to use your cluster names
3. DRPolicy will automatically use the ManagedCluster names

The ApplicationSet `{{name}}` and `{{clusterName}}` variables will automatically expand to your actual cluster names, making the overlay paths match correctly.
