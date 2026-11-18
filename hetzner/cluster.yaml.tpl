hetzner_token: {{ .Env.HETZNER_TOKEN }}
cluster_name: cluster
kubeconfig_path: "./kubeconfig"
k3s_version: v1.35.2+k3s1

networking:
  ssh:
    port: 22
    use_agent: false
    # Administrative access uses the Tailscale subnet route via cluster-master1.
    # Tailscale must be connected before running hetzner-k3s commands.
    use_private_ip: true
    public_key_path: "~/.ssh/id_hetzner_cluster.pub"
    private_key_path: "~/.ssh/id_hetzner_cluster"
  allowed_networks:
    # Public management access is closed. Keep cluster administration on the
    # Hetzner private network reached through Tailscale.
    ssh:
      - 10.0.0.0/16
    api:
      - 10.0.0.0/16

addons:
  metrics_server:
    enabled: true
  cluster_autoscaler:
    enabled: false

masters_pool:
  instance_type: cx23
  instance_count: 1
  locations:
    - nbg1

worker_node_pools:
- name: workers
  instance_type: cx23
  instance_count: 2
  location: nbg1
