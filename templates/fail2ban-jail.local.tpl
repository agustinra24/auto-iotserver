[DEFAULT]
bantime  = 3600
findtime  = 600
maxretry = 5
backend = systemd
action   = nftables-custom

[sshd]
enabled = true
port    = {{SSH_PORT}}
logpath = /var/log/auth.log
maxretry = 5

[nginx-auth]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 10

[nginx-noscript]
enabled = true
port    = http,https
logpath = /var/log/nginx/access.log
maxretry = 6
