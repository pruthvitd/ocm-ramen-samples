# Deploying VM Static IP Application via ACM UI (Pull Model)

This guide walks through deploying the UDN-based VM application using the ACM/OpenShift GitOps UI with the ApplicationSet pull model.

## Prerequisites

### Hub Cluster (Where ACM is installed)
- ✅ **ACM (Advanced Cluster Management)** installed
- ✅ **OpenShift GitOps Operator** installed (Argo CD)
- ✅ Network access to Git repository
- ✅ Network access to managed cluster API servers

### Managed Clusters (dr1, dr2)
- ✅ **Imported into ACM** as ManagedClusters
- ✅ **Labeled** with `name=dr1` and `name=dr2`
- ✅ **ODF/Ceph storage** configured
- ❌ **NO OpenShift GitOps** needed on managed clusters
- ❌ **NO Argo CD** needed on managed clusters

**Important**: Only the **hub cluster** needs the OpenShift GitOps operator. The managed clusters (dr1, dr2) do NOT need Argo CD installed. The hub's Argo CD will deploy to managed clusters via the Kubernetes API using credentials managed by ACM.

> See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed explanation of how the pull model works.

## Overview: Pull Model Architecture

```
┌─────────────────────────────────────────────────────┐
│  Hub Cluster (ACM + OpenShift GitOps)               │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │ ApplicationSet (UDN)                       │    │
│  │ - Watches: ManagedClusters (dr1, dr2)     │    │
│  │ - Generates: 2 Applications                │    │
│  └────────────────────────────────────────────┘    │
│           │                       │                 │
│           ▼                       ▼                 │
│  ┌─────────────┐         ┌─────────────┐          │
│  │ App: UDN-dr1│         │ App: UDN-dr2│          │
│  └─────────────┘         └─────────────┘          │
│           │                       │                 │
│           │  Pulls from Git       │                 │
│           ▼                       ▼                 │
└───────────┼───────────────────────┼─────────────────┘
            │                       │
    ┌───────▼────────┐     ┌───────▼────────┐
    │ DR1 Cluster    │     │ DR2 Cluster    │
    │                │     │                │
    │ ┌────────────┐ │     │ ┌────────────┐ │
    │ │ UDN        │ │     │ │ UDN        │ │
    │ │ 192.168.   │ │     │ │ 192.168.   │ │
    │ │   100.0/24 │ │     │ │   200.0/24 │ │
    │ └────────────┘ │     │ └────────────┘ │
    └────────────────┘     └────────────────┘

  ┌────────────────────────────────────────────┐
  │ ApplicationSet (VMs)                       │
  │ - Watches: PlacementDecision               │
  │ - Generates: 1 Application (active site)   │
  └────────────────────────────────────────────┘
                    │
                    ▼
         ┌─────────────────┐
         │ App: VMs-dr1    │
         └─────────────────┘
                    │
            Pulls from Git
                    ▼
         ┌────────────────┐
         │ DR1 Cluster    │
         │ ┌────────────┐ │
         │ │ vm-server  │ │
         │ │ vm-client  │ │
         │ └────────────┘ │
         └────────────────┘
```

**Pull Model**: 
- Hub cluster generates Applications from ApplicationSets
- Each Application pulls manifests from Git repository
- Argo CD syncs resources to target clusters
- No push from hub to managed clusters

---

## Step 1: Label ManagedClusters

Before creating ApplicationSets, ensure your clusters are properly labeled.

### Via CLI:
```bash
oc label managedcluster dr1 name=dr1 --overwrite
oc label managedcluster dr2 name=dr2 --overwrite
```

### Via ACM UI:
1. Navigate to **Infrastructure → Clusters**
2. Click on **dr1** cluster name
3. Click **Labels** tab
4. Add label: `name=dr1`
5. Repeat for **dr2** cluster

**Verification**:
```bash
oc get managedclusters -L name
```

