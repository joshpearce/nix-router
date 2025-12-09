# Transparent DNS Interception Options for nftables

This document outlines options for intercepting all outbound DNS traffic (port 53) and redirecting it through a local DNS server, transparently to clients.

## Feature Comparison

| Feature | DNAT | redirect | TPROXY | Policy-Based |
|---------|------|----------|--------|--------------|
| Redirect to local machine | Yes | Yes | Yes | Yes |
| Redirect to different host | **Yes** | No | No | **Yes** |
| See original destination IP | No | No | **Yes** | No |
| Per-device bypass | Manual | Manual | Manual | Built-in |
| Complexity | Low | **Lowest** | High | Medium |
| DNS server requirements | Listen on target IP | Listen on interface | IP_TRANSPARENT socket | Listen on target IP |
| Additional routing config | No | No | Yes (policy routing) | No |
| Works with IPv6 | Yes | Yes | Yes | Yes |
| One rule for all VLANs | Yes | **Yes** | Yes | Yes |

---

## Option 1: DNAT (Destination NAT)

Rewrites the destination IP of DNS packets to a specified address.

### Use Case
- Redirecting to a specific IP (local or remote host)
- When you need to send DNS to a different machine on the network

### nftables Implementation

```nft
table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;

    # Redirect to local DNS (use actual interface IP, not 127.0.0.1)
    iifname { "lan", "iot", "guest" } udp dport 53 dnat to 10.13.84.1:53
    iifname { "lan", "iot", "guest" } tcp dport 53 dnat to 10.13.84.1:53

    # Or redirect to a different host on the network
    # iifname { "lan", "iot", "guest" } udp dport 53 dnat to 10.13.84.100:53
  }
}
```

### Pros
- Can redirect to any IP address (local or remote)
- Well-documented, widely used technique
- Works with any standard DNS server

### Cons
- Cannot use 127.0.0.1 for traffic from other interfaces (use interface IP instead)
- DNS server must accept queries from redirected source IPs

### Limitations
- Original destination IP is not preserved (client wanted 8.8.8.8, server sees 10.13.84.1)

---

## Option 2: redirect (Local Socket Redirect)

A simplified DNAT that automatically redirects to the local machine.

### Use Case
- Simplest option when DNS server runs on the router itself
- When you don't need to redirect to a different host

### nftables Implementation

```nft
table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;

    # Redirect to same port on local machine
    iifname { "lan", "iot", "guest" } udp dport 53 redirect
    iifname { "lan", "iot", "guest" } tcp dport 53 redirect

    # Or redirect to a different local port
    # iifname { "lan", "iot", "guest" } udp dport 53 redirect to :5353
  }
}
```

### Pros
- Simplest syntax
- Automatically uses the correct local IP for each interface
- No need to specify destination IP

### Cons
- **Cannot redirect to a different host** - only works for local machine
- DNS server must listen on the interface(s) where packets arrive

### Limitations
- Local-only; if you need to send DNS to another server, use DNAT instead

---

## Option 3: TPROXY (Transparent Proxy)

Intercepts traffic while preserving the original destination IP for the DNS server to see.

### Use Case
- Logging which DNS servers clients are trying to reach
- Conditional forwarding based on original destination
- Advanced DNS filtering/inspection

### nftables Implementation

```nft
table ip filter {
  chain prerouting {
    type filter hook prerouting priority -150; policy accept;

    iifname { "lan", "iot", "guest" } udp dport 53 tproxy to :53 meta mark set 1
    iifname { "lan", "iot", "guest" } tcp dport 53 tproxy to :53 meta mark set 1
  }
}
```

### Additional Required Configuration

Policy routing to handle marked packets:

```bash
# Add routing rule for marked packets
ip rule add fwmark 1 lookup 100

# Route marked packets to local
ip route add local 0.0.0.0/0 dev lo table 100
```

For NixOS, add to networking config:

```nix
networking.iproute2.enable = true;
# Add custom routing rules via systemd or networking options
```

### Pros
- DNS server can see the original destination IP
- Enables logging of which DNS servers clients attempted to use
- Most "transparent" - full visibility into client intent

### Cons
- Complex setup with policy routing
- Requires DNS server with `IP_TRANSPARENT` socket option support
- Not all DNS servers support this (Unbound does, Pi-hole/dnsmasq may not)

### Limitations
- **Cannot redirect to a different host** - requires local transparent proxy
- Higher complexity for setup and debugging

---

## Option 4: Policy-Based (DNAT with Exemptions)

Combines DNAT with rules to allow specific devices to bypass the redirect.

### Use Case
- Most devices intercepted, but some servers need direct DNS access
- Hybrid environments where certain devices must use specific DNS

### nftables Implementation

