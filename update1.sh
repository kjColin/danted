#!/bin/bash
# -*- coding: utf-8 -*-

# 配置文件路径
readonly DANTED_CONF="/etc/danted.conf"
readonly OUTPUT_FILE="/root/danted_config.txt"
readonly SERVICE_NAME="danted"

# 添加日志函数
log_error() {
    echo "[错误] $(date '+%Y-%m-%d %H:%M:%S'): $1" >&2
}

log_info() {
    echo "[信息] $(date '+%Y-%m-%d %H:%M:%S'): $1"
}

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
    # 获取所有网卡的IPv4地址（排除lo和docker网卡）
    local ip_info=$(ip -4 addr show | grep -v 'lo\|docker' | grep 'inet' | awk '{print $2}' | cut -d'/' -f1)
    if [[ -z "$ip_info" ]]; then
        log_error "未找到有效的IPv4地址，请检查网络配置"
        return 1
    fi
    echo "$ip_info"
}

# 添加端口验证函数
validate_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 在生成随机端口时添加验证
generate_unique_port() {
    local current_config=$1
    local new_port
    
    while true; do
        new_port=$(shuf -i 1024-65535 -n 1)
        if ! echo "$current_config" | grep -q " $new_port$" && validate_port "$new_port"; then
            echo "$new_port"
            return 0
        fi
    done
}

# 添加IP验证函数
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
            return 1
        fi
    done
    return 0
}

# 添加配置文件备份函数
backup_config() {
    local backup_file="${DANTED_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$DANTED_CONF" "$backup_file"; then
        log_error "配置文件备份失败"
        return 1
    fi
    log_info "配置文件已备份到: $backup_file"
    return 0
}

# 更改所有 IP 的端口号
change_all_ports() {
    backup_config || return 1
    echo "开始更改所有 IP 的端口号..."

    CURRENT_CONFIG=$(get_current_config)
    NETWORK_IPS=$(get_network_ips)
    
    # 创建临时文件
    TEMP_CONF=$(mktemp)
    TEMP_OUTPUT=$(mktemp)
    
    # 复制非IP配置
    grep -v -E "internal:|external:" "$DANTED_CONF" > "$TEMP_CONF"

    for IP in $NETWORK_IPS; do
        if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
            NEW_PORT=$(generate_unique_port "$CURRENT_CONFIG")
            # 获取当前用户名和密码
            local current_line=$(grep "^$IP:" "$OUTPUT_FILE")
            local username=$(echo "$current_line" | cut -d':' -f3)
            local password=$(echo "$current_line" | cut -d':' -f4)
            
            echo "internal: $IP port = $NEW_PORT" >> "$TEMP_CONF"
            echo "external: $IP" >> "$TEMP_CONF"
            echo "" >> "$TEMP_CONF"
            echo "$IP:$NEW_PORT:$username:$password" >> "$TEMP_OUTPUT"
            echo "IP $IP 的端口已更改为 $NEW_PORT。"
        fi
    done

    # 覆盖原文件
    mv "$TEMP_CONF" "$DANTED_CONF"
    mv "$TEMP_OUTPUT" "$OUTPUT_FILE"

    restart_service
}

# 更改指定 IP 的端口号
change_port() {
    read -p "请输入要更改端口的 IP: " IP
    CURRENT_CONFIG=$(get_current_config)

    if ! echo "$CURRENT_CONFIG" | grep -q "$IP"; then
        echo "错误：IP $IP 不存在于配置中。"
        return
    fi

    # 获取当前用户名和密码
    local current_line=$(grep "^$IP:" "$OUTPUT_FILE")
    local username=$(echo "$current_line" | cut -d':' -f3)
    local password=$(echo "$current_line" | cut -d':' -f4)
    
    NEW_PORT=$(generate_unique_port "$CURRENT_CONFIG")
    
    # 创建临时文件
    TEMP_CONF=$(mktemp)
    TEMP_OUTPUT=$(mktemp)
    
    # 更新配置文件
    sed "/internal: $IP port =/c\internal: $IP port = $NEW_PORT" "$DANTED_CONF" > "$TEMP_CONF"
    
    # 更新输出文件，保持用户名和密码不变
    sed "s/^$IP:.*/$IP:$NEW_PORT:$username:$password/" "$OUTPUT_FILE" > "$TEMP_OUTPUT"
    
    # 覆盖原文件
    mv "$TEMP_CONF" "$DANTED_CONF"
    mv "$TEMP_OUTPUT" "$OUTPUT_FILE"
    
    echo "IP $IP 的端口已更改为 $NEW_PORT。"

    restart_service
}

