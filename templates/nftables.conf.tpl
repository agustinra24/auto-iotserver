#!/usr/sbin/nft -f

flush ruleset

define SSH_PORT = {{SSH_PORT}}
define HTTP_PORT = 80
define HTTPS_PORT = 443

table inet filter {
    # Dynamic IP sets for fail2ban and rate limiting
    set fail2ban_blacklist {
        type ipv4_addr
        flags dynamic, timeout
        size 65536
        timeout 1h
    }
    
    set rate_limit_ssh {
        type ipv4_addr
        flags dynamic, timeout
        size 65536
        timeout 60s
    }
    
    set rate_limit_api_auth {
        type ipv4_addr
        flags dynamic, timeout
        size 65536
        timeout 300s
    }
    
    chain input {
        type filter hook input priority filter; policy drop;
        
        # Allow loopback
        iif lo accept
        
        # Allow established/related connections
        ct state established,related accept
        
        # Drop invalid packets
        ct state invalid drop
        
        # Fail2Ban blacklist (highest priority)
        ip saddr @fail2ban_blacklist drop
        
        # SSH with rate limiting (3 connections per minute per IP)
        tcp dport $SSH_PORT ct state new \
            add @rate_limit_ssh { ip saddr limit rate 3/minute burst 3 packets } \
            accept
        
        # HTTP/HTTPS with rate limiting
        tcp dport $HTTP_PORT ct state new limit rate 10/second burst 10 packets accept
        tcp dport $HTTPS_PORT ct state new limit rate 10/second burst 10 packets accept
        
        # ICMP (ping) - limited
        icmp type echo-request limit rate 5/second accept
        
        # Log dropped packets (optional, comment out in production)
        # log prefix "nftables-drop: " drop
    }
    
    chain forward {
        type filter hook forward priority filter; policy accept;
        
        # Allow established/related
        ct state established,related accept
        
        # Allow Docker networks
        iifname "docker0" accept
        iifname "br-*" accept
    }
    
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
