[Definition]

# Fail2Ban action for nftables
# Adds/removes IPs to/from nftables dynamic set

actionstart = 

actionstop = 

actioncheck = 

actionban = nft add element inet filter fail2ban_blacklist { <ip> timeout 1h }

actionunban = nft delete element inet filter fail2ban_blacklist { <ip> }