Expected output:
```
NAME   HUB ACCEPTED   MANAGED CLUSTER URLS   NAME
dr1    true           https://...            dr1
dr2    true           https://...            dr2
```

---

## Step 2: Create UDN ApplicationSet (Infrastructure)

This deploys the UDN network to **BOTH** clusters.

### Via OpenShift Console UI:

1. **Navigate to ApplicationSets**
   - Go to: **Operators → Installed Operators**
   - Select: **Red Hat OpenShift GitOps**
   - Click: **ApplicationSet** tab
   - Click: **Create ApplicationSet**

2. **Switch to YAML View**
   - Click the **YAML view** radio button at the top

3. **Paste the ApplicationSet YAML**

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
                - dr1
                - dr2

  template:
    metadata:
      name: 'vm-static-ip-udn-{{name}}'
      labels:
        app: vm-static-ip-udn
        cluster: '{{name}}'
        component: network-infrastructure

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
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
```

4. **Important Fields to Customize**:
   - `repoURL`: Your Git repository URL
   - `targetRevision`: Your branch name (e.g., `main`, `gitops-udn-primary-vm`)
   - `path`: Path to overlays in your repo

5. **Click Create**

### Verification:

**Check ApplicationSet Created**:
```bash
oc get applicationset -n openshift-gitops vm-static-ip-udn
```

**Check Generated Applications** (should see 2):
```bash
oc get applications -n openshift-gitops -l app=vm-static-ip-udn
```

Expected output:
```
NAME                    SYNC STATUS   HEALTH STATUS
vm-static-ip-udn-dr1    Synced        Healthy
vm-static-ip-udn-dr2    Synced        Healthy
```

**Verify UDN Deployed to Both Clusters**:
```bash
# On dr1
oc --context dr1 get userdefinednetwork -n vm-static-ip

# On dr2
oc --context dr2 get userdefinednetwork -n vm-static-ip
```

**Verify Different Subnets**:
```bash
# DR1 should have 192.168.100.0/24
oc --context dr1 get userdefinednetwork -n vm-static-ip primary-udn -o jsonpath='{.spec.layer2.subnets}'

# DR2 should have 192.168.200.0/24
oc --context dr2 get userdefinednetwork -n vm-static-ip primary-udn -o jsonpath='{.spec.layer2.subnets}'
```

---

## Step 3: Create Placement Resource

The Placement determines which cluster runs the VMs. The VM ApplicationSet watches this Placement.

### Via ACM UI:

1. **Navigate to Applications**
   - Go to: **Applications → Overview**
   - Click: **Create application → Subscription**

2. **Create Placement** (part of subscription wizard)
   - Or create directly via YAML

### Via CLI (Recommended):

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

### Verification:

**Check Placement Created**:
```bash
oc get placement -n vm-static-ip vm-static-ip-placement
```

**Check PlacementDecision** (shows which cluster was selected):
```bash
oc get placementdecision -n vm-static-ip -o yaml
```

Expected: Should show `dr1` as the selected cluster.

---

## Step 4: Create VM ApplicationSet (Application Workload)

This deploys VMs **ONLY** to the cluster selected by Placement.

### Via OpenShift Console UI:

1. **Navigate to ApplicationSets**
   - **Operators → Installed Operators**
   - **Red Hat OpenShift GitOps**
   - **ApplicationSet** tab
   - **Create ApplicationSet**

2. **Switch to YAML View**

3. **Paste the ApplicationSet YAML**

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
      labels:
        app: vm-static-ip-vms
        cluster: '{{clusterName}}'
        component: application

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
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
```

4. **Important**: The `clusterDecisionResource` generator watches the Placement you created

5. **Click Create**

### Verification:

**Check ApplicationSet Created**:
```bash
oc get applicationset -n openshift-gitops vm-static-ip-vms
```

