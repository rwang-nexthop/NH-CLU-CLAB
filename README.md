# Nexthop.AI SONiC CLOS Topology Lab

A containerlab-based SONiC CLOS topology with 2 spines and 2 leaves, featuring BGP routing and streaming telemetry.

📋 **See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for command reference**

## 🏗️ Topology Overview

```
                        ┌─────────┐   ┌─────────┐
                        │ spine1  │   │ spine2  │
                        │ AS65000 │   │ AS65000 │
                        └────┬────┘   └────┬────┘   
                             |   \        /|
                             |    \      / |
                             |     \    /  |
                             |      \  /   |                                  
                             |      / \    |
                             |    /    \   |
                             |   /      \  |
                             | /         \ |
                             |/            \
                           / |             |\ 
                          ┌───┴───┐ ┌┴───---┐
                          │ leaf1 │ │ leaf2 │
                          │AS65101│ │AS65102│
                          └───────┘ └───┬───┘
                              │         │
                          ┌───┴───┐ ┌───┴───┐
                          │ host1 │ │ host2 │
                          │.1.10  │ │.2.10  │
                          └───────┘ └───────┘
```

## 📋 Network Details

### IP Addressing Scheme

**Spine-Leaf Links:**
- spine1 ↔ leaf1: 10.0.1.0/31 (spine1: .0, leaf1: .1)
- spine1 ↔ leaf2: 10.0.2.0/31 (spine1: .0, leaf2: .1)
- spine2 ↔ leaf1: 10.0.1.2/31 (spine2: .2, leaf1: .3)
- spine2 ↔ leaf2: 10.0.2.2/31 (spine2: .2, leaf2: .3)

**Loopback Addresses:**
- spine1: 1.1.1.1/32
- spine2: 2.2.2.2/32
- leaf1: 11.11.11.11/32
- leaf2: 22.22.22.22/32

**Host Networks:**
- host1: 192.168.1.10/24 (gateway: 192.168.1.1 on leaf1)
- host2: 192.168.2.10/24 (gateway: 192.168.2.1 on leaf2)

### BGP Configuration

**AS Numbers:**
- Spines: AS 65000 (both spine1 and spine2)
- leaf1: AS 65101
- leaf2: AS 65102

**BGP Design:**
- eBGP between spines and leaves
- Each leaf peers with both spines for redundancy
- Route redistribution configured via script

## 🚀 Getting Started

### Prerequisites

1. **Docker Desktop** installed on macOS
2. **VS Code** with Remote-Containers extension
3. **Containerlab** (VSCode extension)
4. **DevContainer** (VSCode extension)

### Option 1: Using VS Code Devcontainer (Recommended for Mac)

1. Open the `NH-CLU-CLAB` folder in VS Code
2. When prompted, click "Reopen in Container"
3. Wait for the devcontainer to build and start
4. Open a terminal in VS Code

### Option 2: Local Installation

If you have containerlab installed locally:

```bash
cd ~/Python/Projects/NH-CLU-CLAB
```

## 📦 Deployment

#### 1. Deploy the Lab

```bash
cd topology
clab deploy -t sonic-clos.clab.yml
```

#### 2. Configure Interfaces and BGP

```bash
cd ../scripts
./configure_bgp_docker.sh
```

The configuration script will:
1. Bring up all containerlab eth interfaces
2. Fix host default routes (remove mgmt network routes)
3. Configure all interface IP addresses and loopbacks
4. Enable the BGP daemon (bgpd) on all containers
5. Configure BGP neighbors and route redistribution
6. Verify BGP sessions are established
7. Test end-to-end connectivity between hosts

**Note:** All scripts use `docker exec` and require no additional dependencies.

## 🔍 Verification

### Check BGP Status

Connect to a SONiC device:

```bash
docker exec -it clab-sonic-clos-spine1 bash
```

Inside the container:

```bash
# View BGP summary
vtysh -c "show ip bgp summary"

# View BGP routes
vtysh -c "show ip bgp"

# View routing table
vtysh -c "show ip route"
```

### Test Connectivity

From host1 to host2:

```bash
docker exec -it clab-sonic-clos-host1 ping 192.168.2.10
```

## 🗂️ Directory Structure

```
NH-CLU-CLAB/
├── .devcontainer/
│   └── devcontainer.json          # VS Code devcontainer config
├── configs/
│   ├── spine1/
│   │   └── config_db.json         # spine1 SONiC configuration
│   ├── spine2/
│   │   └── config_db.json         # spine2 SONiC configuration
│   ├── leaf1/
│   │   └── config_db.json         # leaf1 SONiC configuration
│   └── leaf2/
│       └── config_db.json         # leaf2 SONiC configuration
├── scripts/
│   └── configure_bgp_redistribute.sh  # BGP configuration script
├── topology/
│   └── sonic-clos.clab.yml        # Containerlab topology file
└── README.md                      # This file
```

## 🛠️ Troubleshooting

### SONiC Containers Not Starting

If using sonic-vs containers, ensure you have the SONiC virtual switch image:

```bash
docker pull docker-sonic-vs:latest
```

Or build it from the SONiC repository.

### BGP Not Establishing

The configuration script now automatically handles common issues:
- Brings up eth interfaces (containerlab links)
- Fixes host default routes
- Enables BGP daemon

If BGP still doesn't establish:

1. Check interface status:
   ```bash
   docker exec clab-sonic-clos-spine1 vtysh -c "show interface brief"
   ```

2. Check BGP neighbors:
   ```bash
   docker exec clab-sonic-clos-spine1 vtysh -c "show ip bgp neighbors"
   ```

3. Verify IP addressing matches the topology

4. Re-run the configuration script:
   ```bash
   cd scripts
   ./configure_bgp_docker.sh
   ```

### Host Connectivity Issues

If hosts can't ping each other:

1. Check host routes:
   ```bash
   docker exec clab-sonic-clos-host1 ip route
   ```

2. Verify default route points to data network (192.168.x.1), not mgmt (172.20.20.1)

3. The configuration script automatically fixes this, but you can manually fix:
   ```bash
   docker exec clab-sonic-clos-host1 ip route del default via 172.20.20.1 dev eth0
   docker exec clab-sonic-clos-host1 ip route add default via 192.168.1.1 dev eth1
   ```

## 🧹 Cleanup

### Quick Cleanup (Automated)

```bash
cd scripts
./cleanup_lab.sh
```

This script will:
- Destroy the containerlab topology
- Remove orphaned containers and networks
- Clean up lab artifacts and SSH configs
- Verify complete cleanup

### Manual Cleanup

```bash
cd topology
clab destroy -t sonic-clos.clab.yml --cleanup
```

## 📚 References

- [Containerlab Documentation](https://containerlab.dev/)
- [SONiC Documentation](https://github.com/sonic-net/SONiC/wiki)

## 📝 License

This project is for educational and testing purposes provided by Nexthop.AI.