# 添加新的 IP 和端口
add_ip() {
    # 显示可用IP列表
    echo "可用的IP地址列表："
    local ip_list=$(get_network_ips)
    local number=1
    local -A ip_map
    
    while read -r ip; do
        echo "$number) $ip"
        ip_map[$number]=$ip
        ((number++))
    done <<< "$ip_list"
    
    read -p "请选择要添加的IP编号: " IP_NUMBER
    if [[ ! "${ip_map[$IP_NUMBER]}" ]]; then
        log_error "无效的选择"
        return 1
    fi
    
    IP="${ip_map[$IP_NUMBER]}"
    read -p "请输入用户名: " USERNAME
    read -s -p "请输入密码: " PASSWORD
    echo
    
    CURRENT_CONFIG=$(get_current_config)
    if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
        log_error "IP $IP 已存在于配置中"
        return 1
    fi

    NEW_PORT=$(generate_unique_port "$CURRENT_CONFIG")
    
    # 创建临时文件
    TEMP_CONF=$(mktemp)
    TEMP_OUTPUT=$(mktemp)
    
    # 复制现有配置
    cp "$DANTED_CONF" "$TEMP_CONF"
    cp "$OUTPUT_FILE" "$TEMP_OUTPUT"
    
    # 添加新配置
    echo "internal: $IP port = $NEW_PORT" >> "$TEMP_CONF"
    echo "external: $IP" >> "$TEMP_CONF"
    echo "" >> "$TEMP_CONF"
    echo "$IP:$NEW_PORT:$USERNAME:$PASSWORD" >> "$TEMP_OUTPUT"
    
    # 覆盖原文件
    mv "$TEMP_CONF" "$DANTED_CONF"
    mv "$TEMP_OUTPUT" "$OUTPUT_FILE"
    
    log_info "已添加 IP $IP 和端口 $NEW_PORT"
    restart_service
}

# 批量添加多个 IP
add_multiple_ips() {
    # 获取所有可用IP
    local available_ips=$(get_network_ips)
    if [[ -z "$available_ips" ]]; then
        log_error "没有可用的IP地址"
        return 1
    fi
    
    echo "可用的IP地址列表："
    echo "$available_ips" | nl
    
    read -p "请输入要添加的IP编号（多个编号用空格分隔）: " -a NUMBERS
    read -p "请输入用户名: " USERNAME
    read -s -p "请输入密码: " PASSWORD
    echo
    
    CURRENT_CONFIG=$(get_current_config)
    
    # 创建临时文件
    TEMP_CONF=$(mktemp)
    TEMP_OUTPUT=$(mktemp)
    
    # 复制现有配置
    cp "$DANTED_CONF" "$TEMP_CONF"
    cp "$OUTPUT_FILE" "$TEMP_OUTPUT"
    
    # 将编号转换为IP地址并添加
    for num in "${NUMBERS[@]}"; do
        IP=$(echo "$available_ips" | sed -n "${num}p")
        if [[ -z "$IP" ]]; then
            echo "警告：编号 $num 无效，跳过"
            continue
        fi
        
        if echo "$CURRENT_CONFIG" | grep -q "$IP"; then
            echo "警告：IP $IP 已存在，跳过"
            continue
        fi
        
        NEW_PORT=$(generate_unique_port "$CURRENT_CONFIG")
        echo "internal: $IP port = $NEW_PORT" >> "$TEMP_CONF"
        echo "external: $IP" >> "$TEMP_CONF"
        echo "" >> "$TEMP_CONF"
        echo "$IP:$NEW_PORT:$USERNAME:$PASSWORD" >> "$TEMP_OUTPUT"
        echo "已添加 IP $IP 和端口 $NEW_PORT"
    done
    
    # 覆盖原文件
    mv "$TEMP_CONF" "$DANTED_CONF"
    mv "$TEMP_OUTPUT" "$OUTPUT_FILE"
    
    restart_service
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

    restart_service
}

# 删除所有 IP
delete_all_ips() {
    if ! grep -q "internal: [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ port =" "$DANTED_CONF"; then
        echo "当前没有任何 IP 配置。"
        return
    fi

    # 创建临时文件
    TEMP_CONF=$(mktemp)
    
    # 删除所有IP配置，保留其他配置
    grep -v -E "internal:|external:" "$DANTED_CONF" > "$TEMP_CONF"
    
    # 覆盖原文件
    mv "$TEMP_CONF" "$DANTED_CONF"
    
    # 清空输出文件
    : > "$OUTPUT_FILE"
    
    echo "所有 IP 配置已删除。"

    restart_service
}

