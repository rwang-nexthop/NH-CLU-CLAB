#!/usr/bin/env bash

# Script to configure Nexthop.AI SONiC containers from scratch
# Configures interfaces, IP addresses, loopbacks, and BGP

set -e  # Exit on error

# Container names and their AS numbers
declare -A CONTAINERS
CONTAINERS["clab-nexthop-sonic-clos-spine1"]="65000"
CONTAINERS["clab-nexthop-sonic-clos-spine2"]="65000"
CONTAINERS["clab-nexthop-sonic-clos-leaf1"]="65101"
CONTAINERS["clab-nexthop-sonic-clos-leaf2"]="65102"

# Function to fix host default routes
fix_host_routes() {
    echo "Fixing host default routes..."

    # Host1: Remove mgmt route, add data network route
    docker exec clab-nexthop-sonic-clos-host1 ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true
    docker exec clab-nexthop-sonic-clos-host1 ip route add default via 192.168.1.1 dev eth1 2>/dev/null || true

    # Host2: Remove mgmt route, add data network route
    docker exec clab-nexthop-sonic-clos-host2 ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true
    docker exec clab-nexthop-sonic-clos-host2 ip route add default via 192.168.2.1 dev eth1 2>/dev/null || true

    echo "✓ Host routes configured"
}

# Function to bring up eth interfaces (containerlab links)
bring_up_eth_interfaces() {
    echo "Bringing up eth interfaces on all devices..."

    # Spine switches (eth1, eth2)
    docker exec clab-nexthop-sonic-clos-spine1 ip link set eth1 up
    docker exec clab-nexthop-sonic-clos-spine1 ip link set eth2 up
    docker exec clab-nexthop-sonic-clos-spine2 ip link set eth1 up
    docker exec clab-nexthop-sonic-clos-spine2 ip link set eth2 up

    # Leaf switches (eth1, eth2, eth3)
    docker exec clab-nexthop-sonic-clos-leaf1 ip link set eth1 up
    docker exec clab-nexthop-sonic-clos-leaf1 ip link set eth2 up
    docker exec clab-nexthop-sonic-clos-leaf1 ip link set eth3 up
    docker exec clab-nexthop-sonic-clos-leaf2 ip link set eth1 up
    docker exec clab-nexthop-sonic-clos-leaf2 ip link set eth2 up
    docker exec clab-nexthop-sonic-clos-leaf2 ip link set eth3 up

    echo "✓ All eth interfaces are up"
    sleep 2
}

# Function to configure interfaces on spine1
configure_spine1_interfaces() {
    local container="clab-nexthop-sonic-clos-spine1"
    echo "Configuring interfaces on spine1..."

    # Configure Ethernet0 (to leaf1)
    docker exec $container config interface ip add Ethernet0 10.0.1.0/31
    docker exec $container config interface startup Ethernet0

    # Configure Ethernet4 (to leaf2)
    docker exec $container config interface ip add Ethernet4 10.0.2.0/31
    docker exec $container config interface startup Ethernet4

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 1.1.1.1/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on spine1"
}

# Function to configure interfaces on spine2
configure_spine2_interfaces() {
    local container="clab-nexthop-sonic-clos-spine2"
    echo "Configuring interfaces on spine2..."

    # Configure Ethernet0 (to leaf1)
    docker exec $container config interface ip add Ethernet0 10.0.1.2/31
    docker exec $container config interface startup Ethernet0

    # Configure Ethernet4 (to leaf2)
    docker exec $container config interface ip add Ethernet4 10.0.2.2/31
    docker exec $container config interface startup Ethernet4

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 2.2.2.2/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on spine2"
}

# Function to configure interfaces on leaf1
configure_leaf1_interfaces() {
    local container="clab-nexthop-sonic-clos-leaf1"
    echo "Configuring interfaces on leaf1..."

    # Configure Ethernet0 (to spine1)
    docker exec $container config interface ip add Ethernet0 10.0.1.1/31
    docker exec $container config interface startup Ethernet0

    # Configure Ethernet4 (to spine2)
    docker exec $container config interface ip add Ethernet4 10.0.1.3/31
    docker exec $container config interface startup Ethernet4

    # Configure Ethernet8 (to host1)
    docker exec $container config interface ip add Ethernet8 192.168.1.1/24
    docker exec $container config interface startup Ethernet8

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 11.11.11.11/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on leaf1"
}

