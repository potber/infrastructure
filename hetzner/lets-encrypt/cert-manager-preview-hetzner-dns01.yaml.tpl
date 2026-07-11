apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-preview-hetzner-dns01
spec:
  acme:
    email: {{ .Env.CLUSTER_ADMIN_EMAIL }}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-preview-hetzner-dns01-account-key
    solvers:
      - dns01:
          webhook:
            groupName: acme.hetzner.com
            solverName: hetzner
            config:
              tokenSecretKeyRef:
                name: hetzner-dns-api-token-secret
                key: token
