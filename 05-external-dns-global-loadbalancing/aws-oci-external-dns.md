# ExternalDNS from scratch: get a domain, then AWS (EKS + Route 53) and OCI (OKE + OCI DNS)

A to Z in one place: buy a domain, create a cluster, host the DNS zone, connect the domain, install ExternalDNS, test it, and clean up.

Pick **one track** (AWS or OCI). Sections 1 to 3 and 6 to 9 are shared.

> **Verify before production.** Versions, flags and console menus change. This guide was written without running it against live accounts. Cross-check against the ExternalDNS tutorials for [AWS](https://kubernetes-sigs.github.io/external-dns/latest/tutorials/aws/) and [OCI](https://kubernetes-sigs.github.io/external-dns/latest/tutorials/oracle/), and pin the latest ExternalDNS image tag (examples use `v0.20.0`).

---

## Contents

1. [The big picture](#1-the-big-picture)
2. [Get a domain](#2-get-a-domain)
3. [Install the tools](#3-install-the-tools)
4. [Track A: AWS (EKS + Route 53)](#4-track-a-aws-eks--route-53)
5. [Track B: OCI (OKE + OCI DNS)](#5-track-b-oci-oke--oci-dns)
6. [Test with a Service](#6-test-with-a-service)
7. [Using ExternalDNS with an Ingress](#7-using-externaldns-with-an-ingress)
8. [Flags, concepts, and production hardening](#8-flags-concepts-and-production-hardening)
9. [Troubleshooting](#9-troubleshooting)
10. [Cleanup (do this to stop billing)](#10-cleanup-do-this-to-stop-billing)
11. [Cheat sheet](#11-cheat-sheet)

---

## 1. The big picture

Three separate things, often confused:

| Thing | Job | Examples |
|---|---|---|
| **Registrar** | Sells you the domain and holds the nameserver setting | Namecheap, Route 53 Registered Domains, Cloudflare, GoDaddy |
| **DNS host** | Stores the actual records (`A`, `CNAME`, `TXT`...) | Route 53, OCI DNS, Cloud DNS |
| **ExternalDNS** | Runs in your cluster and writes records into the DNS host | this guide |

ExternalDNS cannot write records at a registrar like Namecheap. It writes to the **DNS host**, and the registrar just points to that DNS host with NS records.

```
You buy example.com at registrar ──► registrar points nameservers to DNS host
                                              │
Kubernetes: Service/Ingress ◀── ExternalDNS ──┘ writes A/CNAME/TXT records
     │
     ▼
Cloud Load Balancer (public address)  ◄── users reach app.example.com
```

Flow for a new record:

1. You create a Service or Ingress with a hostname.
2. The cloud provisions a load balancer and gives it an address.
3. ExternalDNS reads the hostname and the address, then creates the DNS record plus a TXT ownership record.

---

## 2. Get a domain

### 2.1 Where to buy

| Option | Notes |
|---|---|
| **Namecheap** (you already use it) | Good prices, free WHOIS privacy. Requires delegating DNS to AWS/OCI (section 2.4). |
| **AWS Route 53 Registered Domains** | Easiest on AWS: it creates the hosted zone and sets the nameservers for you. No delegation step. |
| **OCI** | OCI DNS hosts zones but, as far as I know, doesn't sell domains. Buy elsewhere and delegate. |
| Cloudflare Registrar, GoDaddy, etc. | Work the same as Namecheap for this guide. |

Prices depend on the TLD (`.com`, `.dev`, `.co.ke`, ...) and change, so check at checkout. Some TLDs have their own rules (for example, `.ke` domains are managed through Kenya's registry, not through global registrars like Namecheap, so check their process if you want one).

### 2.2 Buy at Namecheap

1. Go to namecheap.com and search for the name you want.
2. Add the domain to the cart. Keep **WHOIS privacy** enabled (usually free).
3. Decide on auto-renew (recommended, so you don't lose the domain).
4. Check out and pay.
5. **Verify the registrant email.** ICANN requires you to click a verification link sent to your email. If you don't, the domain can be suspended.
6. The domain appears under **Domain List**. Leave the default nameservers for now. You'll change them in section 2.4.

### 2.3 Or buy in Route 53 (AWS track only)

1. AWS Console → **Route 53 → Registered domains → Register domains**.
2. Search, add to cart, enter contact details, pay.
3. Verify the contact email (ICANN requirement, same as above).
4. Route 53 creates a public hosted zone for the domain and sets its nameservers automatically. Registration can take from minutes to a day or so.
5. Use this zone directly (skip delegation), with `--domain-filter=example.com`.

### 2.4 Delegate DNS from Namecheap to AWS/OCI

Do this **after** you create the zone in section 4.2 (AWS) or 5.2 (OCI), because you need its 4 nameservers.

Pick a layout:

| Layout | What you do in Namecheap | Use when |
|---|---|---|
| **Subdomain (recommended)** | Add NS records for `k8s` pointing to the cloud's 4 nameservers. Zone is `k8s.example.com`. | You have existing records (email, website) you don't want to disturb. ExternalDNS can only touch `*.k8s.example.com`. |
| **Whole domain** | Nameservers → **Custom DNS** → the cloud's 4 nameservers. Zone is `example.com`. | The domain is only for this cluster, or you're moving all DNS. |

**Subdomain steps**

1. Namecheap → **Domain List → Manage → Advanced DNS**.
2. Add 4 records: Type **NS Record**, Host `k8s`, Value = each nameserver. If Namecheap rejects the trailing dot, omit it.
3. If your account doesn't offer NS records for subdomains, use the whole-domain layout.

**Whole-domain steps**

1. **Before switching:** copy every existing record (A, CNAME, MX, TXT for SPF/DKIM/verification) into the new cloud zone, or email and other services will break.
2. If **DNSSEC** is enabled at Namecheap, disable it first. A broken DNSSEC chain makes the domain fail to resolve.
3. Namecheap → **Domain List → Manage → Nameservers** → **Custom DNS** → enter the 4 nameservers → save.

**Check delegation**

```bash
dig NS k8s.example.com +short     # subdomain layout
dig NS example.com +short         # whole-domain layout
```

You should see the cloud's nameservers. Propagation can take minutes to a few hours. Until this works, ExternalDNS can create records but nobody can resolve them.

> The rest of this guide uses the subdomain layout with `k8s.example.com`. For the whole-domain layout, replace `k8s.example.com` with `example.com`.

### 2.5 Namecheap's API, and why this guide doesn't use it

ExternalDNS has no built-in Namecheap provider. A community webhook provider may exist, but I couldn't confirm a maintained one. From memory (verify): the Namecheap API needs your caller's IP whitelisted, which is awkward with cluster egress IPs, and its record-update call replaces the whole record set, so a bug can wipe unrelated records. Delegating to Route 53 or OCI DNS avoids all of this.

---

## 3. Install the tools

Common: `kubectl`, `helm` (optional), `dig` (from `dnsutils` / `bind-tools`).

AWS track:

```bash
# AWS CLI v2 and eksctl: follow the official install pages, then:
aws configure                # access key, secret, default region
aws sts get-caller-identity  # confirm who you are
eksctl version
```

OCI track:

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
oci setup config             # creates ~/.oci/config and an API key pair
oci iam region list          # confirm it works
```

Choose a region close to you. For East Africa, AWS has `af-south-1` (Cape Town) and OCI has `af-johannesburg-1`.

---

## 4. Track A: AWS (EKS + Route 53)

Set variables once:

```bash
export AWS_REGION=af-south-1
export CLUSTER=dns-demo
export DOMAIN=k8s.example.com        # zone you will create/delegate
```

### 4.1 Create the EKS cluster

```bash
eksctl create cluster \
  --name $CLUSTER --region $AWS_REGION \
  --nodegroup-name ng-1 --node-type t3.medium --nodes 2 \
  --with-oidc
```

This takes about 15 to 20 minutes and **costs money while it runs** (control plane + nodes + load balancers). `--with-oidc` enables IAM Roles for Service Accounts (IRSA), which we use for ExternalDNS.

```bash
kubectl get nodes
```

### 4.2 Create the hosted zone

Skip this if you bought the domain in Route 53 and want to use its existing zone.

```bash
aws route53 create-hosted-zone --name $DOMAIN --caller-reference "$(date +%s)"

aws route53 list-hosted-zones-by-name --dns-name $DOMAIN \
  --query "HostedZones[0].Id" --output text
# returns /hostedzone/Z0123456789ABC  -> the ID is the part after /hostedzone/

aws route53 get-hosted-zone --id <ZONE_ID> \
  --query "DelegationSet.NameServers"
```

Save the **zone ID** and the **4 nameservers**.

### 4.3 Delegate from Namecheap

Follow section 2.4 using the 4 Route 53 nameservers (they look like `ns-123.awsdns-45.com`). If you registered in Route 53, skip this.

### 4.4 IAM policy

`external-dns-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets"],
      "Resource": ["arn:aws:route53:::hostedzone/<ZONE_ID>"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": ["*"]
    }
  ]
}
```

```bash
aws iam create-policy --policy-name ExternalDNSRoute53 \
  --policy-document file://external-dns-policy.json
```

Note the returned policy ARN.

### 4.5 Namespace, RBAC and ServiceAccount

Create the shared Kubernetes pieces (the RBAC is the same on both clouds, so the OCI track reuses this file). Save this as `external-dns-rbac.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
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

Create the ServiceAccount **with the IAM role attached** (IRSA):

```bash
eksctl create iamserviceaccount \
  --cluster $CLUSTER --region $AWS_REGION \
  --namespace external-dns --name external-dns \
  --attach-policy-arn arn:aws:iam::<account-id>:policy/ExternalDNSRoute53 \
  --override-existing-serviceaccounts --approve
```

This makes a role and annotates the ServiceAccount with `eks.amazonaws.com/role-arn`. No access keys involved.

*Alternative: EKS Pod Identity.*

```bash
aws eks create-addon --cluster-name $CLUSTER --addon-name eks-pod-identity-agent
aws eks create-pod-identity-association --cluster-name $CLUSTER \
  --namespace external-dns --service-account external-dns \
  --role-arn arn:aws:iam::<account-id>:role/<external-dns-role>
```

The role's trust policy must allow `pods.eks.amazonaws.com`. With Pod Identity, create a plain ServiceAccount with `kubectl create serviceaccount external-dns -n external-dns` instead of `eksctl create iamserviceaccount`.

### 4.6 Deploy ExternalDNS

`external-dns-aws.yaml`:

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
      securityContext:
        fsGroup: 65534          # lets the pod read the IRSA token
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.20.0   # pin to latest release
          args:
            - --source=service
            - --source=ingress
            - --provider=aws
            - --aws-zone-type=public
            - --domain-filter=k8s.example.com
            - --policy=upsert-only
            - --registry=txt
            - --txt-owner-id=eks-demo
          env:
            - name: AWS_DEFAULT_REGION
              value: af-south-1
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 256Mi }
```

```bash
kubectl apply -f external-dns-aws.yaml
kubectl logs -f deployment/external-dns -n external-dns
```

For load balancers with an AWS hostname (ELB/ALB/NLB), ExternalDNS creates **alias A records** automatically. Continue to [section 6](#6-test-with-a-service).

---

## 5. Track B: OCI (OKE + OCI DNS)

Collect these (Console → Profile/Tenancy):

- **Tenancy OCID**, **region** (e.g. `af-johannesburg-1`)
- **Compartment OCID** where you'll put the cluster and the DNS zone (create one, e.g. `dns-demo`, instead of using the root)

### 5.1 Create the OKE cluster

Easiest in the Console:

1. **Developer Services → Kubernetes Clusters (OKE) → Create cluster → Quick create**.
2. Name `dns-demo`, compartment `dns-demo`, Kubernetes API endpoint **Public**, workers **Public** (for a demo), shape and node count 2.
3. Cluster type: choose **Enhanced** if you want workload identity (section 5.4, option 1). Enhanced and Basic clusters are priced differently, so check current pricing.
4. Create. It takes several minutes.
5. Open the cluster → **Access Cluster** → copy the `oci ce cluster create-kubeconfig ...` command and run it:

```bash
oci ce cluster create-kubeconfig --cluster-id <cluster-ocid> \
  --file $HOME/.kube/config --region <region> \
  --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT

kubectl get nodes
```

Quick create sets up the VCN, subnets and security rules for load balancers. Note the **cluster OCID**.

### 5.2 Create the DNS zone

Console: **Networking → DNS Management → Zones → Create Zone**

- Method: Manual, Zone type: **Primary**
- Zone name: `k8s.example.com`
- Compartment: `dns-demo`

Or with the CLI:

```bash
oci dns zone create --name k8s.example.com --zone-type PRIMARY \
  --compartment-id <compartment-ocid> --scope GLOBAL
```

Open the zone and copy its **4 nameservers** (e.g. `ns1.p68.dns.oraclecloud.net`).

### 5.3 Delegate from Namecheap

Follow section 2.4 using the 4 OCI nameservers.

### 5.4 Authentication: pick one

In `oci.yaml`, `region` and the `use...` flags go **inside `auth:`**, and `compartment` is a top-level key. Only one of `useInstancePrincipal` and `useWorkloadIdentity` may be true.

| Method | Use when |
|---|---|
| 1. Workload identity | OKE **Enhanced** clusters. Per-ServiceAccount, no keys. Best practice. |
| 2. API key | Any cluster, quickest to understand. You manage a long-lived key. |
| 3. Instance principal | Worker nodes get access. Every pod on the node inherits it. |

**Option 1: Workload identity**

`oci.yaml`:

```yaml
auth:
  region: af-johannesburg-1
  useWorkloadIdentity: true
compartment: ocid1.compartment.oc1..xxxx
```

Policy (Console → Identity → Policies, in the root or parent compartment):

```
Allow any-user to manage dns in compartment dns-demo where all {
  request.principal.type = 'workload',
  request.principal.namespace = 'external-dns',
  request.principal.service_account = 'external-dns',
  request.principal.cluster_id = '<your-cluster-ocid>'
}
```

**Option 2: API key**

1. Console → **Identity → Domains → Users → Create user** (`external-dns`), then **Groups → Create group** (`dns-admins`) and add the user to it.
2. Open the user → **API keys → Add API key → Generate API key pair**. Download the private key and copy the configuration snippet (it shows the fingerprint, tenancy and user OCIDs).
3. Policy:

```
Allow group dns-admins to manage dns in compartment dns-demo
```

`oci.yaml`:

```yaml
auth:
  region: af-johannesburg-1
  tenancy: ocid1.tenancy.oc1..xxxx
  user: ocid1.user.oc1..xxxx
  fingerprint: aa:bb:cc:dd:...
  key: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
compartment: ocid1.compartment.oc1..xxxx
```

**Option 3: Instance principal**

`oci.yaml`:

```yaml
auth:
  region: af-johannesburg-1
  useInstancePrincipal: true
compartment: ocid1.compartment.oc1..xxxx
```

Create a dynamic group matching your worker nodes (for example, `ALL {instance.compartment.id = '<compartment-ocid>'}`), then:

```
Allow dynamic-group oke-nodes to manage dns in compartment dns-demo
```

### 5.5 Namespace, RBAC, ServiceAccount, Secret

Use the same `external-dns-rbac.yaml` as in section 4.5, then:

```bash
kubectl apply -f external-dns-rbac.yaml
kubectl create serviceaccount external-dns -n external-dns

kubectl create secret generic external-dns-config \
  --from-file=oci.yaml --namespace external-dns
```

### 5.6 Deploy ExternalDNS

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
kubectl logs -f deployment/external-dns -n external-dns
```

Continue to section 6.

---

## 6. Test with a Service

`nginx-test.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  annotations:
    external-dns.alpha.kubernetes.io/hostname: test.k8s.example.com
    external-dns.alpha.kubernetes.io/ttl: "300"
    # --- OCI only: flexible load balancer (uncomment on OKE) ---
    # oci.oraclecloud.com/load-balancer-type: "lb"
    # service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
    # service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
    # service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
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
kubectl get svc nginx-test -w       # wait for EXTERNAL-IP / hostname
kubectl logs deployment/external-dns -n external-dns --tail=30
```

You want to see ExternalDNS log lines about creating records for `test.k8s.example.com`.

Verify in three places, in this order:

```bash
# 1. Directly in the DNS host (skips caches and Namecheap)
#    AWS:
aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID> \
  --query "ResourceRecordSets[?contains(Name,'test')]"
#    OCI:
oci dns record rrset get --zone-name-or-id k8s.example.com \
  --domain test.k8s.example.com --compartment-id <compartment-ocid> --scope GLOBAL

# 2. Straight from one of the cloud's nameservers
dig @<one-of-the-4-nameservers> test.k8s.example.com +short

# 3. Through normal public DNS
dig test.k8s.example.com +short
curl -I http://test.k8s.example.com
```

You should find an A (or alias) record and a TXT ownership record. If step 2 works but step 3 doesn't, the Namecheap delegation isn't finished or hasn't propagated.

---

## 7. Using ExternalDNS with an Ingress

For real apps you usually expose an Ingress, not a LoadBalancer Service per app. ExternalDNS reads the hostname from `spec.rules[].host`, so no annotation is required:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  ingressClassName: <your-ingress-class>   # alb on AWS (AWS Load Balancer Controller), or your installed controller on OKE
  rules:
    - host: app.k8s.example.com            # ExternalDNS creates this record
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

The Ingress needs an ingress controller installed first (AWS Load Balancer Controller on EKS; an ingress controller such as ingress-nginx on OKE, noting that ingress-nginx was announced for retirement, so check its current status or pick a Gateway API option). Once the controller assigns an address to the Ingress, ExternalDNS publishes the record.

For HTTPS: on AWS use an ACM certificate with the ALB (`alb.ingress.kubernetes.io/certificate-arn`). On either cloud you can use cert-manager with Let's Encrypt. The DNS record must exist before the HTTP-01 challenge can pass, so first-time certificates can take a few minutes.

---

## 8. Flags, concepts, and production hardening

### Key flags

| Flag | Why |
|---|---|
| `--domain-filter=k8s.example.com` | ExternalDNS can only manage this zone. Always set it. |
| `--policy=upsert-only` | Creates and updates, never deletes. Switch to `sync` once you trust it. |
| `--registry=txt` + `--txt-owner-id=<id>` | Ownership marker. Use a **fixed, unique** ID per cluster. A random ID per restart would orphan your own records. |
| `--source=service/ingress` | What to watch. Also `gateway-httproute` for Gateway API. |
| `--interval=1m` | Reconcile frequency (default 1 minute). |
| `--dry-run` | Log changes without applying them. |

### Concepts

- **TXT ownership records:** ExternalDNS only modifies or deletes records carrying its own owner ID. It won't take over a record created by hand (delete it and let ExternalDNS recreate it).
- **One replica:** there is no leader election by default, so several replicas would race each other.
- **TTL:** set per record with `external-dns.alpha.kubernetes.io/ttl`. Keep it low during migrations.
- **Multiple hostnames:** `external-dns.alpha.kubernetes.io/hostname: a.k8s.example.com,b.k8s.example.com`.
- **Annotations like `change-id` or `requester`** that appear in some blog posts are ignored by ExternalDNS.

### Hardening checklist

- [ ] IRSA/Pod Identity (AWS) or workload identity (OCI), not static keys
- [ ] IAM/policy scoped to one zone or compartment
- [ ] `--domain-filter` set, unique `--txt-owner-id` per cluster
- [ ] Start with `upsert-only`, switch to `sync` deliberately
- [ ] Resource requests/limits, a single replica
- [ ] Network policy: allow egress only to the cloud API (443) and cluster DNS
- [ ] If you use an OCI API key: store it in a secret manager or sealed secret, rotate it
- [ ] Keep the zone's records in Terraform or exported backups for disaster recovery
- [ ] Monitor ExternalDNS logs and its Prometheus metrics (port 7979)

---

## 9. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Records in the cloud zone but don't resolve publicly | Namecheap delegation missing or not propagated. Check `dig NS k8s.example.com`. |
| Whole domain stopped resolving after switching nameservers | DNSSEC still enabled at Namecheap, or records weren't copied to the new zone |
| Email broke after switching nameservers | MX/TXT records weren't copied to the new zone |
| No records created, no errors | `--domain-filter` doesn't match (hostname must be inside the zone) |
| Service stuck on `<pending>` | Load balancer provisioning problem (quota, subnets, OCI annotations). Run `kubectl describe svc`. |
| `NotAuthorizedOrNotFound` (OCI) | Policy missing, wrong compartment OCID, or wrong cluster OCID in the workload identity policy |
| No zones found (OCI) | Zone in another compartment, or `--oci-zone-scope` mismatch (GLOBAL vs PRIVATE) |
| `AccessDenied` or `NoCredentialProviders` (AWS) | IRSA annotation/Pod Identity association missing, no `fsGroup: 65534`, or region env not set |
| Existing record not updated | It has no ExternalDNS TXT marker. Delete it and let ExternalDNS recreate it. |
| Records flap or disappear | Two clusters share one `--txt-owner-id`, or more than one replica is running |
| Certificate stuck `Pending` | DNS record not live yet. Check `kubectl describe challenge`. |

Useful commands:

```bash
kubectl logs -f deployment/external-dns -n external-dns
kubectl describe svc nginx-test
kubectl auth can-i list services --as=system:serviceaccount:external-dns:external-dns
dig @<cloud-nameserver> test.k8s.example.com
```

---

## 10. Cleanup (do this to stop billing)

Order matters, otherwise load balancers and zones get left behind.

1. **Delete the test app and any LoadBalancer Services/Ingresses first**, so the cloud removes their load balancers:

```bash
kubectl delete -f nginx-test.yaml
kubectl get svc -A | grep LoadBalancer     # should be empty
```

2. **Delete the DNS records** ExternalDNS created (with `upsert-only` it won't remove them), including the TXT ownership records. A hosted zone can't be deleted while it still has records beyond its default NS/SOA.
3. Delete ExternalDNS:

```bash
kubectl delete -f external-dns-aws.yaml    # or external-dns-oci.yaml
kubectl delete -f external-dns-rbac.yaml
```

4. **Delete the cluster.**

AWS:

```bash
eksctl delete cluster --name $CLUSTER --region $AWS_REGION
aws route53 delete-hosted-zone --id <ZONE_ID>
aws iam delete-policy --policy-arn arn:aws:iam::<account-id>:policy/ExternalDNSRoute53
```

OCI: Console → the OKE cluster → **Delete** (also remove the node pool and, if you want, the VCN created by Quick create). Then delete the DNS zone and the IAM policies/user you created.

5. In Namecheap, remove the `k8s` NS records (or restore the original nameservers).
6. Don't forget the domain itself renews each year if auto-renew is on.

Check the billing dashboards the next day to make sure nothing is still running.

---

## 11. Cheat sheet

**Order of operations**

```
 1. Buy domain (Namecheap or Route 53)            -> verify ICANN email
 2. Create cluster (EKS or OKE)
 3. Create DNS zone (Route 53 or OCI DNS)         -> copy the 4 nameservers
 4. Delegate at Namecheap (NS records / Custom DNS) -> dig NS to confirm
 5. Create IAM policy / OCI policy
 6. Apply RBAC + ServiceAccount (IRSA / workload identity)
 7. Deploy ExternalDNS (upsert-only, domain-filter, txt-owner-id)
 8. Deploy test Service -> verify record in zone -> verify public DNS
 9. Real apps via Ingress -> TLS
10. Switch to sync when confident
```

**Provider differences at a glance**

| | AWS | OCI |
|---|---|---|
| Cluster | EKS (`eksctl`) | OKE (Console quick create) |
| Zone | Route 53 hosted zone | OCI DNS primary zone |
| `--provider` | `aws` | `oci` |
| Credentials | IRSA / Pod Identity | Workload identity / API key / instance principal |
| Config | env `AWS_DEFAULT_REGION`, `fsGroup: 65534` | `oci.yaml` in a Secret, `--oci-config-file` |
| Records for LB hostnames | Alias A | A / CNAME |
| Registrar built in | Yes (Route 53 Registered Domains) | No, buy elsewhere |

---

## References

- ExternalDNS docs: https://kubernetes-sigs.github.io/external-dns/
- AWS tutorial: https://kubernetes-sigs.github.io/external-dns/latest/tutorials/aws/
- OCI tutorial: https://kubernetes-sigs.github.io/external-dns/latest/tutorials/oracle/
- Webhook providers: https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/webhook-provider
