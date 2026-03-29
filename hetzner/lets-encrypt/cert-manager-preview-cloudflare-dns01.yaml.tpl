apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-preview-cloudflare-dns01
spec:
  acme:
    email: {{ .Env.CLUSTER_ADMIN_EMAIL }}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-preview-cloudflare-dns01-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-preview-api-token-secret
              key: api-token
