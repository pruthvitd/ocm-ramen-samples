# Resource Segregation for Disaster Recovery

This directory contains Kubernetes manifests segregated by DR behavior to support ACM disaster recovery operations.

## ⚠️ Critical: ArgoCD Sync Annotations

DR prerequisite resources include the annotation `argocd.argoproj.io/sync-options: Prune=false,Delete=false` to prevent ACM/ArgoCD from deleting them during disaster recovery operations.

## Directory Structure

```
base/
├── dr-prerequisites/           # Deploy on BOTH clusters initially (protected)
│   ├── ns.yaml                 # Namespace
│   ├── sc.yaml                 # StorageClass
│   ├── custom-scc.yaml         # SecurityContextConstraints
│   ├── custom-sa.yaml          # ServiceAccount and RoleBindings
│   └── kustomization.yaml
├── application-resources/      # Move with application during DR
│   ├── pvc.yaml                # PersistentVolumeClaims
│   ├── deployment.yaml         # Deployment
│   ├── cm.yaml                 # ConfigMap
│   └── kustomization.yaml
└── kustomization.yaml          # Main kustomization referencing both
```

## Resource Segregation

### DR Prerequisites (Protected Resources)
These resources are **deployed on BOTH clusters initially** and **protected from deletion**:

- **Namespace**: `ns.yaml`
  - Application namespace
  - **Protected by**: `argocd.argoproj.io/sync-options: Prune=false,Delete=false`
  
- **StorageClass**: `sc.yaml`
  - Storage provisioning configuration
  - Cluster-wide resource tied to storage infrastructure
  - **Protected by**: `argocd.argoproj.io/sync-options: Prune=false,Delete=false`
  
- **SecurityContextConstraints (SCC)**: `custom-scc.yaml`
  - Security policies for pods
  - Cluster-wide resource
  - **Protected by**: `argocd.argoproj.io/sync-options: Prune=false,Delete=false`
  
- **ServiceAccount & RoleBindings**: `custom-sa.yaml`
  - Service account for the application
  - RoleBindings for SCC permissions
  - **Protected by**: `argocd.argoproj.io/sync-options: Prune=false,Delete=false`

### Application Resources (Mobile Resources)
These resources **move with the application** during disaster recovery operations:

- **PersistentVolumeClaims**: `pvc.yaml`
  - Application data volumes
  - Replicated via VolSync/storage replication
  
- **Deployment**: `deployment.yaml`
  - Application workload
  
- **ConfigMap**: `cm.yaml`
  - Application configuration

## Disaster Recovery Behavior

### Initial Deployment

#### Option 1: Using Separate ApplicationSets (Recommended)

1. **Deploy DR Prerequisites ApplicationSet** (deploys to ALL clusters):
   ```bash
   # Apply the prerequisites placement and applicationset
   kubectl apply -f workloads/deployment/base/dr-prerequisites-placement.yaml
   kubectl apply -f workloads/deployment/base/dr-prerequisites-appset.yaml
   ```
   
   This creates prerequisites on **all clusters** specified in the placement.

2. **Deploy Application ApplicationSet** (deploys to one cluster based on DR placement):
   ```yaml
   # Your main application ApplicationSet
   spec:
     source:
       path: workloads/deployment/base/application-resources
   ```

#### Option 2: Manual Deployment (For Testing)

1. **Manually deploy prerequisites to BOTH clusters**:
   ```bash
   # On Cluster A
   kubectl apply -k workloads/deployment/base/dr-prerequisites/ --context=cluster-a
   
   # On Cluster B
   kubectl apply -k workloads/deployment/base/dr-prerequisites/ --context=cluster-b
   ```

2. **Deploy application via ApplicationSet** (deploys to one cluster):
   ```yaml
   spec:
     source:
       path: workloads/deployment/base/application-resources
   ```

### During DR Operations (Failover/Relocate)

When the ApplicationSet moves from Cluster A → Cluster B:

