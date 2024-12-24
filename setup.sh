#!/bin/bash

# 1. 更新系统并安装 dante-server
echo "更新系统并安装 dante-server..."
apt update && apt install -y dante-server || { echo "安装失败，请检查网络连接"; exit 1; }

# 2. 获取所有 IPv4 地址
echo "获取所有 IPv4 地址..."
IP_LIST=$(hostname -I | tr ' ' '\n' | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}")
if [[ -z "$IP_LIST" ]]; then
    echo "未找到有效的 IPv4 地址，请检查网络配置"
    exit 1
fi

# 3. 用户输入用户名和密码
read -p "请输入用户名: " USERNAME
read -sp "请输入密码: " PASSWORD
echo

# 检查用户是否已存在
if id "$USERNAME" &>/dev/null; then
    echo "用户 $USERNAME 已存在，退出。"
    exit 1
fi

# 添加系统用户
echo "添加用户 $USERNAME..."
useradd -r -s /bin/false "$USERNAME" || { echo "用户添加失败"; exit 1; }
echo "$USERNAME:$PASSWORD" | chpasswd || { echo "密码设置失败"; exit 1; }

# 4. 随机分配端口并生成配置
echo "生成 danted 配置文件..."
PORT_LIST=()
DANTED_CONF="/etc/danted.conf"
OUTPUT_FILE="/root/danted_config.txt"
> "$DANTED_CONF"
> "$OUTPUT_FILE"

# 写入 danted.conf 标头
cat > "$DANTED_CONF" <<EOF
# 日志文件
logoutput: stderr

# 定义代理运行的用户和组
user.privileged: root
user.unprivileged: nobody

EOF

# 分配 IP 和端口
for IP in $IP_LIST; do
    PORT=$(shuf -i 1024-65535 -n 1)
    while [[ " ${PORT_LIST[@]} " =~ " $PORT " ]]; do
        PORT=$(shuf -i 1024-65535 -n 1)
    done
    PORT_LIST+=("$PORT")

    echo "internal: $IP port = $PORT" >> "$DANTED_CONF"
    echo "external: $IP" >> "$DANTED_CONF"
    echo "" >> "$DANTED_CONF"
    echo "$IP:$PORT:$USERNAME:$PASSWORD" >> "$OUTPUT_FILE"
done

# 写入 danted.conf 规则
cat >> "$DANTED_CONF" <<EOF
# 设置 external.rotation 为 same-same
external.rotation: same-same

# 客户端认证方式
clientmethod: none
socksmethod: username

# 允许规则
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

# 5. 重启 danted 服务
echo "重启 danted 服务..."
systemctl restart danted && systemctl status danted || { echo "danted 服务启动失败"; exit 1; }

echo "配置完成！"
echo "IP:端口列表已输出到 $OUTPUT_FILE"
echo "danted 配置文件已更新到 $DANTED_CONF"