**Check Generated Application** (should see 1, on dr1):
```bash
oc get applications -n openshift-gitops -l app=vm-static-ip-vms
```

Expected output:
```
NAME                    SYNC STATUS   HEALTH STATUS
vm-static-ip-vms-dr1    Synced        Healthy
```

**Verify VMs Running on DR1**:
```bash
oc --context dr1 get vms -n vm-static-ip
```

Expected output:
```
NAME         AGE   STATUS    READY
vm-server    2m    Running   True
vm-client    2m    Running   True
```

**Verify VM IPs**:
```bash
# Should see 192.168.100.10 and .11
oc --context dr1 get vm -n vm-static-ip vm-server -o jsonpath='{.spec.template.metadata.annotations.network\.kubevirt\.io/addresses}'
```

**Verify NO VMs on DR2** (yet):
```bash
oc --context dr2 get vms -n vm-static-ip
```

Expected: Empty (VMs only on active cluster)

---

## Step 5: Monitor in Argo CD UI

### Access Argo CD Console:

1. **Get Argo CD Route**:
   ```bash
   oc get route -n openshift-gitops openshift-gitops-server -o jsonpath='{.spec.host}'
   ```

2. **Get Admin Password**:
   ```bash
   oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
   ```

3. **Login to Argo CD UI**:
   - URL: `https://<route-from-step-1>`
   - Username: `admin`
   - Password: `<password-from-step-2>`

### View Applications:

1. **Filter by Label**:
   - Click **Filters**
   - Add filter: `app=vm-static-ip-udn`
   - Should see 2 apps (dr1 and dr2 UDN)

2. **Click on an Application**:
   - View the resource tree
   - Check sync status
   - See which overlay path is used

3. **View VM Application**:
   - Filter: `app=vm-static-ip-vms`
   - Should see 1 app (on dr1)
   - Resource tree shows VMs, DataVolumes, etc.

### Sync Operations:

- **Auto-sync** is enabled (changes in Git auto-deploy)
- **Self-heal** is enabled (manual changes are reverted)
- Click **Sync** to manually trigger sync
- Click **Refresh** to check Git for changes

---

## Step 6: Setup DR Protection (Optional - via ACM UI)

Once VMs are deployed, protect them with Ramen DR.

### Create DRPolicy:

1. **Navigate to DR**:
   - Go to: **Infrastructure → Disaster Recovery**
   - Click: **Create DRPolicy**

2. **Configure DRPolicy**:
   - **Name**: `dr1-dr2-policy`
   - **Peer clusters**: Select `dr1` and `dr2`
   - **Replication interval**: `5m`
   - Click **Create**

### Create DRPlacementControl:

1. **Navigate to DR**:
   - **Infrastructure → Disaster Recovery**
   - **DRPlacementControl** tab
   - Click: **Create DRPlacementControl**

2. **Configure DRPC**:
   - **Name**: `vm-static-ip-drpc`
   - **Namespace**: `vm-static-ip`
   - **DRPolicy**: Select `dr1-dr2-policy`
   - **Placement**: Select `vm-static-ip-placement`
   - **PVC label selector**: 
     - Key: `appname`
     - Value: `vm-cloudinit-static-ip`
   - **Preferred cluster**: `dr1`
   - Click **Create**

### Verification:

```bash
# Check DRPC status
oc get drpc -n vm-static-ip vm-static-ip-drpc

# Check if VolumeReplicationGroups created
oc get volumereplicationgroup -n vm-static-ip
```

---

## Step 7: Test DR Failover

Once DR protection is setup, test failover from dr1 to dr2.

### Via ACM UI:

1. **Navigate to DRPC**:
   - **Infrastructure → Disaster Recovery**
   - **DRPlacementControl** tab
   - Click on: `vm-static-ip-drpc`

2. **Initiate Failover**:
   - Click: **Actions → Failover**
   - Select target cluster: `dr2`
   - Click **Initiate**

### What Happens (Automated):

