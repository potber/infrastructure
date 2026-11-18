# Server and Kubernetes security audit — 2026-11-18

## Outcome

The cluster was healthy and serving production traffic at the time of the review, but it was **not fully updated** and should not be considered security-current.

The highest-priority work is:

1. Reboot all three nodes into the already-installed Ubuntu security kernel.
2. Upgrade K3s from `v1.35.2+k3s1` to `v1.35.10+k3s1`.
3. Upgrade Flux from `v2.8.3` to at least `v2.9.4` and replace its vulnerable `allow-webhooks` NetworkPolicy.
4. Upgrade cert-manager from `v1.20.0` to `v1.21.3`.
5. Repair or remove the expired preview wildcard certificate.
6. Begin migration away from the retired ingress-nginx project.

The original review was read-only. No packages, workloads, firewall rules, or cluster resources were changed during the audit itself.

## Remediation completed after the review

The following live fixes were completed later on 2026-11-18 without restarting cluster nodes:

- Flux's `allow-webhooks` NetworkPolicy was restricted to TCP 9292.
- cert-manager was upgraded from `v1.20.0` to the security-fixed `v1.20.5` patch release.
- ingress-nginx was configured to reject snippet annotations and annotations above Medium risk.
- the Hetzner DNS API token was rotated and validated against the `potber.de` zone.
- the expired preview wildcard certificate was reissued and externally verified on both preview hosts. It is valid until 2027-02-16 and scheduled to renew on 2027-01-17.
- Tailscale private administration was enabled through `cluster-master1`, which advertises the Hetzner `10.0.0.0/16` network. The local kubeconfig now uses `10.0.0.2:6443`, and public TCP 22 and 6443 were externally verified closed on all three nodes.

The remaining findings below preserve the state observed during the original audit and explain why each remediation was required.

## Live inventory and health

| Area | Observed state | Assessment |
| --- | --- | --- |
| Nodes | One control-plane/etcd node and two workers; all `Ready` | Healthy, but the single control plane is still a control-plane and etcd single point of failure |
| Operating system | Ubuntu 24.04.3 LTS on all nodes | Supported |
| Running kernel | `6.8.0-136-generic` on all nodes | Old; security-fixed `6.8.0-149` is installed but not active |
| K3s | `v1.35.2+k3s1` | Eight patch releases behind the current 1.35 line and affected by published advisories |
| containerd | `2.1.5-k3s1` | Affected by published 2026 advisories; upgraded with K3s 1.35.10 |
| ingress-nginx | `v1.15.1` | Final upstream release; project retired and a newer issue has no upstream fix |
| cert-manager | `v1.20.0` | Below security-fixed `1.20.3`; upgrade recommended |
| Flux | `v2.8.3` | Affected by a high-severity NetworkPolicy advisory and a source-controller path traversal advisory |
| Hetzner CCM / CSI | `v1.30.1` / `v2.20.2` | Working, but behind current upstream releases; review after the urgent upgrades |
| Workloads | All observed pods running; production replicas spread across both workers | Healthy |
| GitOps | All Flux reconciliations observed as Ready | Healthy |

No failed workload, unexpected cross-namespace pod, or obvious compromise indicator was visible in the pods, Kubernetes events, certificate resources, or controller state inspected. This is not equivalent to a forensic compromise assessment: API audit logs, host authentication logs over a long retention window, registry provenance, SBOMs, and application images were not exhaustively analyzed.

## Findings

### 1. Ubuntu security fixes are installed but not running

All nodes run `6.8.0-136-generic`, while `6.8.0-149-generic` is already installed and `/var/run/reboot-required` is present. Ubuntu's [USN-9022-1](https://ubuntu.com/security/notices/USN-9022-1) identifies `6.8.0-149.149` as the security-fixed generic kernel and explicitly requires a reboot for the changes to take effect.

Automatic security updates are enabled and were installing packages daily. At the time of the check:

- control plane and worker 1 each had 64 non-security updates pending and no pending standard security update;
- worker 2 had 69 updates pending, including two standard security updates (`needrestart` and `sosreport`) that unattended-upgrades had not yet applied;
- all three nodes required a reboot.

