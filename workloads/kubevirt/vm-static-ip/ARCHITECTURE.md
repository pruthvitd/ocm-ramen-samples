# Architecture: Pull Model with ACM and OpenShift GitOps

## Common Misconception: "Pull Model" Naming

❌ **WRONG**: "Pull model means each managed cluster pulls from Git"  
✅ **CORRECT**: "Pull model means the Hub's Argo CD pulls from Git and pushes to managed clusters via Kubernetes API"

## Where Components Run

```
┌─────────────────────────────────────────────────────┐
│  HUB CLUSTER                                        │
│                                                      │
│  ✅ ACM (Advanced Cluster Management)               │
│  ✅ OpenShift GitOps Operator (Argo CD)             │
│  ✅ ApplicationSet Controller                       │
│  ✅ Argo CD Server                                  │
│                                                      │
│  These components:                                  │
│  - Generate Applications from ApplicationSets      │
│  - Pull manifests from Git repository              │
│  - Apply manifests to managed clusters via K8s API │
│  - Use ACM-managed credentials for access          │
│                                                      │
└─────────────────────────────────────────────────────┘
            │                       │
            │   K8s API calls       │
            ▼                       ▼
┌─────────────────┐       ┌─────────────────┐
│  DR1 CLUSTER    │       │  DR2 CLUSTER    │
│                 │       │                 │
│  ❌ NO GitOps   │       │  ❌ NO GitOps   │
│  ❌ NO Argo CD  │       │  ❌ NO Argo CD  │
│                 │       │                 │
│  ✅ Just K8s API│       │  ✅ Just K8s API│
│  ✅ ACM Agent   │       │  ✅ ACM Agent   │
│                 │       │                 │
└─────────────────┘       └─────────────────┘
```

## Prerequisites per Cluster

### Hub Cluster Requirements
- ✅ **ACM (Advanced Cluster Management)** installed
- ✅ **OpenShift GitOps Operator** installed
- ✅ Network access to Git repository
- ✅ Network access to managed cluster API servers

### Managed Cluster Requirements (dr1, dr2)
- ✅ **Registered as ManagedClusters** in ACM
- ✅ **ACM agent** running (klusterlet)
- ❌ **NO OpenShift GitOps** needed
- ❌ **NO Argo CD** needed
- ❌ **NO Git access** needed

## How It Works: Application Deployment Flow

### 1. ApplicationSet Generation Phase

```
Hub Cluster:
┌─────────────────────────────────────────┐
│ ApplicationSet Controller               │
│                                         │
│ Watches: ManagedClusters (dr1, dr2)    │
│                                         │
│ Generates:                              │
│  ├─ Application: vm-static-ip-udn-dr1  │
│  └─ Application: vm-static-ip-udn-dr2  │
│                                         │
└─────────────────────────────────────────┘
```

### 2. Manifest Pull Phase

```
Hub Cluster (Argo CD):
┌─────────────────────────────────────────┐
│ Application: vm-static-ip-udn-dr1       │
│                                         │
│ 1. Reads: source.repoURL                │
│    → https://github.com/.../            │
│                                         │
│ 2. Reads: source.path                   │
│    → overlays/dr1-udn                   │
│                                         │
│ 3. Executes: kustomize build            │
│    → Generates manifests                │
│                                         │
└─────────────────────────────────────────┘
```

### 3. Manifest Apply Phase

```
Hub Cluster (Argo CD) → DR1 Cluster:
┌─────────────────────────────────────────┐
│ Application syncs to DR1                │
│                                         │
│ 1. Gets credentials for DR1 from ACM   │
│                                         │
│ 2. Connects to DR1 K8s API server      │
│    (using ManagedCluster kubeconfig)    │
│                                         │
│ 3. Applies manifests via kubectl apply │
│    ├─ Namespace: vm-static-ip          │
│    └─ UserDefinedNetwork: primary-udn  │
│                                         │
└─────────────────────────────────────────┘
                  │
                  │ K8s API (HTTPS)
                  ▼
       ┌─────────────────────┐
       │  DR1 Cluster        │
       │                     │
       │  Resources created: │
       │  ├─ Namespace       │
       │  └─ UDN (subnet:    │
       │      192.168.100/24)│
       └─────────────────────┘
```

## Credential Management

### How Hub Accesses Managed Clusters

When you import a cluster into ACM:

1. **ACM stores cluster credentials**:
   ```bash
   # On hub cluster
   oc get secret -n dr1 | grep kubeconfig
   ```

2. **Argo CD uses these credentials**:
   - Argo CD on hub reads the ManagedCluster secret
   - Uses the kubeconfig to connect to dr1/dr2 API server
   - No special agent needed on managed clusters

3. **Verification**:
   ```bash
   # Check Argo CD cluster connections
   argocd cluster list
   ```

## Network Requirements

### Hub Cluster Needs Access To:

1. **Git Repository**:
   - Protocol: HTTPS
   - Port: 443
   - Purpose: Pull manifests from Git

