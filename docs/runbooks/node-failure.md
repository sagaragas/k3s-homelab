# Runbook: Node Failure

## Symptoms

- Node shows `NotReady` in `kubectl get nodes`
- Pods on the node are `Pending` or `Unknown`
- Alerts firing for node down

## Quick Check

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Check Talos status
talosctl -n <node-ip> health
talosctl -n <node-ip> services
```

## Diagnosis

### 1. Network Connectivity

```bash
# Ping the node
ping <node-ip>

# Check from Proxmox
ssh root@<pve-host> "ping <node-ip>"
```

### 2. VM Status (if virtualized)

```bash
# Check VM status
ssh root@<pve-host> "qm status <vmid>"

# Check VM console
ssh root@<pve-host> "qm terminal <vmid>"
```

### 3. Talos Health

```bash
# Check all services
talosctl -n <node-ip> services

# Check specific service
talosctl -n <node-ip> service kubelet
talosctl -n <node-ip> service etcd  # control plane only

# Check logs
talosctl -n <node-ip> logs kubelet
```

## Recovery Procedures

### Scenario 1: VM Not Running

```bash
# Start the VM
ssh root@<pve-host> "qm start <vmid>"

# Wait for boot
sleep 60

# Verify
talosctl -n <node-ip> health
```

### Scenario 2: Talos Service Crashed

```bash
# Restart kubelet
talosctl -n <node-ip> service kubelet restart

# If etcd is unhealthy (control plane)
talosctl -n <node-ip> service etcd restart
```

### Scenario 3: Node Unresponsive

```bash
# Hard reset via Proxmox
ssh root@<pve-host> "qm reset <vmid>"

# Or stop and start
ssh root@<pve-host> "qm stop <vmid> && sleep 5 && qm start <vmid>"
```

### Scenario 4: etcd Quorum Loss

If 2+ control plane nodes are down:

```bash
# Check etcd status
talosctl -n 172.16.1.50 etcd members

# If quorum lost, need to recover from snapshot
talosctl -n <healthy-node> etcd snapshot db.snapshot
# Then restore following Talos docs
```

### Scenario 5: Node Needs Replacement

```bash
# Drain the node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Remove from cluster
kubectl delete node <node-name>

# If control plane, remove from etcd
talosctl -n <other-cp> etcd remove-member <node-id>

# Recreate VM and re-apply config
talosctl apply-config --nodes <new-ip> --file <config.yaml>
```

## Post-Recovery

1. Verify node is `Ready`:
   ```bash
   kubectl get nodes
   ```

2. Check pods rescheduled:
   ```bash
   kubectl get pods -A -o wide | grep <node-name>
   ```

3. Verify cluster health:
   ```bash
   talosctl -n 172.16.1.50 health
   kubectl get pods -n kube-system
   kubectl get --raw='/readyz?verbose' | head -50
   ```

## Prevention

- Enable HA for critical workloads
- Use PodDisruptionBudgets
- Regular etcd snapshots
- Monitor node health with Prometheus
