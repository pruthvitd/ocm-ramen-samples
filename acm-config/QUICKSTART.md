# Quick Start: Two-Layer Deployment

## ⚡ 2-Minute Deployment

### Prerequisites Check

```bash
# Verify managed clusters imported
oc get managedclusters ammahapa-prd-c1 ammahapa-prd-c2

# Verify clusterset
oc get managedclusterset clusterset-submariner-844b61f9678d4a62b0

# Verify OpenShift GitOps on hub
oc get pods -n openshift-gitops
```

---

## 🚀 Deploy (2 Commands!)

### Step 1: Deploy Infrastructure (Layer 1)

```bash
oc apply -f acm-config/vm-network-infrastructure/bootstrap-infrastructure.yaml
```

**Wait 1 minute**, then verify:

```bash
oc get applications -n openshift-gitops | grep vm-network
```

Expected:
```
vm-network-infrastructure         Synced   Healthy
vm-network-ammahapa-prd-c1        Synced   Healthy
vm-network-ammahapa-prd-c2        Synced   Healthy
```

---

### Step 2: Deploy Workload (Layer 2)

```bash
oc apply -f acm-config/vm-workload-dr/bootstrap-workload.yaml
```

**Wait 2 minutes**, then verify:

```bash
oc get applications -n openshift-gitops | grep vm-static-ip
```

Expected:
```
vm-static-ip-workload             Synced   Healthy
vm-static-ip-ammahapa-prd-c1      Synced   Healthy
```

---

## ✅ Verification

### Check UDN on Both Clusters

```bash
# Cluster 1
oc --context ammahapa-prd-c1 get udn,namespace -n vm-static-ip

# Cluster 2  
oc --context ammahapa-prd-c2 get udn,namespace -n vm-static-ip
```

### Check VMs on Active Cluster

```bash
# Should be on ammahapa-prd-c1 (Placement default)
oc --context ammahapa-prd-c1 get vm,vmi -n vm-static-ip
```

### Check VM IPs

```bash
# Should have 192.168.100.x IPs
oc --context ammahapa-prd-c1 get vmi -n vm-static-ip -o yaml | grep "ipAddress:"
```

Expected:
```
- ipAddress: 192.168.100.10  # vm-server
- ipAddress: 192.168.100.11  # vm-client
```

---

## 🔄 Test DR Failover

### Create DRPlacementControl

```bash
oc apply -f - <<EOF
apiVersion: ramendr.openshift.io/v1alpha1
kind: DRPlacementControl
metadata:
  name: vm-static-ip-drpc
  namespace: openshift-gitops
spec:
  placementRef:
    name: vm-static-ip-placement
  drPolicyRef:
    name: odr-policy-5m  # Use your DR policy name
  preferredCluster: ammahapa-prd-c1
  pvcSelector:
    matchLabels:
      appname: vm-cloudinit-static-ip
EOF
```

### Trigger Failover

```bash
# Failover to cluster 2
oc patch drpc vm-static-ip-drpc -n openshift-gitops \
  --type merge \
  -p '{"spec":{"action":"Failover","failoverCluster":"ammahapa-prd-c2"}}'

# Watch Placement change
watch 'oc get placement vm-static-ip-placement -n openshift-gitops -o yaml | grep -A5 "name: ammahapa"'

# Watch Application move
watch 'oc get applications -n openshift-gitops | grep vm-static-ip'
```

### Verify After Failover

```bash
# VMs should now be on cluster 2
oc --context ammahapa-prd-c2 get vm,vmi -n vm-static-ip

# IPs should be translated to 192.168.200.x
oc --context ammahapa-prd-c2 get vmi -n vm-static-ip -o yaml | grep "ipAddress:"
```

Expected:
```
- ipAddress: 192.168.200.10  # vm-server (translated!)
- ipAddress: 192.168.200.11  # vm-client (translated!)
```

---

## 🧹 Cleanup

### Remove Workload Only (Keep Infrastructure)

```bash
oc delete application vm-static-ip-workload -n openshift-gitops
```

**UDN remains on both clusters** - ready for redeployment!

### Remove Everything

```bash
# Remove workload
oc delete application vm-static-ip-workload -n openshift-gitops

# Remove infrastructure
oc delete application vm-network-infrastructure -n openshift-gitops
```

---

## 🎯 Summary

**Deploy**: 2 commands  
**Time**: ~3 minutes total  
**Result**: DR-protected VMs with automatic IP translation  
**Cleanup**: No finalizer issues!  

**Questions?** See [README.md](README.md) for full architecture details.
