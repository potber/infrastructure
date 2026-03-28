hetzner_token: {{ .Env.HETZNER_TOKEN }}
cluster_name: cluster
kubeconfig_path: "./kubeconfig"
k3s_version: v1.35.2+k3s1

networking:
  ssh:
    port: 22
    use_agent: false
    use_private_ip: false
    public_key_path: "~/.ssh/id_hetzner_cluster.pub"
    private_key_path: "~/.ssh/id_hetzner_cluster"
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0

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
  instance_count: 3
  location: nbg1
