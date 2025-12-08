# Add a Node

This guide covers adding new control plane or worker nodes to the Talos cluster.

## Prerequisites

- Proxmox VM or bare metal server
- Talos ISO booted
- Network connectivity to existing cluster
- `talosctl` configured with cluster access

## Adding a Worker Node

### 1. Create the VM

In Proxmox, create a new VM:

| Setting | Value |
|---------|-------|
| CPU | 4+ cores |
| RAM | 8GB+ |
| Disk | 100GB+ |
| Network | VLAN 1 (172.16.1.0/24) |
| ISO | talos-v1.11.5-amd64.iso |

### 2. Update Nodes Configuration

Edit `nodes.yaml`:

```yaml
nodes:
  # ... existing nodes ...
  
  - hostname: talos-worker-2
    ipAddress: 172.16.1.54
    controlPlane: false
    installDiskSelector:
      size: ">= 100GB"
    networkInterfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - 172.16.1.54/24
        routes:
          - network: 0.0.0.0/0
            gateway: 172.16.1.1
```

### 3. Generate Machine Config

```bash
# Regenerate configs
task talos:generate

# Or manually with talhelper
talhelper genconfig
```

### 4. Apply Configuration

```bash
# Apply config to new node
talosctl apply-config \
  --nodes 172.16.1.54 \
  --file talos/clusterconfig/kubernetes-talos-worker-2.yaml \
  --insecure
```

### 5. Verify Node Joined

```bash
# Wait for node to appear
kubectl get nodes -w

# Check node status
talosctl -n 172.16.1.54 health
```

## Adding a Control Plane Node

### 1. Create the VM

Same as worker, but with:

| Setting | Value |
|---------|-------|
| CPU | 4 cores |
| RAM | 8GB |
| Disk | 100GB |

### 2. Update Nodes Configuration

Edit `nodes.yaml`:

```yaml
nodes:
  # ... existing nodes ...
  
  - hostname: talos-cp-4
    ipAddress: 172.16.1.55
    controlPlane: true
    installDiskSelector:
      size: ">= 100GB"
```

### 3. Generate and Apply

```bash
task talos:generate
talosctl apply-config \
  --nodes 172.16.1.55 \
  --file talos/clusterconfig/kubernetes-talos-cp-4.yaml \
  --insecure
```

### 4. Verify Etcd Membership

```bash
# Check etcd members
talosctl -n 172.16.1.50 etcd members

# Verify all control planes healthy
talosctl -n 172.16.1.50,172.16.1.51,172.16.1.52,172.16.1.55 health
```

## Post-Addition Steps

### Update Monitoring

If using kube-prometheus-stack, update the endpoints:

```yaml
kubeControllerManager:
  endpoints:
    - 172.16.1.50
    - 172.16.1.51
    - 172.16.1.52
    - 172.16.1.55  # new
```

### Update DNS Records (if needed)

Add new node to any relevant DNS records or monitoring configurations.

### Label the Node (optional)

```bash
# Add labels for scheduling
kubectl label node talos-worker-2 node-role.kubernetes.io/worker=true
kubectl label node talos-worker-2 topology.kubernetes.io/zone=rack-1
```

## Removing a Node

### Worker Node

```bash
# Drain the node
kubectl drain talos-worker-2 --ignore-daemonsets --delete-emptydir-data

# Delete from Kubernetes
kubectl delete node talos-worker-2

# Reset Talos (optional)
talosctl -n 172.16.1.54 reset --graceful=false
```

### Control Plane Node

```bash
# Remove from etcd first
talosctl -n 172.16.1.50 etcd remove-member talos-cp-4

# Then drain and delete
kubectl drain talos-cp-4 --ignore-daemonsets --delete-emptydir-data
kubectl delete node talos-cp-4

# Reset
talosctl -n 172.16.1.55 reset --graceful=false
```

## Troubleshooting

### Node Not Joining

1. Check network connectivity:
   ```bash
   talosctl -n <new-node-ip> dmesg | grep -i network
   ```

2. Verify config was applied:
   ```bash
   talosctl -n <new-node-ip> get machinestatus
   ```

3. Check kubelet logs:
   ```bash
   talosctl -n <new-node-ip> logs kubelet
   ```

### Etcd Issues (Control Plane)

1. Check etcd health:
   ```bash
   talosctl -n 172.16.1.50 etcd status
   ```

2. View etcd logs:
   ```bash
   talosctl -n <new-cp-ip> logs etcd
   ```
