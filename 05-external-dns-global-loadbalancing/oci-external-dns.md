# ExternalDNS on Oracle Cloud (OKE + OCI DNS)

Dedicated OCI guide, written for this setup:

- Home region: **US East (Ashburn)**, `us-ashburn-1`
- Existing **Basic** OKE cluster (so no workload identity unless you upgrade to Enhanced)
- Domain registered at **GoDaddy**, DNS hosted in **OCI DNS**

Goal: when you create a Kubernetes Service or Ingress with a hostname, ExternalDNS creates the DNS record in OCI DNS automatically.

> **Verify before production.** This was written without running it against your tenancy. Console menus and ExternalDNS flags change. Cross-check with the [ExternalDNS OCI tutorial](https://kubernetes-sigs.github.io/external-dns/latest/tutorials/oracle/) and pin the latest ExternalDNS image tag (examples use `v0.20.0`).

---

## Contents

1. [How it fits together](#1-how-it-fits-together)
2. [Your values](#2-your-values)
3. [Get a domain](#3-get-a-domain)
4. [Install and configure the OCI CLI](#4-install-and-configure-the-oci-cli)
5. [Connect to your OKE cluster](#5-connect-to-your-oke-cluster)
6. [Create the DNS zone](#6-create-the-dns-zone)
7. [Delegate the domain at GoDaddy](#7-delegate-the-domain-at-godaddy)
8. [Give ExternalDNS permission (authentication)](#8-give-externaldns-permission-authentication)
9. [Deploy ExternalDNS](#9-deploy-externaldns)
10. [Test it](#10-test-it)
11. [Using it with an Ingress](#11-using-it-with-an-ingress)
12. [Production hardening and flags](#12-production-hardening-and-flags)
13. [Troubleshooting](#13-troubleshooting)
14. [Cleanup](#14-cleanup)
15. [Cheat sheet](#15-cheat-sheet)

---

## 1. How it fits together

Three separate things:

| Thing | Job | In your setup |
|---|---|---|
| Registrar | Sells the domain and stores which nameservers it uses | GoDaddy |
| DNS host | Stores the records (`A`, `CNAME`, `TXT`) | OCI DNS |
| ExternalDNS | Runs in the cluster and writes records to the DNS host | Deployment in OKE |

OCI hosts DNS zones but, as far as I know, doesn't sell domains. So you buy the domain elsewhere and **delegate** it to OCI DNS by pointing GoDaddy's nameservers at OCI.

```
Registrar (GoDaddy)  ── nameservers ──►  OCI DNS zone
                                                      ▲
Service/Ingress with hostname ──► ExternalDNS ────────┘ creates A + TXT records
        │
        ▼
OCI Load Balancer (public IP)  ◄── users visit app.zinglow.it.com
```

Flow for each new hostname:

1. You create a Service (type `LoadBalancer`) or an Ingress with a hostname.
2. OKE provisions an OCI Load Balancer and gives it a public IP.
3. ExternalDNS sees the hostname and IP, then creates an `A` record plus a `TXT` ownership record in the zone.

---

## 2. Your values

Fill these in once and keep them handy.

| Item | Value |
|---|---|
| Region | `us-ashburn-1` |
| Cluster OCID | `ocid1.cluster.oc1.iad.aaaaaaaagjb67fkcmk6fvetuwi3b4aon4hnsut2ya4rzoi2dxcwqiwk2jaiq` |
| Cluster type | Basic |
| Compartment (cluster + zone) | `<compartment-name>` / `<compartment-ocid>` |
| Domain | `zinglow.it.com` (an `it.com` name, see section 3.4) |
| DNS zone you will create | `zinglow.it.com` (whole-domain layout, because nothing else uses the domain) |

Variables for the shell:

```bash
export OCI_REGION=us-ashburn-1
export CLUSTER_OCID=ocid1.cluster.oc1.iad.aaaaaaaagjb67fkcmk6fvetuwi3b4aon4hnsut2ya4rzoi2dxcwqiwk2jaiq
export COMPARTMENT_OCID=<compartment-ocid>
export ZONE=zinglow.it.com
```

Find a compartment OCID: Console → **Identity & Security → Compartments** → click it → copy the OCID. Keep the cluster, worker nodes and DNS zone in the **same** dedicated compartment (for example `dns-demo`) so one narrow policy covers it.

---

## 3. Get a domain

If you already own one, skip to section 4.

### 3.1 GoDaddy

1. Search on godaddy.com and add the domain to the cart.
2. Decline extras you don't need (email, website builder, protection plans). WHOIS privacy is usually a paid add-on there.
3. Check the **renewal price**, not just the first-year promo price.
4. Choose auto-renew and check out. Complete any verification email GoDaddy sends.
5. The domain appears under **My Products → Domains**. Leave the nameservers alone for now.

### 3.2 About `.it.com`

`it.com` is a second-level domain run by CentralNic, so `zinglow.it.com` is a third-level name under it (not Italy's `.it`). Delegating DNS should work through GoDaddy's nameserver settings, but I couldn't find anything confirming how it behaves, so check with the `dig` commands in section 7. ICANN-style verification emails may not apply to this kind of domain, so just complete whatever verification email GoDaddy sent.

### 3.3 Why not use GoDaddy's API instead?

ExternalDNS has a built-in GoDaddy provider (`--provider=godaddy`), so you could keep DNS at GoDaddy and skip OCI DNS. This guide delegates to OCI DNS instead:

- From memory, GoDaddy limited production DNS API access to accounts meeting certain requirements. I couldn't confirm the current rule, so you'd need to check that your account can create a production key.
- It means long-lived static API credentials with access to your whole domain's DNS, instead of a narrowly scoped OCI policy.

---

## 4. Install and configure the OCI CLI

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
oci setup config      # asks for tenancy OCID, user OCID, region; generates an API key pair
oci iam region list   # confirms it works
```

`oci setup config` prints a public key. Upload it in Console → Profile → **API keys → Add API key → Paste public key**. Use `us-ashburn-1` as the region.

Install `kubectl` and `dig` (package `dnsutils` on Debian/Ubuntu, `bind-tools` on Alpine) if you don't have them.

---

## 5. Connect to your OKE cluster

```bash
oci ce cluster create-kubeconfig \
  --cluster-id $CLUSTER_OCID \
  --file $HOME/.kube/config \
  --region $OCI_REGION \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT

kubectl get nodes
```

If your cluster's API endpoint is private, use the Console's **Access Cluster** instructions instead (Cloud Shell or a bastion).

Find which compartment your worker nodes are in (needed in section 8): Console → cluster → **Node pools** → the node pool shows its compartment, or open any node's instance page.

---

## 6. Create the DNS zone

Console: **Networking → DNS Management → Zones → Create Zone**

- Method: **Manual**
- Zone type: **Primary**
- Zone name: `zinglow.it.com`
- Compartment: your dedicated compartment

Or with the CLI:

```bash
oci dns zone create \
  --name $ZONE --zone-type PRIMARY \
  --compartment-id $COMPARTMENT_OCID --scope GLOBAL
```

Open the zone and copy its **4 nameservers**. They look like `ns1.p68.dns.oraclecloud.net`. You need them in the next step.

OCI DNS zones are **global**, so the region you are in doesn't affect them.

### Layout: whole domain

Nothing else uses `zinglow.it.com`, so the zone is the whole domain and ExternalDNS manages names like `test.zinglow.it.com` and `app.zinglow.it.com`. If you later put email or a website on this domain, add those records (MX, TXT, etc.) to the same OCI zone.

Alternative if you ever need to keep other DNS elsewhere: create a zone for a subdomain such as `k8s.zinglow.it.com`, add NS records for `k8s` in GoDaddy's DNS panel, and use `--domain-filter=k8s.zinglow.it.com`. As far as I know GoDaddy allows NS records on subdomains but not on the root, but I haven't verified that for this domain.

---

## 7. Delegate the domain at GoDaddy

Until delegation works, ExternalDNS can create records but nobody can resolve them.

Menu names may differ slightly, so verify in the GoDaddy UI:

1. My Products → Domains → click `zinglow.it.com`.
2. Open its **DNS** page → **Nameservers** → **Change Nameservers**.
3. Choose **I'll use my own nameservers** and enter the 4 OCI nameservers from your zone (`ns1.p68.dns.oraclecloud.net` style).
4. Save.

### Before switching nameservers

- If GoDaddy added any default records you care about (parking page, email forwarding), note them first. Nothing else uses the domain, so there is nothing else to preserve.
- If **DNSSEC** is enabled at GoDaddy, disable it first. A broken DNSSEC chain makes the domain fail to resolve.

### Check that delegation works

```bash
dig NS zinglow.it.com +short
dig NS zinglow.it.com +trace      # shows where the chain breaks if it fails
```

You should see the OCI nameservers. Propagation takes minutes to a few hours.

---

## 8. Give ExternalDNS permission (authentication)

ExternalDNS needs permission to manage records in your compartment. Your options on a **Basic** cluster:

| Method | Works on Basic? | Notes |
|---|---|---|
| **A. Instance principal** | Yes | **Recommended here.** No keys to store. Any pod on a worker node can use the node's DNS access, so scope the policy to one compartment. |
| **B. API key** | Yes | Dedicated user with a DNS-only policy. The private key lives in a Kubernetes Secret you must protect and rotate. |
| **C. Workload identity** | **No** (needs an Enhanced cluster) | Best practice, per-pod and keyless. See the upgrade note below. |

In every `oci.yaml`, `region` and the `use...` flags go **inside `auth:`**, and `compartment` is a top-level key. Only one of `useInstancePrincipal` and `useWorkloadIdentity` may be true.

### Option A: Instance principal (recommended)

**1. Dynamic group.** Console → **Identity & Security → Domains → Default domain → Dynamic groups → Create dynamic group**. Name `oke-nodes`, with this matching rule (use the compartment that holds your worker nodes):

```
ALL {instance.compartment.id = '<worker-node-compartment-ocid>'}
```

**2. Policy.** Console → **Identity & Security → Policies → Create Policy** (in the root compartment or a parent of the zone's compartment):

```
Allow dynamic-group oke-nodes to manage dns in compartment <compartment-name>
```

If your tenancy uses identity domains and the group isn't in the Default domain, write it as `dynamic-group '<domain>'/'oke-nodes'`.

**3. `oci.yaml`:**

```yaml
auth:
  region: us-ashburn-1
  useInstancePrincipal: true
compartment: <compartment-ocid-holding-the-zone>
```

### Option B: API key

1. Console → **Identity & Security → Domains → Default domain → Users → Create user** (`external-dns`). Then **Groups → Create group** (`dns-admins`) and add the user.
2. Open the user → **API keys → Add API key → Generate API key pair**. Download the private key and copy the configuration snippet (fingerprint, tenancy OCID, user OCID).
3. Policy:

```
Allow group dns-admins to manage dns in compartment <compartment-name>
```

4. `oci.yaml`:

```yaml
auth:
  region: us-ashburn-1
  tenancy: ocid1.tenancy.oc1..xxxx
  user: ocid1.user.oc1..xxxx
  fingerprint: aa:bb:cc:dd:...
  key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
compartment: <compartment-ocid-holding-the-zone>
```

Don't commit this file to Git. Rotate the key regularly.

### Option C: Workload identity (needs Enhanced)

On the cluster's page, look for an option to upgrade a Basic cluster to Enhanced. I believe it can't be reversed, and Enhanced is priced differently, so check current pricing first. Once Enhanced:

`oci.yaml`:

```yaml
auth:
  region: us-ashburn-1
  useWorkloadIdentity: true
compartment: <compartment-ocid-holding-the-zone>
```

Policy:

```
Allow any-user to manage dns in compartment <compartment-name> where all {
  request.principal.type = 'workload',
  request.principal.namespace = 'external-dns',
  request.principal.service_account = 'external-dns',
  request.principal.cluster_id = 'ocid1.cluster.oc1.iad.aaaaaaaagjb67fkcmk6fvetuwi3b4aon4hnsut2ya4rzoi2dxcwqiwk2jaiq'
}
```

---

## 9. Deploy ExternalDNS

### 9.1 Namespace and RBAC

`external-dns-rbac.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods"]
    verbs: ["get", "watch", "list"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "watch", "list"]
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: external-dns
```

```bash
kubectl apply -f external-dns-rbac.yaml
```

### 9.2 Config Secret

Save the `oci.yaml` from section 8, then:

```bash
kubectl create secret generic external-dns-config \
  --from-file=oci.yaml --namespace external-dns
```

### 9.3 Deployment

`external-dns-oci.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels: { app: external-dns }
  template:
    metadata:
      labels: { app: external-dns }
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.20.0   # pin to latest release
          args:
            - --source=service
            - --source=ingress
            - --provider=oci
            - --oci-zone-scope=GLOBAL
            - --oci-config-file=/etc/kubernetes/oci.yaml
            - --domain-filter=zinglow.it.com
            - --policy=upsert-only
            - --registry=txt
            - --txt-owner-id=oke-demo
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 256Mi }
          volumeMounts:
            - name: oci-config
              mountPath: /etc/kubernetes
              readOnly: true
      volumes:
        - name: oci-config
          secret:
            secretName: external-dns-config
```

```bash
kubectl apply -f external-dns-oci.yaml
kubectl get pods -n external-dns
kubectl logs -f deployment/external-dns -n external-dns
```

Healthy logs show it finding your zone with no authorization errors. If you see `NotAuthorizedOrNotFound`, go to the troubleshooting table.

---

## 10. Test it

`nginx-test.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  annotations:
    external-dns.alpha.kubernetes.io/hostname: test.zinglow.it.com
    external-dns.alpha.kubernetes.io/ttl: "300"
    oci.oraclecloud.com/load-balancer-type: "lb"
    service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
spec:
  type: LoadBalancer
  selector:
    app: nginx-test
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
spec:
  replicas: 1
  selector:
    matchLabels: { app: nginx-test }
  template:
    metadata:
      labels: { app: nginx-test }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
```

```bash
kubectl apply -f nginx-test.yaml
kubectl get svc nginx-test -w                       # wait for EXTERNAL-IP
kubectl logs deployment/external-dns -n external-dns --tail=30
```

You want ExternalDNS log lines about creating records for `test.zinglow.it.com`.

Verify in three places, in this order:

```bash
# 1. In OCI DNS itself
oci dns record rrset get --zone-name-or-id $ZONE \
  --domain test.zinglow.it.com --compartment-id $COMPARTMENT_OCID --scope GLOBAL

# 2. Straight from one of your zone's OCI nameservers (skips caches and GoDaddy)
dig @<one-of-the-4-nameservers> test.zinglow.it.com +short

# 3. Through normal public DNS
dig test.zinglow.it.com +short
curl -I http://test.zinglow.it.com
```

You should see an `A` record and a `TXT` ownership record. If step 2 works but step 3 doesn't, delegation (section 7) isn't finished or hasn't propagated.

---

## 11. Using it with an Ingress

For real apps you usually expose an Ingress rather than one LoadBalancer Service per app. ExternalDNS reads the hostname from `spec.rules[].host`, so no annotation is needed:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  ingressClassName: <your-ingress-class>
  rules:
    - host: app.zinglow.it.com        # ExternalDNS creates this record
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

You need an ingress controller installed first. ingress-nginx was announced for retirement (maintenance end around March 2026), so check its current status or consider a Gateway API implementation. On OKE the controller's Service of type `LoadBalancer` gets the OCI load balancer, and ExternalDNS publishes records pointing at it.

For HTTPS, use cert-manager with Let's Encrypt. The DNS record must exist before the HTTP-01 challenge can pass, so first-time certificates can take a few minutes. Install:

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set crds.enabled=true
```

---

## 12. Production hardening and flags

### Key flags

| Flag | Why |
|---|---|
| `--domain-filter=zinglow.it.com` | ExternalDNS can only manage this zone. Always set it. |
| `--policy=upsert-only` | Creates and updates, never deletes. Switch to `sync` once you trust it. |
| `--registry=txt` + `--txt-owner-id=<id>` | Ownership marker. Use a **fixed, unique** ID per cluster. A random ID per restart would orphan your own records. |
| `--oci-zone-scope=GLOBAL` | Public zones. Use `PRIVATE` for VCN-only zones. |
| `--source=service/ingress` | What to watch. Also `gateway-httproute` for Gateway API. |
| `--interval=1m` | Reconcile frequency (default 1 minute). |
| `--dry-run` | Log changes without applying them. |

### Concepts

- **TXT ownership records:** ExternalDNS only modifies or deletes records carrying its own owner ID. It won't take over a record you created by hand. Delete it and let ExternalDNS recreate it.
- **One replica only:** there is no leader election by default, so several replicas would race each other.
- **TTL:** set per record with `external-dns.alpha.kubernetes.io/ttl`. Keep it low during migrations.
- **Multiple hostnames:** `external-dns.alpha.kubernetes.io/hostname: a.zinglow.it.com,b.zinglow.it.com`.

### Checklist

- [ ] Policy scoped to **one compartment** that holds only the zone
- [ ] `--domain-filter` set, unique `--txt-owner-id` per cluster
- [ ] Start with `upsert-only`, switch to `sync` deliberately
- [ ] Single replica with resource requests/limits
- [ ] Network policy restricting ExternalDNS egress to the OCI API (443) and cluster DNS
- [ ] API key (if used) in a secret manager or sealed secret, rotated regularly
- [ ] For production: upgrade to Enhanced and use workload identity
- [ ] Back up zone records (export or Terraform)
- [ ] Monitor logs and ExternalDNS's Prometheus metrics (port 7979)

---

## 13. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Records in OCI but don't resolve publicly | Delegation at GoDaddy missing or not propagated. Run `dig NS zinglow.it.com`. |
| Whole domain stopped resolving after switching nameservers | DNSSEC still enabled at GoDaddy, or records weren't copied to the OCI zone |
| Email broke after switching nameservers | MX/TXT records weren't copied to the OCI zone |
| `NotAuthorizedOrNotFound` in logs | Policy missing, wrong compartment in the policy or in `oci.yaml`, or (instance principal) the dynamic group rule doesn't match your worker nodes' compartment. OCI returns this one error for both "not allowed" and "doesn't exist". |
| No zones found | Zone is in a different compartment than `oci.yaml` says, or scope mismatch (GLOBAL vs PRIVATE) |
| No records created, no errors | `--domain-filter` doesn't match (the hostname must be inside the zone) |
| Service stuck on `<pending>` | Load balancer provisioning issue (service limits, subnets, annotations). Run `kubectl describe svc nginx-test`. |
| Existing record never updated | It has no ExternalDNS TXT marker. Delete it and let ExternalDNS recreate it. |
| Records flap or disappear | Two clusters share one `--txt-owner-id`, or more than one replica is running |
| Pod can't authenticate with instance principal | Pods may not reach the node's metadata service if network policy or a hardened config blocks it. Check pod logs. |
| Certificate stuck `Pending` | DNS record not live yet. Run `kubectl describe challenge -A`. |

Useful commands:

```bash
kubectl logs -f deployment/external-dns -n external-dns
kubectl describe svc nginx-test
kubectl auth can-i list services --as=system:serviceaccount:external-dns:external-dns
dig @<oci-nameserver> test.zinglow.it.com
```

Tip: run once with `--dry-run --log-level=debug` to see what ExternalDNS would change.

---

## 14. Cleanup

Order matters, otherwise load balancers and zones get left behind.

1. **Delete the test app and any LoadBalancer Services/Ingresses first** so OCI removes their load balancers:

```bash
kubectl delete -f nginx-test.yaml
kubectl get svc -A | grep LoadBalancer     # should be empty
```

2. **Delete the DNS records** ExternalDNS created (`upsert-only` won't remove them), including the `TXT` ownership records. Console: the zone → **Records**.
3. Delete ExternalDNS:

```bash
kubectl delete -f external-dns-oci.yaml
kubectl delete secret external-dns-config -n external-dns
kubectl delete -f external-dns-rbac.yaml
```

4. Delete the DNS zone (Console → the zone → **Delete**), then the IAM pieces you created: the policy, the dynamic group `oke-nodes`, and for the API-key route the user, group, and key.
5. If you're finished with the cluster: Console → the OKE cluster → **Delete** (also remove the node pool, and the VCN if Quick create made one for it).
6. At GoDaddy, restore the original nameservers (or leave them pointing at OCI if you'll keep using OCI DNS).
7. The domain itself renews each year if auto-renew is on.

Check billing the next day to make sure nothing is still running.

---

## 15. Cheat sheet

**Order of operations**

```
 1. Buy domain at GoDaddy ........................ complete any verification email
 2. oci setup config; kubeconfig for the Ashburn cluster
 3. Create OCI DNS zone (zinglow.it.com) ......... copy the 4 nameservers
 4. Set OCI nameservers at GoDaddy ............... dig NS to confirm
 5. Dynamic group + DNS policy (instance principal)
 6. kubectl apply RBAC; create Secret from oci.yaml
 7. Deploy ExternalDNS (upsert-only, domain-filter, txt-owner-id)
 8. Deploy test Service -> record in zone -> public DNS resolves
 9. Real apps via Ingress -> TLS
10. Switch to sync when confident; upgrade to Enhanced for workload identity
```

**Your `oci.yaml` (instance principal)**

```yaml
auth:
  region: us-ashburn-1
  useInstancePrincipal: true
compartment: <compartment-ocid-holding-the-zone>
```

---

## References

- ExternalDNS docs: https://kubernetes-sigs.github.io/external-dns/
- OCI tutorial: https://kubernetes-sigs.github.io/external-dns/latest/tutorials/oracle/
- OCI DNS docs: https://docs.oracle.com/en-us/iaas/Content/DNS/home.htm
- cert-manager: https://cert-manager.io/docs/
