# Sync Waves: Ordered Deployment

This configuration uses **Argo CD Sync Waves** to deploy resources in the correct order.

## 🌊 Deployment Sequence

```
Wave 0: Placement
  └─> Selects which cluster runs VMs
      ⏱️  Wait for sync...
      ✅ Healthy

Wave 1: UDN ApplicationSet
  └─> Deploys network infrastructure to BOTH clusters
      ⏱️  Wait for sync...
      ⏱️  Wait for Applications to be created...
      ⏱️  Wait for UDN resources to be healthy...
      ✅ UDN on ammahapa-prd-c1: Healthy
      ✅ UDN on ammahapa-prd-c2: Healthy

Wave 2: VMs ApplicationSet
  └─> Deploys VMs to Placement-selected cluster
      ⏱️  Wait for sync...
      ⏱️  Wait for Applications to be created...
      ⏱️  Wait for VM resources to be healthy...
      ✅ VMs on ammahapa-prd-c1: Running
```

---

## 📋 Sync Wave Annotations

### Placement (Wave 0)
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy first
```

### UDN ApplicationSet (Wave 1)
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy after Placement
```

### VMs ApplicationSet (Wave 2)
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy after UDN
```

---

## ⏱️ How It Works

### Argo CD Sync Behavior

1. **Sort by Wave**: Resources are sorted by sync-wave annotation (lowest first)
2. **Sync**: Deploy all resources in current wave
3. **Wait**: Wait for all resources in current wave to become **Healthy**
4. **Next Wave**: Move to next wave number
5. **Repeat**: Continue until all waves are complete

### What "Healthy" Means

| Resource Type | Healthy When |
|---------------|--------------|
| **Placement** | PlacementDecision created with cluster selected |
| **ApplicationSet** | All generated Applications created successfully |
| **Application** | All resources synced and healthy on target cluster |
| **UDN** | Resource created and status is ready |
| **VM** | VirtualMachine running and ready |

---

## 🎯 Why This Ordering Matters

### Problem Without Sync Waves

```
❌ All resources deploy at once:
   ├─ Placement creates
   ├─ UDN ApplicationSet creates
   └─ VMs ApplicationSet creates
       └─> VMs try to use UDN before it exists! 💥
           Error: Network not found
```

### Solution With Sync Waves

```
✅ Sequential deployment:
   Wave 0: Placement ✅
           ↓
   Wave 1: UDN ApplicationSet ✅
           UDN deployed to clusters ✅
           ↓
   Wave 2: VMs ApplicationSet ✅
           VMs use existing UDN ✅
```

---

## 🔍 Monitoring Sync Progress

### Via Argo CD UI

1. Open Argo CD UI
2. Click on `vm-static-ip-bootstrap` Application
3. Watch resources deploy in waves:
   - **Wave 0** resources turn green first
   - **Wave 1** resources wait, then deploy
   - **Wave 2** resources wait, then deploy

### Via CLI

```bash
# Watch bootstrap Application sync
oc get application vm-static-ip-bootstrap -n openshift-gitops -w

# Check what's in each wave
oc get placement,applicationset -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave
```

Expected output:
```
NAME                      WAVE
vm-static-ip-placement    0
vm-static-ip-udn          1
vm-static-ip-vms          2
```

### Check Sync Status

```bash
# See sync phase
oc get application vm-static-ip-bootstrap -n openshift-gitops \
  -o jsonpath='{.status.operationState.phase}'

# Syncing = in progress
# Succeeded = complete
```

---

## ⏱️ Typical Timeline

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| **Wave 0 Sync** | 5-10 sec | Placement created |
| **Wave 0 Wait** | 5-10 sec | PlacementDecision generated |
| **Wave 1 Sync** | 5-10 sec | UDN ApplicationSet created |
| **Wave 1 Wait** | 30-60 sec | Applications generated, UDN deployed |
| **Wave 2 Sync** | 5-10 sec | VMs ApplicationSet created |
| **Wave 2 Wait** | 60-120 sec | Applications generated, VMs deployed |
| **Total** | ~2-3 minutes | Complete deployment |

---

## 🚀 Deploying with Sync Waves

### Step 1: Commit Updated Files

```bash
git add acm-config/vm-static-ip/
git commit -m "Add sync waves for sequential deployment

- Wave 0: Placement (cluster selection)
- Wave 1: UDN ApplicationSet (infrastructure)
- Wave 2: VMs ApplicationSet (workload)

This ensures UDN exists before VMs try to use it."
git push
```

### Step 2: Apply Bootstrap

```bash
# Apply bootstrap Application
oc apply -f acm-config/vm-static-ip/bootstrap-application.yaml

# Watch it deploy in waves
oc get application vm-static-ip-bootstrap -n openshift-gitops -w
```

### Step 3: Observe Sequential Deployment

```bash
# Watch resources appear in order
watch 'oc get placement,applicationset,applications -n openshift-gitops | grep vm-static-ip'

# You'll see:
# 1. Placement appears first
# 2. UDN ApplicationSet appears next
# 3. VMs ApplicationSet appears last
```

---

## 🔧 Adjusting Wave Numbers

You can change the wave numbers if needed:

### Faster (Less Safe)
```yaml
sync-wave: "0"  # Placement
sync-wave: "0"  # UDN ApplicationSet (same wave as Placement)
sync-wave: "1"  # VMs ApplicationSet
```

Faster, but UDN might not be ready when VMs deploy.

### Slower (More Safe)
```yaml
sync-wave: "0"  # Placement
sync-wave: "5"  # UDN ApplicationSet (bigger gap)
sync-wave: "10" # VMs ApplicationSet (bigger gap)
```

Adds more wait time between waves (not necessary, but very safe).

### Recommended (Current)
```yaml
sync-wave: "0"  # Placement
sync-wave: "1"  # UDN ApplicationSet
sync-wave: "2"  # VMs ApplicationSet
```

Good balance of speed and safety. ✅

---

## 📊 Sync Waves vs. Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **Sync Waves** | ✅ Native Argo CD<br>✅ Automatic<br>✅ Declarative | ⚠️ Requires annotations |
| **Manual Sequencing** | ✅ Full control | ❌ Manual work<br>❌ Not GitOps |
| **Health Checks Only** | ✅ Eventually consistent | ❌ May retry/fail initially |
| **Separate Apps** | ✅ Complete isolation | ❌ More complex<br>❌ Hard to manage |

**Sync Waves are the recommended approach!** ✅

---

## 🎯 Summary

**What we added:**
- `sync-wave: "0"` to Placement
- `sync-wave: "1"` to UDN ApplicationSet
- `sync-wave: "2"` to VMs ApplicationSet

**What this does:**
- Ensures resources deploy in correct order
- UDN exists before VMs try to use it
- No race conditions or deployment errors

**How to use:**
1. Commit updated files with sync wave annotations
2. Push to Git
3. Apply bootstrap Application
4. Watch sequential deployment happen automatically!

Argo CD handles the rest! 🎉
