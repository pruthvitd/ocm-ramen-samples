# Resource Segregation for Disaster Recovery

This directory contains Kubernetes manifests segregated by resource scope to support ACM disaster recovery operations.

## Directory Structure

```
base/
├── cluster-scoped/          # Cluster-level resources (retained during DR)
│   ├── custom-scc.yaml      # SecurityContextConstraints
│   ├── sc.yaml              # StorageClass
│   └── kustomization.yaml
├── namespace-scoped/        # Namespace-level resources (moved during DR)
│   ├── ns.yaml              # Namespace
│   ├── custom-sa.yaml       # ServiceAccount and RoleBindings
│   ├── pvc.yaml             # PersistentVolumeClaims
│   ├── deployment.yaml      # Deployment
│   ├── cm.yaml              # ConfigMap
│   └── kustomization.yaml
└── kustomization.yaml       # Main kustomization referencing both scopes
```

## Resource Segregation

### Cluster-Scoped Resources
These resources are **retained by ACM** on the cluster during disaster recovery operations:
- **SecurityContextConstraints (SCC)**: `custom-scc.yaml`
  - Defines security policies for pods
  - Cluster-wide resource that should exist on all clusters
- **StorageClass**: `sc.yaml`
  - Defines storage provisioning configuration
  - Cluster-wide resource tied to storage infrastructure

### Namespace-Scoped Resources
These resources **move with the application** during disaster recovery operations:
- **Namespace**: `ns.yaml`
  - Application namespace with volsync annotations
- **ServiceAccount & RoleBindings**: `custom-sa.yaml`
  - Service account for the application
  - RoleBindings for SCC permissions
- **PersistentVolumeClaims**: `pvc.yaml`
  - Application data volumes
- **Deployment**: `deployment.yaml`
  - Application workload
- **ConfigMap**: `cm.yaml`
  - Application configuration

## Disaster Recovery Behavior

When an ApplicationSet is moved from one cluster to another during a DR operation:

1. **Cluster-scoped resources** remain on both clusters
   - They must be pre-deployed on all clusters in the DR topology
   - ACM does not delete or move these resources
   - Ensures infrastructure dependencies are available

2. **Namespace-scoped resources** move with the application
   - Deleted from the source cluster
   - Created on the target cluster
   - Application state and data follow the workload

## Deployment

### Initial Setup (All Clusters)
Deploy cluster-scoped resources to all clusters in your DR topology:
```bash
kubectl apply -k workloads/deployment/base/cluster-scoped/
```

### Application Deployment (via ACM/ArgoCD)
Deploy the complete application including namespace-scoped resources:
```bash
kubectl apply -k workloads/deployment/base/
```

Or reference in your ApplicationSet/Subscription:
```yaml
spec:
  source:
    path: workloads/deployment/base
```

## Notes

- The main `kustomization.yaml` references both subdirectories
- Cluster-scoped resources should be deployed before the application
- Ensure StorageClass and SCC exist on all clusters before DR operations
- The namespace annotation `volsync.backube/privileged-movers: "true"` enables VolSync for data replication