# Function to configure interfaces on leaf2
configure_leaf2_interfaces() {
    local container="clab-nexthop-sonic-clos-leaf2"
    echo "Configuring interfaces on leaf2..."

    # Configure Ethernet0 (to spine1)
    docker exec $container config interface ip add Ethernet0 10.0.2.1/31
    docker exec $container config interface startup Ethernet0

    # Configure Ethernet4 (to spine2)
    docker exec $container config interface ip add Ethernet4 10.0.2.3/31
    docker exec $container config interface startup Ethernet4

    # Configure Ethernet8 (to host2)
    docker exec $container config interface ip add Ethernet8 192.168.2.1/24
    docker exec $container config interface startup Ethernet8

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 22.22.22.22/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on leaf2"
}

# Function to enable bgpd daemon
enable_bgpd() {
    local container_name=$1
    echo "Enabling bgpd in $container_name..."

    docker exec $container_name sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
    docker exec $container_name service frr restart
    sleep 3
}

# Function to configure BGP on spine
configure_spine_bgp() {
    local container_name=$1
    local asn=$2
    local router_id=""
    local neighbor1=""
    local neighbor2=""

    if [ "$container_name" == "clab-nexthop-sonic-clos-spine1" ]; then
        router_id="1.1.1.1"
        neighbor1="10.0.1.1"  # leaf1
        neighbor2="10.0.2.1"  # leaf2
    else
        router_id="2.2.2.2"
        neighbor1="10.0.1.3"  # leaf1
        neighbor2="10.0.2.3"  # leaf2
    fi

    echo "Configuring BGP on $container_name (AS $asn)..."

    docker exec $container_name vtysh -c "configure terminal" \
        -c "router bgp $asn" \
        -c "bgp router-id $router_id" \
        -c "bgp log-neighbor-changes" \
        -c "no bgp ebgp-requires-policy" \
        -c "neighbor $neighbor1 remote-as 65101" \
        -c "neighbor $neighbor2 remote-as 65102" \
        -c "address-family ipv4 unicast" \
        -c "neighbor $neighbor1 activate" \
        -c "neighbor $neighbor2 activate" \
        -c "redistribute connected" \
        -c "exit-address-family" \
        -c "exit" 2>&1 | grep -v "Unknown command" || true

    # Save configuration (try both commands)
    docker exec $container_name vtysh -c "write memory" 2>/dev/null || \
    docker exec $container_name vtysh -c "write" 2>/dev/null || true

    echo "✓ Successfully configured $container_name"
}

# Function to configure BGP on leaf
configure_leaf_bgp() {
    local container_name=$1
    local asn=$2
    local router_id=""
    local neighbor1=""
    local neighbor2=""
    local network=""

    if [ "$container_name" == "clab-nexthop-sonic-clos-leaf1" ]; then
        router_id="11.11.11.11"
        neighbor1="10.0.1.0"  # spine1
        neighbor2="10.0.1.2"  # spine2
        network="192.168.1.0/24"
    else
        router_id="22.22.22.22"
        neighbor1="10.0.2.0"  # spine1
        neighbor2="10.0.2.2"  # spine2
        network="192.168.2.0/24"
    fi

    echo "Configuring BGP on $container_name (AS $asn)..."

    docker exec $container_name vtysh -c "configure terminal" \
        -c "router bgp $asn" \
        -c "bgp router-id $router_id" \
        -c "bgp log-neighbor-changes" \
        -c "no bgp ebgp-requires-policy" \
        -c "neighbor $neighbor1 remote-as 65000" \
        -c "neighbor $neighbor2 remote-as 65000" \
        -c "address-family ipv4 unicast" \
        -c "network $network" \
        -c "neighbor $neighbor1 activate" \
        -c "neighbor $neighbor2 activate" \
        -c "redistribute connected" \
        -c "exit-address-family" \
        -c "exit" 2>&1 | grep -v "Unknown command" || true

    # Save configuration (try both commands)
    docker exec $container_name vtysh -c "write memory" 2>/dev/null || \
    docker exec $container_name vtysh -c "write" 2>/dev/null || true

    echo "✓ Successfully configured $container_name"
}

