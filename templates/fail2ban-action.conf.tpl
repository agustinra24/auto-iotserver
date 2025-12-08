[Definition]

# Acción de Fail2Ban para nftables
# Agrega/elimina IPs al/del conjunto dinámico de nftables

actionstart = 

actionstop = 

actioncheck = 

actionban = nft add element inet filter fail2ban_blacklist { <ip> timeout 1h }

actionunban = nft delete element inet filter fail2ban_blacklist { <ip> }