# 在服务重启函数中添加错误处理
restart_service() {
    if ! systemctl restart "$SERVICE_NAME"; then
        log_error "服务重启失败"
        return 1
    fi
    
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log_error "服务未能正常运行"
        return 1
    fi
    
    log_info "服务重启成功"
    systemctl status "$SERVICE_NAME"
}

show_help() {
    cat << EOF
用法说明：
1. 用户管理：
    - 添加系统用户
    - 删除系统用户
    - 修改用户密码
    - 查看系统用户

2. IP管理：
    - 添加新的IP和端口
    - 批量添加多个IP
    - 删除指定的IP
    - 删除所有IP
    - 查看当前IP配置

3. 端口管理：
    - 更改指定IP的端口
    - 更改所有IP的端口
    - 查看当前端口配置

注意：
- 所有用户操作都会立即生效
- IP和端口的修改会自动重启服务
- 请确保有足够的权限执行这些操作
EOF
}

# 用户管理相关函数
add_system_user() {
    read -p "请输入要添加的用户名: " USERNAME
    read -s -p "请输入用户密码: " PASSWORD
    echo
    
    if id "$USERNAME" &>/dev/null; then
        log_error "用户 $USERNAME 已存在"
        return 1
    fi
    
    # 创建系统用户，使用 /bin/false 作为 shell，不创建家目录
    if ! useradd -r -M -s /bin/false "$USERNAME"; then
        log_error "创建用户失败"
        return 1
    fi
    
    # 设置密码
    echo "$USERNAME:$PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        log_error "设置密码失败"
        userdel -r "$USERNAME"
        return 1
    fi
    
    # 锁定用户登录
    usermod -L "$USERNAME"
    
    # 添加到代理用户组
    if ! grep -q "^proxy:" /etc/group; then
        groupadd proxy
    fi
    usermod -aG proxy "$USERNAME"
    
    log_info "用户 $USERNAME 创建成功"
    return 0
}

delete_system_user() {
    # 显示当前可删除的用户列表
    echo "当前代理用户列表："
    echo "----------------------------------------"
    list_proxy_users
    echo "----------------------------------------"
    
    read -p "请输入要删除的用户名: " USERNAME
    
    if ! id "$USERNAME" &>/dev/null; then
        log_error "用户 $USERNAME 不存在"
        return 1
    fi
    
    # 检查用户是否是代理用户
    if ! is_proxy_user "$USERNAME"; then
        log_error "用户 $USERNAME 不是代理用户"
        return 1
    fi
    
    # 检查用户是否正在使用代理服务
    if is_user_active "$USERNAME"; then
        log_error "用户 $USERNAME 当前正在使用代理服务，无法删除"
        return 1
    fi
    
    if ! userdel "$USERNAME"; then
        log_error "删除用户失败"
        return 1
    fi
    
    log_info "用户 $USERNAME 删除成功"
    return 0
}

modify_user_password() {
    # 显示当前可修改的用户列表
    echo "当前代理用户列表："
    echo "----------------------------------------"
    list_proxy_users
    echo "----------------------------------------"
    
    read -p "请输入用户名: " USERNAME
    read -s -p "请输入新密码: " NEW_PASSWORD
    echo
    
    if ! id "$USERNAME" &>/dev/null; then
        log_error "用户 $USERNAME 不存在"
        return 1
    fi
    
    # 检查用户是否是代理用户
    if ! is_proxy_user "$USERNAME"; then
        log_error "用户 $USERNAME 不是代理用户"
        return 1
    fi
    
    echo "$USERNAME:$NEW_PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        log_error "修改密码失败"
        return 1
    fi
    
    log_info "用户 $USERNAME 密码修改成功"
    return 0
}

# 辅助函数：检查用户是否是代理用户
is_proxy_user() {
    local username=$1
    local shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
    local groups=$(groups "$username" 2>/dev/null)
    
    # 检查 shell 是否为 /bin/false 且属于 proxy 组
    [ "$shell" = "/bin/false" ] && [[ $groups == *"proxy"* ]]
}

# 辅助函数：检查用户是否正在使用代理服务
is_user_active() {
    local username=$1
    # 检查是否有活动连接
    netstat -anp | grep ":$(grep "^$username:" "$OUTPUT_FILE" | cut -d: -f2)" | grep -q ESTABLISHED
}