# Main script
echo "=========================================="
echo "SONiC CLOS Lab - Complete Configuration"
echo "=========================================="
echo ""

# Step 0: Bring up eth interfaces
echo "Step 0: Bringing up containerlab eth interfaces..."
echo "---------------------------------------------------"
bring_up_eth_interfaces
echo ""

# Step 0.5: Fix host default routes
echo "Step 0.5: Configuring host routes..."
echo "-------------------------------------"
fix_host_routes
echo ""

# Step 1: Configure interfaces and IP addresses
echo "Step 1: Configuring interfaces and IP addresses..."
echo "---------------------------------------------------"
configure_spine1_interfaces
configure_spine2_interfaces
configure_leaf1_interfaces
configure_leaf2_interfaces
echo ""
sleep 5

# Step 2: Verify interface configuration
echo "Step 2: Verifying interface configuration..."
echo "---------------------------------------------"
for container in "${!CONTAINERS[@]}"; do
    echo "=== $container interfaces ==="
    docker exec $container show ip interface brief 2>/dev/null || docker exec $container ip addr show | grep -E "inet |^[0-9]"
    echo ""
done
sleep 2

# Step 3: Enable bgpd on all containers
echo "Step 3: Enabling bgpd daemon on all containers..."
echo "--------------------------------------------------"
for container in "${!CONTAINERS[@]}"; do
    enable_bgpd "$container"
done
echo ""

# Step 4: Configure BGP on spines
echo "Step 4: Configuring BGP on spine routers..."
echo "--------------------------------------------"
configure_spine_bgp "clab-nexthop-sonic-clos-spine1" "65000"
configure_spine_bgp "clab-nexthop-sonic-clos-spine2" "65000"
echo ""

# Step 5: Configure BGP on leaves
echo "Step 5: Configuring BGP on leaf routers..."
echo "-------------------------------------------"
configure_leaf_bgp "clab-nexthop-sonic-clos-leaf1" "65101"
configure_leaf_bgp "clab-nexthop-sonic-clos-leaf2" "65102"
echo ""

# Step 6: Wait for BGP to establish
echo "Step 6: Waiting for BGP sessions to establish..."
echo "-------------------------------------------------"
echo "Waiting 30 seconds..."
sleep 30

# Step 7: Verify BGP status
echo ""
echo "Step 7: Verifying BGP configuration..."
echo "---------------------------------------"
for container in "${!CONTAINERS[@]}"; do
    echo "=== $container BGP Summary ==="
    docker exec $container vtysh -c "show ip bgp summary"
    echo ""
done

# Step 8: Check connectivity
echo "Step 8: Testing connectivity..."
echo "--------------------------------"
echo "Testing host1 -> host2 connectivity..."
docker exec clab-nexthop-sonic-clos-host1 ping -c 3 192.168.2.10
echo ""
echo "Testing host2 -> host1 connectivity..."
docker exec clab-nexthop-sonic-clos-host2 ping -c 3 192.168.1.10
echo ""

echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "Verification commands:"
echo "  - Check BGP neighbors: docker exec <container> vtysh -c 'show ip bgp summary'"
echo "  - Check BGP routes:    docker exec <container> vtysh -c 'show ip bgp'"
echo "  - Check routing table: docker exec <container> vtysh -c 'show ip route'"
echo "  - Test connectivity:   docker exec clab-nexthop-sonic-clos-host1 ping 192.168.2.10"
echo ""
echo "Troubleshooting:"
echo "  - Check interfaces:    docker exec <container> show ip interface"
echo "  - Check FRR status:    docker exec <container> service frr status"
echo "  - Enter vtysh:         docker exec -it <container> vtysh"
echo ""
echo "Powered by Nexthop.AI"
echo ""

