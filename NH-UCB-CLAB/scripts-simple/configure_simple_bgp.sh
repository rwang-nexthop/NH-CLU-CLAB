#!/usr/bin/env bash

# Script to configure Simple SONiC topology
# Configures interfaces, IP addresses, loopbacks, and BGP

set -e  # Exit on error

# Container names and their AS numbers
declare -A CONTAINERS
CONTAINERS["clab-simple-sonic-sonic1"]="65001"
CONTAINERS["clab-simple-sonic-sonic2"]="65002"

# Function to bring up eth interfaces (containerlab links)
bring_up_eth_interfaces() {
    echo "Bringing up eth interfaces on all devices..."

    # SONiC switches
    docker exec clab-simple-sonic-sonic1 ip link set eth1 up
    docker exec clab-simple-sonic-sonic1 ip link set eth2 up

    docker exec clab-simple-sonic-sonic2 ip link set eth1 up
    docker exec clab-simple-sonic-sonic2 ip link set eth2 up

    sleep 2
    echo "✓ All eth interfaces are up"
}

# Function to fix host default routes
fix_host_routes() {
    echo "Fixing host default routes..."
    
    # Remove management network default routes and add proper defaults
    docker exec clab-simple-sonic-host1 sh -c "ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true"
    docker exec clab-simple-sonic-host1 sh -c "ip route add default via 192.168.1.1 dev eth1 2>/dev/null || true"
    
    docker exec clab-simple-sonic-host2 sh -c "ip route del default via 172.20.20.1 dev eth0 2>/dev/null || true"
    docker exec clab-simple-sonic-host2 sh -c "ip route add default via 192.168.2.1 dev eth1 2>/dev/null || true"
    
    echo "✓ Host routes configured"
}

# Function to configure interfaces on sonic1
configure_sonic1_interfaces() {
    local container="clab-simple-sonic-sonic1"
    echo "Configuring interfaces on sonic1..."

    # Configure inter-switch link (eth1 -> Ethernet0)
    docker exec $container config interface ip add Ethernet0 10.0.0.0/31
    docker exec $container config interface startup Ethernet0

    # Configure host1 link (eth2 -> Ethernet4)
    docker exec $container config interface ip add Ethernet4 192.168.1.1/24
    docker exec $container config interface startup Ethernet4

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 1.1.1.1/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on sonic1"
}

# Function to configure interfaces on sonic2
configure_sonic2_interfaces() {
    local container="clab-simple-sonic-sonic2"
    echo "Configuring interfaces on sonic2..."

    # Configure inter-switch link (eth1 -> Ethernet0)
    docker exec $container config interface ip add Ethernet0 10.0.0.1/31
    docker exec $container config interface startup Ethernet0

    # Configure host2 link (eth2 -> Ethernet4)
    docker exec $container config interface ip add Ethernet4 192.168.2.1/24
    docker exec $container config interface startup Ethernet4

    # Configure Loopback0
    docker exec $container config loopback add Loopback0
    docker exec $container config interface ip add Loopback0 2.2.2.2/32
    docker exec $container config interface startup Loopback0

    echo "✓ Interfaces configured on sonic2"
}

# Function to enable bgpd daemon
enable_bgpd() {
    local container_name=$1
    echo "Enabling bgpd in $container_name..."

    docker exec $container_name sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
    docker exec $container_name service frr restart
    sleep 3
}

# Function to configure BGP on sonic1
configure_sonic1_bgp() {
    local container_name="clab-simple-sonic-sonic1"
    local asn="65001"

    echo "Configuring BGP on sonic1 (AS $asn)..."

    docker exec $container_name vtysh -c "configure terminal" \
        -c "router bgp $asn" \
        -c "bgp router-id 1.1.1.1" \
        -c "bgp log-neighbor-changes" \
        -c "no bgp ebgp-requires-policy" \
        -c "neighbor 10.0.0.1 remote-as 65002" \
        -c "address-family ipv4 unicast" \
        -c "network 192.168.1.0/24" \
        -c "redistribute connected" \
        -c "exit-address-family" \
        -c "exit" 2>&1 | grep -v "Unknown command" || true

    # Save configuration
    docker exec $container_name vtysh -c "write memory" 2>/dev/null || \
    docker exec $container_name vtysh -c "write" 2>/dev/null || true

    echo "✓ Successfully configured sonic1"
}