Recommended action: perform a rolling worker reboot, one worker at a time, then reboot the single control plane in a short maintenance window. Draining workers first preserves the two-replica production workloads. The applications should continue running during the control-plane reboot, but the Kubernetes API and scheduling/control operations will be unavailable because there is only one control-plane node.

### 2. K3s and bundled containerd are security-outdated

The system-upgrade-controller Plans both reported Complete, but they are pinned to the installed `v1.35.2+k3s1`; they do not track new patch releases automatically. The repository also pins `v1.35.2+k3s1` in `hetzner/cluster.yaml.tpl`.

Confirmed version exposures:

- [K3s GHSA-jxr7-mqhw-9p98 / CVE-2026-54250](https://github.com/k3s-io/k3s/security/advisories/GHSA-jxr7-mqhw-9p98) affects K3s through `v1.35.2+k3s1` and is fixed in `v1.35.3+k3s1`. It requires an administrator to restore a malicious compressed etcd snapshot, so practical exposure is limited, but the installed version is explicitly affected.
- [Kubernetes CVE-2026-2270](https://github.com/kubernetes/kubernetes/issues/142097) affects Kubernetes through 1.35.8 and is fixed in 1.35.9. Exploitation requires high namespace-scoped permissions on StatefulSets and ControllerRevisions.
- [containerd CVE-2026-53488](https://github.com/containerd/containerd/security/advisories/GHSA-xhf5-7wjv-pqxp) includes containerd 2.1.5 in the affected range. A malicious image label can reach host command execution through a consuming plugin; using only trusted images reduces but does not remove the need to patch.
- [containerd CVE-2026-95837](https://github.com/containerd/containerd/security/advisories/GHSA-p7v4-vr35-mj6f) affects the installed containerd version when CRI checkpoint restore is used with an untrusted checkpoint.

The recommended same-minor target is [K3s `v1.35.10+k3s1`](https://github.com/k3s-io/k3s/releases/tag/v1.35.10%2Bk3s1), which includes Kubernetes 1.35.10 and containerd 2.2.10-k3s1. Kubernetes 1.35 remains supported until February 2027, so a minor-version jump is not required for this immediate remediation.

### 3. Flux has a live, confirmed high-severity configuration exposure

The installed distribution is Flux `v2.8.3`, with notification-controller `v1.8.2` and source-controller `v1.8.1`.

[Flux GHSA-mwcp-qpcg-fr7c](https://github.com/fluxcd/flux2/security/advisories/GHSA-mwcp-qpcg-fr7c) affects Flux versions before 2.9.4. The live `allow-webhooks` NetworkPolicy exactly matches the vulnerable pattern: it permits traffic from every namespace to notification-controller without restricting the destination port. A compromised application pod could therefore reach the event server and potentially forge events/status updates or cause denial of service.

The installed source-controller is also affected by [GHSA-jjrm-hr5f-673x / CVE-2026-47680](https://github.com/fluxcd/source-controller/security/advisories/GHSA-jjrm-hr5f-673x), fixed in source-controller 1.8.5. Exploitation requires influence over a referenced bucket or permission to create/update GitRepository resources.

Recommended action: apply the advisory's NetworkPolicy restriction to TCP port 9292 as a short-term containment, then upgrade Flux to at least `v2.9.4`. Follow Flux's migration guidance because the upgrade removes old API versions.

### 4. cert-manager is below a high-severity security fix

The installed cert-manager `v1.20.0` is affected by [GHSA-8rvj-mm4h-c258 / CVE-2026-62290](https://github.com/cert-manager/cert-manager/security/advisories/GHSA-8rvj-mm4h-c258), fixed in 1.20.3. A namespace user who can create ACME Challenge resources can make cert-manager use ClusterIssuer DNS credentials outside the issuer's intended solver policy.

The default service accounts in `potber-prod`, `potber-test`, and `potber-previews` were checked and cannot create Challenge resources, which reduces the immediate exploitability. The vulnerable code is nevertheless present, and other privileged identities were not exhaustively enumerated.

Recommended target: [cert-manager `v1.21.3`](https://github.com/cert-manager/cert-manager/releases/tag/v1.21.3). It includes the advisory fix, supports Kubernetes 1.35, and removes trust related to the 2026 eMudhra CA compromise.

### 5. ingress-nginx is patched for the older high-severity issues, but upstream is retired

The live controller is ingress-nginx `v1.15.1`, not an older 1.13 release. It is at or above the fixed versions for the March 2026 configuration-injection issues, including [CVE-2026-4342](https://github.com/kubernetes/kubernetes/issues/137893).

However, ingress-nginx was [retired on March 24, 2026](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/), so it receives no more upstream security releases. The November advisory [CVE-2026-116472](https://github.com/kubernetes/kubernetes/issues/143852) affects ingress-nginx and has no upstream fix. It is rated low and requires permission to create or modify an Ingress. No `mirror-target`, rewrite, snippet, or authentication annotations were present in the cluster's Ingress resources, so the observed configuration does not show an active exploit path for this issue.

Recommended action: migrate to a maintained Gateway API or Ingress controller. Until then, restrict who may create/update Ingress resources, reject `mirror-target`, and set the annotation risk level to Medium or Low if compatible with the workloads.

### 6. The preview wildcard certificate is expired

`*.preview.potber.de` expired on 2026-10-09. Renewal has been pending for about 70 days because the Hetzner DNS API rejects the configured token as invalid/unauthorized. External TLS verification of `pr-107.preview.potber.de` fails with an expired-certificate error; production `potber.de` returned HTTP 200 with valid TLS.

The affected preview Ingresses are PR 107 and PR 132, both old. Either rotate the Hetzner DNS token and reissue the wildcard certificate, or remove the stale preview environments if they are no longer needed. Do not rely on the Certificate object's stale `Ready=True` condition; its `notAfter` value and the actual TLS handshake confirm expiration.

### 7. Public management exposure should be narrowed

External checks found TCP 22 and TCP 6443 reachable on all three public node addresses. TCP 10250, 10257, 10259, and 8233 were not reachable. The repository configuration permits both SSH and the Kubernetes API from `0.0.0.0/0`.

SSH password authentication is disabled, root password login is disabled, fail2ban and AppArmor are active, and SSH keys are required. UFW is inactive, so the Hetzner firewall is the external enforcement layer.

Recommended action: close TCP 22 again after maintenance, and restrict both SSH and TCP 6443 to trusted administrator IP ranges or a VPN. The Kubernetes API still requires authentication, but universal network reachability unnecessarily exposes it to scanning and protocol-level vulnerabilities.

### 8. Backups and certificates are healthy but not resilient enough

K3s client/server certificates are currently valid; the shortest observed lifetime ends in March 2027. K3s rotates eligible certificates when it starts within the rotation window, so the planned maintenance reboots also help keep them managed.

Etcd snapshots are being created hourly, but the snapshots listed are stored only on the control-plane node under `/var/lib/rancher/k3s/server/db/snapshots`. With one control-plane server, losing that VM can lose both etcd and its local backups. Copy encrypted snapshots to independent object storage and test a restore procedure.

### 9. The local kubectl client is outside supported skew

The workstation client is `v1.33.9` while the API server is `v1.35.2`. Kubernetes supports kubectl within one minor version of the server; this two-minor gap produced a live warning. Upgrade the client to 1.35.x (or another supported adjacent version) before cluster maintenance.

## Recommended remediation sequence

1. Close port 22 again now that the audit is complete.
2. Fix or remove the expired preview wildcard certificate.
3. Apply the Flux NetworkPolicy containment and prepare the Flux upgrade to at least 2.9.4.
4. Upgrade K3s to 1.35.10, server first and then workers, following the K3s upgrade procedure.
5. Upgrade cert-manager to 1.21.3 and verify all production/test renewals.
6. Drain and reboot worker 1, verify it returns Ready, repeat for worker 2, then reboot the single control plane in a maintenance window.
7. Apply the remaining Ubuntu package updates and verify zero pending security updates on every node.
8. Restrict public SSH/API firewall ranges and add off-node etcd snapshots.
9. Plan ingress-nginx replacement; do not treat 1.15.1 as a long-term maintained endpoint.
10. Review updates for Hetzner CCM/CSI and scan application/controller images with an authenticated registry-aware vulnerability scanner.

After each stage, verify node readiness, pod distribution, Flux reconciliation, certificates, Ingress responses, and etcd snapshot creation.