2. **Managed Cluster API Servers**:
   - Protocol: HTTPS (Kubernetes API)
   - Port: 6443 (or custom API port)
   - Purpose: Apply resources via kubectl/K8s API

### Managed Clusters Need Access To:

1. **Hub Cluster**:
   - For ACM agent (klusterlet) heartbeat
   - For status reporting back to hub

2. **NO Git Access Required**:
   - Managed clusters never pull from Git
   - All Git interaction happens on hub

## Why This Architecture?

### Advantages

✅ **Centralized Control**:
- All GitOps logic runs on hub
- Single point of configuration
- Easier to audit and secure

✅ **Simplified Managed Clusters**:
- No additional operators to install
- Smaller footprint
- Reduced maintenance

✅ **Consistent Credentials**:
- ACM manages all cluster access
- No need to configure Git credentials on each cluster
- Credential rotation handled centrally

✅ **Better for DR**:
- Managed clusters can be completely offline
- Hub can deploy when cluster comes back online
- No dependency on Git access during disaster

### Trade-offs

⚠️ **Hub is Single Point of Failure**:
- If hub is down, no deployments happen
- Existing workloads on managed clusters keep running
- Mitigation: Hub cluster should be highly available

⚠️ **Network Dependency**:
- Hub must reach all managed clusters
- Firewall rules must allow hub → managed cluster traffic
- ACM handles this via agent connections

## Comparison: Pull Model vs. Push Model

### Pull Model (What We're Using)

```
Hub (GitOps) → Pull from Git → Push to Managed Clusters via K8s API
```

- Git credentials: Only on hub
- GitOps operator: Only on hub
- Managed clusters: Just K8s API access

### Push Model (Alternative)

```
CI/CD Pipeline → Push to Each Cluster Directly
```

- Git credentials: Needed everywhere
- Each cluster needs authentication
- No centralized control

### "Agent Pull" Model (Another Alternative)

```
Each Cluster has GitOps Agent → Each Agent Pulls from Git
```

- Git credentials: On every cluster
- GitOps operator: On every cluster
- More autonomy, more complexity

## Installation Checklist

### One-Time Setup: Hub Cluster

```bash
# 1. Install ACM Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.11
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# 2. Install OpenShift GitOps Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### One-Time Setup: Managed Clusters (dr1, dr2)

```bash
# Import cluster into ACM via UI or:
oc apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: dr1
  labels:
    name: dr1
spec:
  hubAcceptsClient: true
EOF

# Then run the import command shown in ACM UI on the managed cluster
```

**That's it!** No GitOps installation needed on managed clusters.

## Verification

### Verify Hub Setup

```bash
# Check GitOps operator
oc get pods -n openshift-gitops

# Check ACM
oc get pods -n open-cluster-management

# Check ApplicationSets
oc get applicationsets -n openshift-gitops
```

### Verify Managed Cluster Connection

```bash
# On hub, check managed cluster status
oc get managedclusters

# Should show:
# NAME   HUB ACCEPTED   MANAGED CLUSTER URLS       JOINED   AVAILABLE
# dr1    true           https://api.dr1...         True     True
# dr2    true           https://api.dr2...         True     True

# Check Argo CD can reach managed clusters
oc get applications -n openshift-gitops -o wide
```

### Verify Resources Deployed

```bash
# On managed cluster (no Argo CD needed!)
oc --context dr1 get all -n vm-static-ip

# Should see resources deployed by hub's Argo CD
```

## Troubleshooting

### "Application stuck in Progressing"

**Check**: Can hub reach managed cluster API?

```bash
# On hub
oc get managedcluster dr1 -o yaml | grep conditions -A 20

# Look for "ManagedClusterConditionAvailable: True"
```

### "Could not pull from Git repository"

**Check**: Hub's Git access (not managed cluster!)

```bash
# On hub
oc logs -n openshift-gitops -l app.kubernetes.io/name=argocd-repo-server
```

### "Permission denied applying resources"

**Check**: Managed cluster credentials in ACM

```bash
# On hub
oc get secret -n dr1 -o yaml | grep kubeconfig

# Ensure ACM has valid credentials for managed cluster
```

## Summary

| Question | Answer |
|----------|--------|
| **Do managed clusters need Argo CD?** | ❌ No |
| **Do managed clusters need GitOps operator?** | ❌ No |
| **Do managed clusters need Git access?** | ❌ No |
| **Does hub need Argo CD?** | ✅ Yes |
| **Does hub need ACM?** | ✅ Yes |
| **How does hub deploy to managed clusters?** | Via Kubernetes API using ACM-managed credentials |
| **What if managed cluster can't reach Git?** | No problem - hub pulls from Git |
| **What if hub can't reach managed cluster?** | Deployment fails - hub must reach managed cluster API |

**Bottom Line**: Only install OpenShift GitOps/Argo CD on the **HUB** cluster. Managed clusters (dr1, dr2) only need to be imported into ACM.
