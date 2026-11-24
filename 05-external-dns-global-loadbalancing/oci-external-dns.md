# ExternalDNS on Oracle Cloud (OKE + OCI DNS)

Dedicated OCI guide, written for this setup:

- Home region: **US East (Ashburn)**, `us-ashburn-1`
- Existing **Basic** OKE cluster (so no workload identity unless you upgrade to Enhanced)
- Domain bought at a third-party registrar (Namecheap or GoDaddy), DNS hosted in **OCI DNS**

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
7. [Delegate the domain from your registrar](#7-delegate-the-domain-from-your-registrar)
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
| Registrar | Sells the domain and stores which nameservers it uses | Namecheap or GoDaddy |
| DNS host | Stores the records (`A`, `CNAME`, `TXT`) | OCI DNS |
| ExternalDNS | Runs in the cluster and writes records to the DNS host | Deployment in OKE |

OCI hosts DNS zones but, as far as I know, doesn't sell domains. So you buy the domain elsewhere and **delegate** it to OCI DNS by pointing the registrar's nameservers (or a subdomain's NS records) at OCI.

```
Registrar (Namecheap/GoDaddy)  ── NS records ──►  OCI DNS zone
                                                      ▲
Service/Ingress with hostname ──► ExternalDNS ────────┘ creates A + TXT records
        │
        ▼
OCI Load Balancer (public IP)  ◄── users visit app.k8s.example.com
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
| Domain | `example.com` (replace with yours) |
| DNS zone you will create | `k8s.example.com` (subdomain layout) |

Variables for the shell:

```bash
export OCI_REGION=us-ashburn-1
export CLUSTER_OCID=ocid1.cluster.oc1.iad.aaaaaaaagjb67fkcmk6fvetuwi3b4aon4hnsut2ya4rzoi2dxcwqiwk2jaiq
export COMPARTMENT_OCID=<compartment-ocid>
export ZONE=k8s.example.com
```

Find a compartment OCID: Console → **Identity & Security → Compartments** → click it → copy the OCID. Keep the cluster, worker nodes and DNS zone in the **same** dedicated compartment (for example `dns-demo`) so one narrow policy covers it.

---

## 3. Get a domain

If you already own one, skip to section 4.

### 3.1 Namecheap

1. Search for the name on namecheap.com and add it to the cart.
2. Keep **WHOIS privacy** enabled (usually free). Choose auto-renew.
3. Check out.
4. **Verify the registrant email.** ICANN sends a verification link. If you ignore it, the domain can be suspended.
5. The domain appears under **Domain List**. Leave the nameservers alone for now.

### 3.2 GoDaddy

1. Search on godaddy.com and add the domain to the cart.
2. Decline extras you don't need (email, website builder, protection plans). WHOIS privacy is usually a paid add-on there.
3. Check the **renewal price**, not just the first-year promo price.
4. Choose auto-renew and check out. Verify the ICANN email.
5. The domain appears under **My Products → Domains**. Leave nameservers alone for now.

Some TLDs have their own rules (for example, `.ke` domains go through Kenya's registry process), so check before buying one.

### 3.3 Why not use the registrar's API instead?

- **Namecheap** has no built-in ExternalDNS provider. A community webhook may exist, but I couldn't confirm a maintained one. From memory (verify): its API needs your caller's IP whitelisted, and its record-update call replaces the whole record set, so a bug can wipe unrelated records.
- **GoDaddy** does have a built-in ExternalDNS provider (`--provider=godaddy`). From memory, GoDaddy limited production DNS API access to accounts meeting certain requirements. I couldn't confirm the current rule. It also means long-lived static credentials with access to your whole domain.

Delegating to OCI DNS avoids both. That's the path in this guide.

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
- Zone name: `k8s.example.com`
- Compartment: your dedicated compartment

Or with the CLI:

```bash
oci dns zone create \
  --name $ZONE --zone-type PRIMARY \
  --compartment-id $COMPARTMENT_OCID --scope GLOBAL
```

Open the zone and copy its **4 nameservers**. They look like `ns1.p68.dns.oraclecloud.net`. You need them in the next step.

OCI DNS zones are **global**, so the region you are in doesn't affect them.

### Subdomain vs whole domain

| Layout | Zone name | Pick when |
|---|---|---|
| **Subdomain (recommended)** | `k8s.example.com` | You have existing records (email, website) at the registrar. ExternalDNS can only touch `*.k8s.example.com`. |
| Whole domain | `example.com` | The domain is only for this cluster, or you're moving all DNS to OCI. |

The rest of this guide uses the subdomain layout. For the whole-domain layout replace `k8s.example.com` with `example.com` everywhere.

---

## 7. Delegate the domain from your registrar

Until delegation works, ExternalDNS can create records but nobody can resolve them.

### Namecheap

**Subdomain:** Domain List → **Manage** → **Advanced DNS** → add 4 records: Type **NS Record**, Host `k8s`, Value = each OCI nameserver. If Namecheap rejects a trailing dot, omit it. If your account doesn't offer NS records for subdomains, use the whole-domain layout.

**Whole domain:** Domain List → **Manage** → **Nameservers** → **Custom DNS** → enter the 4 OCI nameservers → save.

### GoDaddy (menu names may differ slightly)

**Subdomain:** open the domain's **DNS** page → **Add New Record** → Type **NS**, Name `k8s`, Value = each OCI nameserver (4 records). As far as I know GoDaddy allows NS records on subdomains but not on the root (`@`). If it rejects them, use the whole-domain layout.

**Whole domain:** My Products → Domains → the domain → **DNS** → **Nameservers** → **Change Nameservers** → **I'll use my own nameservers** → enter the 4 OCI nameservers → Save.

### Before switching the whole domain

- **Copy every existing record** (A, CNAME, MX, TXT for SPF/DKIM/verification) into the OCI zone first, or email and other services break.
- If **DNSSEC** is enabled at the registrar, disable it first. A broken DNSSEC chain makes the domain fail to resolve.

### Check that delegation works

```bash
dig NS k8s.example.com +short      # subdomain layout
dig NS example.com +short          # whole-domain layout
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
            - --domain-filter=k8s.example.com
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
    external-dns.alpha.kubernetes.io/hostname: test.k8s.example.com
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

You want ExternalDNS log lines about creating records for `test.k8s.example.com`.

Verify in three places, in this order:

```bash
# 1. In OCI DNS itself
oci dns record rrset get --zone-name-or-id $ZONE \
  --domain test.k8s.example.com --compartment-id $COMPARTMENT_OCID --scope GLOBAL

# 2. Straight from one of your zone's OCI nameservers (skips caches and the registrar)
dig @<one-of-the-4-nameservers> test.k8s.example.com +short

# 3. Through normal public DNS
dig test.k8s.example.com +short
curl -I http://test.k8s.example.com
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
    - host: app.k8s.example.com        # ExternalDNS creates this record
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
| `--domain-filter=k8s.example.com` | ExternalDNS can only manage this zone. Always set it. |
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
- **Multiple hostnames:** `external-dns.alpha.kubernetes.io/hostname: a.k8s.example.com,b.k8s.example.com`.

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
| Records in OCI but don't resolve publicly | Registrar delegation missing or not propagated. Run `dig NS k8s.example.com`. |
| Whole domain stopped resolving after switching nameservers | DNSSEC still enabled at the registrar, or records weren't copied to the OCI zone |
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
dig @<oci-nameserver> test.k8s.example.com
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
6. At the registrar, remove the `k8s` NS records (or restore the original nameservers).
7. The domain itself renews each year if auto-renew is on.

Check billing the next day to make sure nothing is still running.

---

## 15. Cheat sheet

**Order of operations**

```
 1. Buy domain (Namecheap/GoDaddy) ................ verify ICANN email
 2. oci setup config; kubeconfig for the Ashburn cluster
 3. Create OCI DNS zone (k8s.example.com) ......... copy the 4 nameservers
 4. Delegate at registrar (NS records) ............ dig NS to confirm
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