# 显示代理用户列表
list_proxy_users() {
    printf "%-20s %-10s %-15s %-15s\n" "用户名" "UID" "状态" "最后活动时间"
    echo "----------------------------------------"
    
    while IFS=: read -r username _ uid _ _ _ shell; do
        # 只处理 /bin/false shell 用户且属于 proxy 组的用户
        if [ "$shell" = "/bin/false" ] && groups "$username" 2>/dev/null | grep -q "proxy"; then
            local status="未连接"
            local last_active="-"
            
            # 检查用户是否有活动连接
            if is_user_active "$username"; then
                status="活动"
                last_active=$(date '+%Y-%m-%d %H:%M')
            else
                # 获取最后活动时间（如果有）
                last_active=$(last -F "$username" | grep -v "never" | head -1 | awk '{print $5,$6,$7}')
                [ -z "$last_active" ] && last_active="-"
            fi
            
            printf "%-20s %-10s %-15s %-15s\n" "$username" "$uid" "$status" "$last_active"
        fi
    done < /etc/passwd
}

# 修改用户管理菜单
user_management_menu() {
    while true; do
        echo "用户管理菜单："
        echo "1. 添加代理用户"
        echo "2. 删除代理用户"
        echo "3. 修改用户密码"
        echo "4. 查看代理用户"
        echo "5. 返回主菜单"
        read -p "请输入选项（1-5）: " CHOICE

        case $CHOICE in
            1) add_system_user ;;
            2) delete_system_user ;;
            3) modify_user_password ;;
            4) list_proxy_users ;;
            5) return ;;
            *) echo "无效选项，请重新输入。" ;;
        esac
    done
}

# IP管理菜单
ip_management_menu() {
    while true; do
        echo "IP管理菜单："
        echo "1. 添加新的IP和端口"
        echo "2. 批量添加多个IP"
        echo "3. 删除指定的IP"
        echo "4. 删除所有IP"
        echo "5. 查看当前IP配置"
        echo "6. 返回主菜单"
        read -p "请输入选项（1-6）: " CHOICE

        case $CHOICE in
            1) add_ip ;;
            2) add_multiple_ips ;;
            3) delete_ip ;;
            4) delete_all_ips ;;
            5) show_ip_config ;;
            6) return ;;
            *) echo "无效选项，请重新输入。" ;;
        esac
    done
}

# 端口管理菜单
port_management_menu() {
    while true; do
        echo "端口管理菜单："
        echo "1. 更改指定IP的端口"
        echo "2. 更改所有IP的端口"
        echo "3. 查看当前端口配置"
        echo "4. 返回主菜单"
        read -p "请输入选项（1-4）: " CHOICE

        case $CHOICE in
            1) change_port ;;
            2) change_all_ports ;;
            3) show_port_config ;;
            4) return ;;
            *) echo "无效选项，请重新输入。" ;;
        esac
    done
}

# 添加配置查询函数
show_ip_config() {
    echo "当前系统网卡IP配置："
    echo "----------------------------------------"
    ip -4 addr show | grep -v 'lo\|docker' | grep 'inet'
    echo "----------------------------------------"
    
    echo "当前代理服务IP配置："
    echo "----------------------------------------"
    if [[ -f "$OUTPUT_FILE" ]]; then
        printf "%-15s %-8s %-15s %-15s\n" "IP地址" "端口" "用户名" "状态"
        echo "----------------------------------------"
        while IFS=: read -r ip port username _; do
            local status="未运行"
            if grep -q "internal: $ip port = $port" "$DANTED_CONF"; then
                if ss -tnlp | grep -q ":$port"; then
                    status="运行中"
                fi
            fi
            printf "%-15s %-8s %-15s %-15s\n" "$ip" "$port" "$username" "$status"
        done < "$OUTPUT_FILE"
    else
        echo "未找到配置文件"
    fi
    echo "----------------------------------------"
}

show_port_config() {
    echo "当前端口配置："
    echo "----------------------------------------"
    grep -E "internal.*port" "$DANTED_CONF"
    echo "----------------------------------------"
}

# 修改主菜单
while true; do
    echo "��菜单："
    echo "1. 用户管理"
    echo "2. IP管理"
    echo "3. 端口管理"
    echo "4. 显示帮助信息"
    echo "5. 退出"
    read -p "请输入选项（1-5）: " CHOICE

    case $CHOICE in
        1) user_management_menu ;;
        2) ip_management_menu ;;
        3) port_management_menu ;;
        4) show_help ;;
        5) echo "退出程序。"; break ;;
        *) echo "无效选项，请重新输入。" ;;
    esac
done
