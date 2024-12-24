#!/bin/bash

DANTED_CONF="/etc/danted.conf"
OUTPUT_FILE="/root/danted_config.txt"

# 检查 danted.conf 是否存在
if [[ ! -f "$DANTED_CONF" ]]; then
    echo "错误：$DANTED_CONF 文件不存在，请先生成初始配置。"
    exit 1
fi

# 提取当前配置中的 IP 和端口
get_current_config() {
    grep -E "internal: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ port =" "$DANTED_CONF" | \
    awk '{print $2, $4}' | tr -d '='
}

# 读取网卡 IP 地址
get_network_ips() {
    IP_LIST=$(hostname -I | tr ' ' '\n' | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}")
    if [[ -z "$IP_LIST" ]]; then
        echo "未找到 IPv4 地址，请检查网络配置"
        exit 1
    fi
    echo "$IP_LIST"
}

# 更改所有 IP 的端口号
change_all_ports() {
    echo "开始更改所有 IP 的端口号..."

    CURRENT_CONFIG=$(get_current_config)
    NETWORK_IPS=$(get_network_ips)

    # 遍历配置中的每个 IP，重新分配端口
    for IP in $NETWORK_IPS; do
        if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
            NEW_PORT=$(shuf -i 1024-65535 -n 1)
            while echo "$CURRENT_CONFIG" | grep -q " $NEW_PORT$"; do
                NEW_PORT=$(shuf -i 1024-65535 -n 1)
            done
            sed -i "/internal: $IP port =/c\internal: $IP port = $NEW_PORT" "$DANTED_CONF"
            sed -i "s/^$IP:.*/$IP:$NEW_PORT/" "$OUTPUT_FILE"
            echo "IP $IP 的端口已更改为 $NEW_PORT。"
        fi
    done

    # 重启服务并显示状态
    systemctl restart danted
    systemctl status danted
}

# 更改指定 IP 的端口号
change_port() {
    read -p "请输入要更改端口的 IP: " IP
    CURRENT_CONFIG=$(get_current_config)

    if ! echo "$CURRENT_CONFIG" | grep -q "$IP"; then
        echo "错误：IP $IP 不存在于配置中。"
        return
    fi

    NEW_PORT=$(shuf -i 1024-65535 -n 1)
    while echo "$CURRENT_CONFIG" | grep -q " $NEW_PORT$"; do
        NEW_PORT=$(shuf -i 1024-65535 -n 1)
    done

    sed -i "/internal: $IP port =/c\internal: $IP port = $NEW_PORT" "$DANTED_CONF"
    sed -i "s/^$IP:.*/$IP:$NEW_PORT/" "$OUTPUT_FILE"
    echo "IP $IP 的端口已更改为 $NEW_PORT。"

    systemctl restart danted
    systemctl status danted
}

# 添加新的 IP 和端口
add_ip() {
    read -p "请输入要添加的 IP: " IP
    CURRENT_CONFIG=$(get_current_config)

    if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
        echo "错误：IP $IP 已存在于配置中。"
        return
    fi

    NEW_PORT=$(shuf -i 1024-65535 -n 1)
    while echo "$CURRENT_CONFIG" | grep -q " $NEW_PORT$"; do
        NEW_PORT=$(shuf -i 1024-65535 -n 1)
    done

    # 使用临时文件存储现有配置
    cp "$DANTED_CONF" "$DANTED_CONF.tmp"
    cat "$DANTED_CONF.tmp" > "$DANTED_CONF"
    echo "internal: $IP port = $NEW_PORT" >> "$DANTED_CONF"
    echo "external: $IP" >> "$DANTED_CONF"
    echo "" >> "$DANTED_CONF"
    rm -f "$DANTED_CONF.tmp"
    
    # 覆盖写入新的 IP:端口
    echo "$IP:$NEW_PORT" > "$OUTPUT_FILE"
    echo "已添加 IP $IP 和端口 $NEW_PORT。"

    systemctl restart danted
    systemctl status danted
}