```nft
table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;

    # Define bypass list
    define bypass_dns = { 10.13.84.100, 10.13.84.101 }

    # Allow bypass for specific IPs (process these first)
    ip saddr $bypass_dns udp dport 53 accept
    ip saddr $bypass_dns tcp dport 53 accept

    # Redirect everything else to local DNS
    iifname { "lan", "iot", "guest" } udp dport 53 dnat to 10.13.84.1:53
    iifname { "lan", "iot", "guest" } tcp dport 53 dnat to 10.13.84.1:53

    # Or redirect to a different host
    # iifname { "lan", "iot", "guest" } udp dport 53 dnat to 10.13.93.50:53
  }
}
```

### Pros
- Flexible per-device control
- Can redirect to local or remote DNS server
- Easy to add/remove bypass entries

### Cons
- More rules to maintain
- Bypass list needs updating when devices change

### Limitations
- Same as DNAT - original destination IP not preserved

---

## Additional Considerations

### DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT)

All these methods only capture traditional DNS on port 53. Encrypted DNS bypasses interception:

| Protocol | Port | Interception Difficulty |
|----------|------|------------------------|
| DNS (traditional) | 53 | Easy (this document) |
| DoT (DNS-over-TLS) | 853 | Medium - can block or redirect port 853 |
| DoH (DNS-over-HTTPS) | 443 | Hard - shares port with HTTPS traffic |

**Options for handling encrypted DNS:**

1. **Block DoT**: Drop outbound port 853
   ```nft
   chain forward {
     oifname "wan" tcp dport 853 drop
     oifname "wan" udp dport 853 drop
   }
   ```

2. **Block known DoH providers**: Use DNS-based blocklists for known DoH endpoints (dns.google, cloudflare-dns.com, etc.)

3. **Accept the limitation**: Some encrypted DNS will bypass; focus on devices that use traditional DNS

### IPv6

Current config drops all IPv6. If IPv6 is enabled later, add equivalent rules:

```nft
table ip6 nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    iifname { "lan", "iot", "guest" } udp dport 53 redirect
    iifname { "lan", "iot", "guest" } tcp dport 53 redirect
  }
}
```

### Local DNS Server Requirements

Depending on method chosen:

| Method | DNS Server Must... |
|--------|-------------------|
| DNAT | Listen on the target IP, accept queries from all source subnets |
| redirect | Listen on interface IPs (or 0.0.0.0), accept queries from all source subnets |
| TPROXY | Support `IP_TRANSPARENT` socket option |
| Policy-Based | Same as DNAT |

Common DNS servers and compatibility:

- **AdGuard Home**: Works with DNAT, redirect, Policy-Based
- **Pi-hole**: Works with DNAT, redirect, Policy-Based
- **Unbound**: Works with all methods including TPROXY
- **dnsmasq**: Works with DNAT, redirect, Policy-Based
- **dnsproxy**: Works with DNAT, redirect, Policy-Based

---

## Recommendation Summary

| If you need to... | Use |
|-------------------|-----|
| Simplest setup, local DNS | **redirect** |
| Send to a different host | **DNAT** |
| Bypass certain devices | **Policy-Based** |
| Log original destinations | **TPROXY** |

---

## Current Network Configuration

### VLAN Overview

| VLAN | Interface | Router IP | DHCP DNS Setting | dnsproxy Listening |
|------|-----------|-----------|------------------|-------------------|
| (default) | enp2s0 | 192.168.1.1 | 192.168.1.1 | Yes |
| lan | lan | 10.13.84.1 | 10.13.84.1 | Yes |
| iot | iot | 10.13.93.1 | 10.13.93.1 | Yes |
| k8s | k8s | 10.13.86.1 | 10.13.86.1 | Yes |
| guest | guest | 10.13.83.1 | 9.9.9.9 (external) | Yes |
| hazmat | hazmat | 10.13.99.1 | 9.9.9.9 (external) | Yes |

### Key Observations

1. **dnsproxy listens on all VLAN interfaces** - A single `redirect` rule works; no per-VLAN rules needed

2. **guest and hazmat use external DNS via DHCP** - These VLANs are told to use Quad9 (9.9.9.9) directly. Intercepting their DNS would change this behavior, routing them through local dnsproxy instead.

3. **dnsproxy upstream chain**: dnsproxy → Home Assistant (10.13.93.50:53) → fallback to Google DoH

### Do You Need Per-VLAN Rules?

**No.** Since dnsproxy listens on all interfaces, you can use a single rule:

```nft
iifname { "enp2s0", "lan", "iot", "k8s", "guest", "hazmat" } udp dport 53 redirect
```

The `redirect` action automatically uses the correct interface IP.

### Policy Consideration

If you want guest/hazmat to continue using external DNS (respecting their DHCP setting), exclude them:

```nft
# Only intercept VLANs that are supposed to use local DNS
iifname { "enp2s0", "lan", "iot", "k8s" } udp dport 53 redirect
iifname { "enp2s0", "lan", "iot", "k8s" } tcp dport 53 redirect
```

