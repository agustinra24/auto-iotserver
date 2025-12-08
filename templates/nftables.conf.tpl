#!/usr/sbin/nft -f

flush ruleset

define SSH_PORT = {{SSH_PORT}}
define HTTP_PORT = 80
define HTTPS_PORT = 443

table inet filter {
    # Conjuntos dinámicos de IP para fail2ban y limitación de tasa
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
        
        # Permitir loopback
        iif lo accept
        
        # Permitir conexiones establecidas/relacionadas
        ct state established,related accept
        
        # Descartar paquetes inválidos
        ct state invalid drop
        
        # Lista negra de Fail2Ban (máxima prioridad)
        ip saddr @fail2ban_blacklist drop
        
        # SSH con limitación de tasa (3 conexiones por minuto por IP)
        tcp dport $SSH_PORT ct state new \
            add @rate_limit_ssh { ip saddr limit rate 3/minute burst 3 packets } \
            accept
        
        # HTTP/HTTPS con limitación de tasa
        tcp dport $HTTP_PORT ct state new limit rate 10/second burst 10 packets accept
        tcp dport $HTTPS_PORT ct state new limit rate 10/second burst 10 packets accept
        
        # ICMP (ping) - limitado
        icmp type echo-request limit rate 5/second accept
        
        # Registrar paquetes descartados (opcional, comentar en producción)
        # log prefix "nftables-drop: " drop
    }
    
    chain forward {
        type filter hook forward priority filter; policy accept;
        
        # Permitir establecidas/relacionadas
        ct state established,related accept
        
        # Permitir redes Docker
        iifname "docker0" accept
        iifname "br-*" accept
    }
    
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
