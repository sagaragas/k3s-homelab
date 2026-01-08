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

### 2. Copy machine config from an existing worker

This cluster is managed manually (not via talhelper-generated configs). The simplest pattern is to copy the machine config from an existing worker and edit it for the new node.

```bash
# Export an existing worker machine config
talosctl -n 172.16.1.53 get machineconfig -o jsonpath='{.spec}' > /tmp/new-worker.yaml

# Edit /tmp/new-worker.yaml: hostname, IP, MAC address
# (use your editor of choice)
```

### 3. Apply configuration to the new node

Boot the new VM from the Talos ISO (maintenance mode), then apply the config using the node's current (DHCP) IP:

```bash
talosctl apply-config --insecure --nodes <new-node-ip> --file /tmp/new-worker.yaml
```

### 4. Verify Node Joined

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

### 2. Copy machine config from an existing control plane

```bash
talosctl -n 172.16.1.50 get machineconfig -o jsonpath='{.spec}' > /tmp/new-controlplane.yaml

# Edit /tmp/new-controlplane.yaml: hostname, IP, MAC address
```

### 3. Apply configuration to the new control plane

```bash
talosctl apply-config --insecure --nodes <new-node-ip> --file /tmp/new-controlplane.yaml
```

### 4. Verify Etcd Membership

```bash
# Check etcd members
talosctl -n 172.16.1.50 etcd members

# Verify all control planes healthy
talosctl -n 172.16.1.50,172.16.1.51,172.16.1.52,<new-cp-ip> health
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
kubectl label node <node-name> node-role.kubernetes.io/worker=true
kubectl label node <node-name> topology.kubernetes.io/zone=rack-1
```

## Removing a Node

### Worker Node

```bash
# Drain the node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Delete from Kubernetes
kubectl delete node <node-name>

# Reset Talos (optional)
talosctl -n <node-ip> reset --graceful=false
```

### Control Plane Node

```bash
# Remove from etcd first
talosctl -n 172.16.1.50 etcd remove-member <cp-node-name>

# Then drain and delete
kubectl drain <cp-node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <cp-node-name>

# Reset
talosctl -n <node-ip> reset --graceful=false
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