# Function to configure BGP on sonic2
configure_sonic2_bgp() {
    local container_name="clab-simple-sonic-sonic2"
    local asn="65002"

    echo "Configuring BGP on sonic2 (AS $asn)..."

    docker exec $container_name vtysh -c "configure terminal" \
        -c "router bgp $asn" \
        -c "bgp router-id 2.2.2.2" \
        -c "bgp log-neighbor-changes" \
        -c "no bgp ebgp-requires-policy" \
        -c "neighbor 10.0.0.0 remote-as 65001" \
        -c "address-family ipv4 unicast" \
        -c "network 192.168.2.0/24" \
        -c "redistribute connected" \
        -c "exit-address-family" \
        -c "exit" 2>&1 | grep -v "Unknown command" || true

    # Save configuration
    docker exec $container_name vtysh -c "write memory" 2>/dev/null || \
    docker exec $container_name vtysh -c "write" 2>/dev/null || true

    echo "✓ Successfully configured sonic2"
}

# Main script
echo "=========================================="
echo "Simple SONiC Lab - Complete Configuration"
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

# Step 1: Configure interfaces
echo "Step 1: Configuring interfaces..."
echo "----------------------------------"
configure_sonic1_interfaces
configure_sonic2_interfaces
echo ""

# Step 2: Wait for interfaces to stabilize
echo "Step 2: Waiting for interfaces to stabilize..."
echo "-----------------------------------------------"
sleep 5
echo "✓ Interfaces stabilized"
echo ""

# Step 3: Enable bgpd on all containers
echo "Step 3: Enabling bgpd daemon on all containers..."
echo "--------------------------------------------------"
for container in "${!CONTAINERS[@]}"; do
    enable_bgpd "$container"
done
echo ""

# Step 4: Configure BGP
echo "Step 4: Configuring BGP on routers..."
echo "--------------------------------------"
configure_sonic1_bgp
configure_sonic2_bgp
echo ""

# Step 5: Wait for BGP to establish
echo "Step 5: Waiting for BGP sessions to establish..."
echo "-------------------------------------------------"
echo "Waiting 30 seconds..."
sleep 30

# Step 6: Verify BGP status
echo ""
echo "Step 6: Verifying BGP configuration..."
echo "---------------------------------------"
for container in "${!CONTAINERS[@]}"; do
    echo "=== $container BGP Summary ==="
    docker exec $container vtysh -c "show ip bgp summary"
    echo ""
done

# Step 7: Test connectivity
echo "Step 7: Testing connectivity..."
echo "--------------------------------"
echo "Testing host1 -> host2 (via 192.168.2.10)..."
docker exec clab-simple-sonic-host1 ping -c 3 192.168.2.10 && echo "✓ host1 -> host2 SUCCESS" || echo "✗ host1 -> host2 FAILED"
echo ""
echo "Testing host2 -> host1 (via 192.168.1.10)..."
docker exec clab-simple-sonic-host2 ping -c 3 192.168.1.10 && echo "✓ host2 -> host1 SUCCESS" || echo "✗ host2 -> host1 FAILED"
echo ""

echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "Verification commands:"
echo "  - Check BGP neighbors: docker exec <container> vtysh -c 'show ip bgp summary'"
echo "  - Check BGP routes:    docker exec <container> vtysh -c 'show ip bgp'"
echo "  - Check routing table: docker exec <container> vtysh -c 'show ip route'"
echo "  - Test connectivity:   docker exec clab-simple-sonic-host1 ping 192.168.2.10"
echo ""

