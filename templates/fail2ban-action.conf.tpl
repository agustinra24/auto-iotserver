[Definition]

# Acción de Fail2Ban para nftables del host.
# Usada para SSH, no para puertos publicados por Docker.

actionstart = 

actionstop = 

actioncheck = nft list set inet iot_filter fail2ban_blacklist >/dev/null

actionban = nft add element inet iot_filter fail2ban_blacklist { <ip> timeout 1h }

actionunban = nft delete element inet iot_filter fail2ban_blacklist { <ip> }
