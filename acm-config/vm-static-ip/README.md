# ACM Configuration for VM Static IP Workload

This directory contains ACM (Advanced Cluster Management) configuration for deploying VMs with static IPs across DR clusters using GitOps.

## 📁 Files

| File | Description |
|------|-------------|
| `placement.yaml` | Selects which cluster runs the VMs (active cluster) |
| `applicationset-udn.yaml` | Deploys UDN infrastructure to BOTH clusters |
| `applicationset-vms.yaml` | Deploys VMs to Placement-selected cluster |
| `kustomization.yaml` | Bundles all resources together |

## 🚀 Deployment

### Bootstrap Method (Recommended)

Create a bootstrap Application that deploys everything from this Git directory:

```bash
oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vm-static-ip-bootstrap
  namespace: openshift-gitops
  labels:
    app: vm-static-ip-bootstrap
spec:
  project: default
  
  source:
    repoURL: https://github.com/pruthvitd/ocm-ramen-samples.git
    targetRevision: gitops-udn-primary-vm
    path: acm-config/vm-static-ip
  
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

### Manual Method (For Testing)

```bash
# Apply all resources
kustomize build acm-config/vm-static-ip | oc apply -f -

# Or
oc apply -k acm-config/vm-static-ip
```

## 📊 What Gets Created

```
Hub Cluster (openshift-gitops namespace):
├─ Placement: vm-static-ip-placement
│  └─ Selects: ammahapa-prd-c1 (initial)
│
├─ ApplicationSet: vm-static-ip-udn
│  ├─ Generates App → ammahapa-prd-c1 (UDN)
│  └─ Generates App → ammahapa-prd-c2 (UDN)
│
└─ ApplicationSet: vm-static-ip-vms
   └─ Generates App → ammahapa-prd-c1 (VMs)

Managed Clusters:
├─ ammahapa-prd-c1:
│  ├─ UDN (192.168.100.0/24)
│  └─ VMs (vm-server, vm-client)
│
└─ ammahapa-prd-c2:
   └─ UDN (192.168.200.0/24)
   └─ (no VMs - standby)
```

## 🔍 Verification

```bash
# Check bootstrap Application
oc get application vm-static-ip-bootstrap -n openshift-gitops

# Check Placement
oc get placement -n openshift-gitops vm-static-ip-placement

# Check ApplicationSets
oc get applicationsets -n openshift-gitops | grep vm-static-ip

# Check generated Applications
oc get applications -n openshift-gitops | grep vm-static-ip

# Check UDN on both clusters
oc --context ammahapa-prd-c1 get udn -n vm-static-ip
oc --context ammahapa-prd-c2 get udn -n vm-static-ip

# Check VMs on active cluster
oc --context ammahapa-prd-c1 get vms -n vm-static-ip
```

## 🔧 Customization

### Change Active Cluster

Edit `placement.yaml`:
```yaml
matchLabels:
  name: ammahapa-prd-c2  # Change to c2
```

Commit and push - VMs will automatically move to c2!

### Add More Clusters

Edit `applicationset-udn.yaml`:
```yaml
values:
  - ammahapa-prd-c1
  - ammahapa-prd-c2
  - ammahapa-prd-c3  # Add new cluster
```

Create new overlays:
```bash
mkdir -p workloads/kubevirt/vm-static-ip/overlays/{ammahapa-prd-c3-udn,ammahapa-prd-c3-vms}
```

### Change Git Repository or Branch

Edit all `applicationset-*.yaml` files:
```yaml
source:
  repoURL: https://github.com/your-org/your-repo.git
  targetRevision: your-branch
```

## 🎯 GitOps Benefits

✅ **Single Source of Truth**: All config in Git  
✅ **Version Control**: Track all changes  
✅ **Easy Rollback**: Revert Git commits  
✅ **Audit Trail**: Who changed what, when  
✅ **Replication**: Deploy to new environments easily  
✅ **Automation**: CI/CD can update configs  

## 📚 Related Documentation

- [Main Deployment Guide](../../workloads/kubevirt/vm-static-ip/DEPLOYMENT_GUIDE_UI.md)
- [Architecture Guide](../../workloads/kubevirt/vm-static-ip/ARCHITECTURE.md)
- [Cluster Customization](../../workloads/kubevirt/vm-static-ip/CUSTOMIZE_FOR_YOUR_CLUSTERS.md)