Or intercept everything (override DHCP setting, force all through local DNS):

```nft
# Force all VLANs through local DNS regardless of DHCP setting
iifname { "enp2s0", "lan", "iot", "k8s", "guest", "hazmat" } udp dport 53 redirect
iifname { "enp2s0", "lan", "iot", "k8s", "guest", "hazmat" } tcp dport 53 redirect
```

---

## Logging Redirects

To identify devices that ignore their DHCP-assigned DNS and try to use external resolvers, add logging to the redirect rules.

### Logging Architecture

DNS redirect logs use **NFLOG** (packet logging) to send logs through ulogd. This is separate from the existing **NFCT** (connection tracking) flow logs used for bandwidth monitoring.

| Log Type | Source | NFLOG Group | ulogd Stack | Purpose |
|----------|--------|-------------|-------------|---------|
| Flow logs (existing) | NFCT (conntrack) | N/A | `ct1:NFCT` | Bandwidth metrics |
| Packet logs (existing) | NFLOG | Group 1 | `log1:NFLOG` | Firewall audit |
| DNS redirect logs (new) | NFLOG | **Group 2** | `log2:NFLOG` (new) | DNS bypass detection |

**Important:** DNS redirect logs MUST use a different NFLOG group (group 2) than existing packet logs (group 1) to allow separate handling in ulogd and Vector. This protects the existing flow log pipeline in `vector.nix`.

### Log Only Non-Compliant Traffic

Use `ip daddr != { ... }` to exclude traffic already destined for the router. This avoids log noise from compliant clients:

```nft
chain prerouting {
  type nat hook prerouting priority -100; policy accept;

  # Define router DNS IPs (traffic to these doesn't need redirect)
  define router_dns = { 192.168.1.1, 10.13.84.1, 10.13.93.1, 10.13.86.1 }

  # Log and redirect DNS going to external servers
  # Uses NFLOG group 2 to keep separate from existing packet logs (group 1)
  iifname { "enp2s0", "lan", "iot", "k8s" } udp dport 53 ip daddr != $router_dns log group 2 prefix "DNS-REDIRECT: " redirect
  iifname { "enp2s0", "lan", "iot", "k8s" } tcp dport 53 ip daddr != $router_dns log group 2 prefix "DNS-REDIRECT: " redirect
}
```

### ulogd Configuration Update

Add a new stack in `ulogd.nix` for NFLOG group 2:

```nix
# In settings.global.stack, add:
"log2:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,syslog1:SYSLOG"

# Add new section:
log2 = {
  group = 2;
};
```

### Vector Configuration Update

The existing `vector.nix` pipeline expects NFCT flow format (`[DESTROY] ORIG:... REPLY:...`). DNS redirect logs have a different format and will cause parsing errors if processed by `prep_for_metric`.

**Option A: Filter by prefix (recommended for incremental approach)**

Add a filter in Vector to route DNS-REDIRECT messages separately:

```nix
# Add before prep_for_metric transform
filter_dns_redirect = {
  type = "filter";
  inputs = [ "journald" ];
  condition = ''!starts_with!(.message, "DNS-REDIRECT:")'';
};

# Update prep_for_metric to use filtered input
prep_for_metric = {
  # ...
  inputs = [ "filter_dns_redirect" ];  # Changed from "journald"
};

# Optionally add a separate sink for DNS redirect logs
dns_redirect_logs = {
  type = "filter";
  inputs = [ "journald" ];
  condition = ''starts_with(.message, "DNS-REDIRECT:")'';
};
```

**Option B: Separate ulogd syslog facility**

Use a different syslog facility for DNS logs in ulogd, then filter in Vector by facility.

### What Gets Logged

Only DNS queries to external servers (e.g., 8.8.8.8, 1.1.1.1) are logged. Traffic already going to router IPs passes through silently.

### Example Log Entry

```
DNS-REDIRECT: IN=iot OUT= MAC=... SRC=10.13.93.50 DST=8.8.8.8 LEN=... PROTO=UDP DPT=53
```

This tells you:
- **IN=iot**: Packet came from the iot VLAN
- **SRC=10.13.93.50**: Device IP that tried to bypass local DNS
- **DST=8.8.8.8**: External DNS server the device tried to reach

### Viewing Logs

```bash
# Live tail of DNS redirect logs (via ulogd/journald)
journalctl -u ulogd -f | grep "DNS-REDIRECT"
```

### Log Rate Limiting (Optional)

To prevent log flooding from chatty devices, add rate limiting:

```nft
iifname { "enp2s0", "lan", "iot", "k8s" } udp dport 53 ip daddr != $router_dns limit rate 10/minute log group 2 prefix "DNS-REDIRECT: " redirect
```

This logs at most 10 matching packets per minute per rule, while still redirecting all traffic.