```
1. Ramen updates Placement: dr1 → dr2
   ↓
2. VM ApplicationSet detects Placement change
   ↓
3. ApplicationSet generates new Application:
   - Name: vm-static-ip-vms-dr2
   - Path: overlays/dr2-vms
   ↓
4. Argo CD syncs to dr2
   ↓
5. VMs start on dr2 with 192.168.200.x IPs
```

### Verification After Failover:

**Check Placement Decision**:
```bash
oc get placementdecision -n vm-static-ip -o yaml | grep clusterName
```
Should show: `dr2`

**Check Applications**:
```bash
oc get applications -n openshift-gitops -l app=vm-static-ip-vms
```
Should see: `vm-static-ip-vms-dr2`

**Check VMs on DR2**:
```bash
oc --context dr2 get vms -n vm-static-ip
```
Should see: `vm-server` and `vm-client` running

**Verify New IPs**:
```bash
oc --context dr2 get vm -n vm-static-ip vm-server -o jsonpath='{.spec.template.metadata.annotations.network\.kubevirt\.io/addresses}'
```
Should show: `192.168.200.10` (dr2 subnet)

---

## Troubleshooting

### ApplicationSet Not Generating Applications

**Check ApplicationSet status**:
```bash
oc describe applicationset -n openshift-gitops vm-static-ip-udn
```

**Common issues**:
- Cluster labels missing: `oc get managedclusters -L name`
- Generator selector mismatch: Check `matchLabels` in ApplicationSet
- Git repo not accessible: Check `repoURL` and `targetRevision`

### Applications Not Syncing

**Check Application status**:
```bash
oc describe application -n openshift-gitops vm-static-ip-udn-dr1
```

**Common issues**:
- Path not found in Git: Verify `path` in ApplicationSet
- Kustomize build error: Test locally with `kustomize build`
- Cluster not reachable: Check ManagedCluster status

### VM ApplicationSet Not Following Placement

**Check ClusterDecisionResource**:
```bash
oc get placementdecision -n vm-static-ip -o yaml
```

**Common issues**:
- Placement namespace mismatch: Must match ApplicationSet namespace reference
- Placement label mismatch: Check `cluster.open-cluster-management.io/placement`
- ConfigMap not found: Ensure ACM is properly configured

### VMs Not Starting

**Check VM events**:
```bash
oc --context dr1 describe vm -n vm-static-ip vm-server
```

**Common issues**:
- UDN not found: Ensure UDN ApplicationSet deployed successfully
- Storage class not found: Check `storageClassName` in base/vm.yaml
- Namespace annotation missing: Check namespace has UDN annotation

---

## Summary: Deployment Checklist

- [ ] Step 1: Label ManagedClusters (dr1, dr2)
- [ ] Step 2: Create UDN ApplicationSet (deploys to both clusters)
- [ ] Step 3: Verify UDN on both clusters with correct subnets
- [ ] Step 4: Create Placement resource (selects dr1)
- [ ] Step 5: Create VM ApplicationSet (follows Placement)
- [ ] Step 6: Verify VMs running on dr1 with correct IPs
- [ ] Step 7: (Optional) Setup DR protection with DRPolicy and DRPC
- [ ] Step 8: (Optional) Test failover to dr2

## Key Advantages of Pull Model

✅ **Git as Single Source of Truth**: All config in Git, no manual changes  
✅ **Automatic Reconciliation**: Drift is auto-corrected via self-heal  
✅ **Audit Trail**: All changes tracked in Git history  
✅ **Multi-Cluster Consistency**: Same GitOps workflow for all clusters  
✅ **DR-Aware**: ApplicationSet follows Placement decisions automatically  

## Next Steps

- Monitor applications in Argo CD UI
- Test DR failover scenarios
- Add more clusters by creating new overlays
- Customize VM configurations per site
- Integrate with CI/CD pipelines for automated updates
