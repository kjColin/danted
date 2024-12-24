#!/bin/bash

# Check root permissions
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# Configuration paths
DANTED_CONF="/etc/danted.conf"
OUTPUT_FILE="/root/danted_config.txt"
BACKUP_CONF="/root/danted.conf.bak"

# Backup existing config
if [[ -f "$DANTED_CONF" ]]; then
    BACKUP_CONF="/root/danted_$(date +'%Y%m%d_%H%M%S').bak"
    cp "$DANTED_CONF" "$BACKUP_CONF"
    echo "备份已创建：$BACKUP_CONF"
fi

# Get IPv4 addresses
IP_LIST=$(hostname -I | tr ' ' '\n' | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}")
if [[ -z "$IP_LIST" ]]; then
    echo "未找到有效的 IPv4 地址"
    exit 1
fi

# Get current users with /bin/false shell
EXISTING_USERS=$(grep "/bin/false" /etc/passwd | cut -d: -f1)

# Get new credentials
read -p "请输入要修改密码的用户名: " USERNAME
if ! echo "$EXISTING_USERS" | grep -q "^$USERNAME$"; then
    echo "错误：用户名 $USERNAME 不存在或不具有 /bin/false shell"
    exit 1
fi

read -sp "请输入新密码: " PASSWORD
echo

# Update password for the user
echo "$USERNAME:$PASSWORD" | chpasswd
echo "用户 $USERNAME 的密码已更新。"

# List of protected users that should never be modified
PROTECTED_USERS="root nobody daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats sshd"

# Generate new config
PORT_LIST=()
> "$DANTED_CONF"
> "$OUTPUT_FILE"

# Write base config
cat > "$DANTED_CONF" <<EOF
logoutput: stderr
user.privileged: root
user.unprivileged: nobody

EOF

# Configure IPs and ports
for IP in $IP_LIST; do
    PORT=$(shuf -i 10000-65000 -n 1)
    while [[ " ${PORT_LIST[@]} " =~ " $PORT " ]]; do
        PORT=$(shuf -i 10000-65000 -n 1)
    done
    PORT_LIST+=("$PORT")

    echo "internal: $IP port = $PORT" >> "$DANTED_CONF"
    echo "external: $IP" >> "$DANTED_CONF"
    echo "" >> "$DANTED_CONF"
    echo "$IP:$PORT:$USERNAME:$PASSWORD" >> "$OUTPUT_FILE"
done

# Add access rules
cat >> "$DANTED_CONF" <<EOF
external.rotation: same-same
clientmethod: none
socksmethod: username

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect error
}
EOF

# Set permissions
chmod 600 "$DANTED_CONF"
chmod 600 "$OUTPUT_FILE"

# Restart service and handle errors
systemctl restart danted
if [[ $? -ne 0 ]]; then
    echo "错误：danted 服务重启失败。请检查配置文件是否正确。"
    exit 1
fi

echo "配置已更新，新代理信息已保存至 $OUTPUT_FILE"
systemctl status danted