# 批量添加多个 IP
add_multiple_ips() {
    read -p "请输入要添加的 IP 列表（以空格分隔）: " -a IP_ARRAY
    CURRENT_CONFIG=$(get_current_config)

    # 使用临时文件存储现有配置
    cp "$DANTED_CONF" "$DANTED_CONF.tmp"
    cat "$DANTED_CONF.tmp" > "$DANTED_CONF"
    > "$OUTPUT_FILE"  # 清空输出文件

    for IP in "${IP_ARRAY[@]}"; do
        if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
            echo "警告：IP $IP 已存在，跳过。"
            continue
        fi

        NEW_PORT=$(shuf -i 1024-65535 -n 1)
        while echo "$CURRENT_CONFIG" | grep -q " $NEW_PORT$"; do
            NEW_PORT=$(shuf -i 1024-65535 -n 1)
        done

        echo "internal: $IP port = $NEW_PORT" >> "$DANTED_CONF"
        echo "external: $IP" >> "$DANTED_CONF"
        echo "" >> "$DANTED_CONF"
        echo "$IP:$NEW_PORT" >> "$OUTPUT_FILE"
        echo "已添加 IP $IP 和端口 $NEW_PORT。"
    done

    rm -f "$DANTED_CONF.tmp"
    systemctl restart danted
    systemctl status danted
}

# 删除指定的 IP
delete_ip() {
    read -p "请输入要删除的 IP: " IP
    if ! grep -q "internal: $IP port =" "$DANTED_CONF"; then
        echo "错误：IP $IP 不存在于配置中。"
        return
    fi

    sed -i "/internal: $IP port =/,+1d" "$DANTED_CONF"
    sed -i "/$IP/d" "$OUTPUT_FILE"
    echo "IP $IP 已删除。"

    systemctl restart danted
    systemctl status danted
}

# 删除所有 IP
delete_all_ips() {
    if ! grep -q "internal: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ port =" "$DANTED_CONF"; then
        echo "当前没有任何 IP 配置。"
        return
    fi

    sed -i '/internal: [0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+ port =/,+1d' "$DANTED_CONF"
    > "$OUTPUT_FILE"
    echo "所有 IP 配置已删除。"

    systemctl restart danted
    systemctl status danted
}

# 查看所有代理用户
list_users() {
    echo "当前系统中的代理用户："
    grep "/bin/false" /etc/passwd | cut -d: -f1
}

# 添加代理用户
add_user() {
    read -p "请输入要添加的用户名: " USERNAME
    if id "$USERNAME" &>/dev/null; then
        echo "错误：用户 $USERNAME 已存在。"
        return
    fi

    # 创建系统用户，禁止登录shell
    useradd -r -s /bin/false "$USERNAME"
    
    # 设置密码
    passwd "$USERNAME"
    
    echo "用户 $USERNAME 已创建成功。"
}

# 删除代理用户
delete_user() {
    read -p "请输入要删除的用户名: " USERNAME
    if ! id "$USERNAME" &>/dev/null; then
        echo "错误：用户 $USERNAME 不存在。"
        return
    fi

    if ! grep -q "/bin/false" "/etc/passwd" | grep -q "^$USERNAME:"; then
        echo "错误：$USERNAME 不是代理用户。"
        return
    fi

    userdel "$USERNAME"
    echo "用户 $USERNAME 已删除。"
}

# 修改用户密码
change_password() {
    read -p "请输入要修改密码的用户名: " USERNAME
    if ! id "$USERNAME" &>/dev/null; then
        echo "错误：用户 $USERNAME 不存在。"
        return
    fi

    if ! grep -q "/bin/false" "/etc/passwd" | grep -q "^$USERNAME:"; then
        echo "错误：$USERNAME 不是代理用户。"
        return
    fi

    passwd "$USERNAME"
}

# 主菜单
while true; do
    echo "请选择操作："
    echo "1. 更改指定 IP 的端口号"
    echo "2. 添加新的 IP 和端口"
    echo "3. 批量添加多个 IP"
    echo "4. 删除指定的 IP"
    echo "5. 删除所有 IP"
    echo "6. 更改所有 IP 的端口号"
    echo "7. 查看代理用户"
    echo "8. 添加代理用户"
    echo "9. 删除代理用户"
    echo "10. 修改用户密码"
    echo "11. 退出"
    read -p "请输入选项（1-11）: " CHOICE

    case $CHOICE in
        1) change_port ;;
        2) add_ip ;;
        3) add_multiple_ips ;;
        4) delete_ip ;;
        5) delete_all_ips ;;
        6) change_all_ports ;;
        7) list_users ;;
        8) add_user ;;
        9) delete_user ;;
        10) change_password ;;
        11) echo "退出程序。"; break ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
done