**DR Prerequisites (Protected)**:
- ✅ Namespace remains on Cluster A (not deleted)
- ✅ StorageClass remains on Cluster A (not deleted)
- ✅ SCC remains on Cluster A (not deleted)
- ✅ ServiceAccount & RoleBindings remain on Cluster A (not deleted)
- ✅ All prerequisites already exist on Cluster B (pre-deployed)

**Application Resources (Mobile)**:
- ❌ PVCs deleted from Cluster A
- ❌ Deployment deleted from Cluster A
- ❌ ConfigMap deleted from Cluster A
- ✅ PVCs created on Cluster B (data restored via VolSync)
- ✅ Deployment created on Cluster B
- ✅ ConfigMap created on Cluster B

### How Protection Works

The annotation `argocd.argoproj.io/sync-options: Prune=false,Delete=false` tells ArgoCD:
- **Prune=false**: Don't delete this resource when it's no longer in the ApplicationSet
- **Delete=false**: Don't delete this resource when the Application is deleted

This ensures infrastructure dependencies remain available on both clusters while the application moves between them.

## Deployment Instructions

### Step 1: Deploy Prerequisites to ALL Clusters

**Update the Placement** with your cluster names:
```bash
# Edit dr-prerequisites-placement.yaml
# Replace cluster1, cluster2 with your actual cluster names
```

**Deploy Prerequisites ApplicationSet**:
```bash
kubectl apply -f workloads/deployment/base/dr-prerequisites-placement.yaml
kubectl apply -f workloads/deployment/base/dr-prerequisites-appset.yaml
```

This will deploy prerequisites (Namespace, StorageClass, SCC, ServiceAccount, RoleBindings) to **all clusters** in the placement.

### Step 2: Deploy Application (via ACM ApplicationSet)

Create an ApplicationSet for the application that references **application-resources**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: sftpgo-app
  namespace: openshift-gitops
spec:
  generators:
    - clusterDecisionResource:
        configMapRef: acm-placement
        labelSelector:
          matchLabels:
            cluster.open-cluster-management.io/placement: sftpgo-app-placement
        requeueAfterSeconds: 180
  template:
    metadata:
      name: 'sftpgo-app-{{name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/your-repo.git
        targetRevision: main
        path: workloads/deployment/base/application-resources
      destination:
        server: '{{server}}'
        namespace: rdr-test
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=false  # Namespace already exists from prerequisites
```

### Step 3: Enable DR Protection

Create a DRPlacementControl to enable disaster recovery for the application:

```yaml
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPlacementControl
metadata:
  name: sftpgo-app-drpc
  namespace: openshift-gitops
spec:
  placementRef:
    name: sftpgo-app-placement
    namespace: openshift-gitops
  drPolicyRef:
    name: your-dr-policy
  pvcSelector:
    matchLabels:
      appname: sftpgo
```

## Verification

### Check Prerequisites on Both Clusters
```bash
# Verify on Cluster A
kubectl get namespace rdr-test --context=cluster-a
kubectl get storageclass ocs-storagecluster-cephfs-selinux-relabel --context=cluster-a
kubectl get scc custom --context=cluster-a
kubectl get sa db-app-sa -n rdr-test --context=cluster-a

# Verify on Cluster B
kubectl get namespace rdr-test --context=cluster-b
kubectl get storageclass ocs-storagecluster-cephfs-selinux-relabel --context=cluster-b
kubectl get scc custom --context=cluster-b
kubectl get sa db-app-sa -n rdr-test --context=cluster-b
```

### Check Application Resources
```bash
# Should exist on only one cluster at a time
kubectl get deployment,pvc,cm -n rdr-test --context=<active-cluster>
```

## Notes

- Prerequisites must be deployed to both clusters before enabling DR
- Prerequisites are protected from deletion and remain on both clusters
- Application resources move between clusters during DR operations
- Data is replicated via VolSync or storage-level replication
- The namespace annotation for VolSync can be uncommented when needed