#!/usr/bin/env bash
# Linux 定时任务管理工具（简化版）
# 功能：添加 / 查看 / 删除 / 暂停 / 恢复 / 今日执行情况 / 立即执行
# 自动检测并安装 cron 相关依赖（尽力支持常见发行版）

# ====== 外观相关 ======
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

divider() {
    printf "%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$CYAN" "$RESET"
}

pause() {
    echo
    read -rp "按回车键继续..." _
}

LOG_FILE="${HOME}/.cron_easy.log"
RUNNER_SCRIPT="${HOME}/.cron_easy_run.sh"

# ====== 依赖检测 & 安装 ======

run_with_sudo_if_needed() {
    if [[ $EUID -eq 0 ]]; then
        bash -c "$*"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo bash -c "$*"
        else
            echo -e "${RED}⚠ 当前不是 root，且系统没有 sudo，无法自动安装依赖。${RESET}"
            echo -e "${YELLOW}请手动安装 cron / cronie 后再运行本脚本。${RESET}"
            exit 1
        fi
    fi
}

install_cron_if_needed() {
    if command -v crontab >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${YELLOW}⚠ 未检测到 crontab 命令，尝试自动安装 cron 相关组件...${RESET}"

    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${BLUE}➜ 检测到 apt-get，尝试安装 cron...${RESET}"
        run_with_sudo_if_needed "apt-get update -y && apt-get install -y cron"
    elif command -v yum >/dev/null 2>&1; then
        echo -e "${BLUE}➜ 检测到 yum，尝试安装 cronie...${RESET}"
        run_with_sudo_if_needed "yum install -y cronie"
    elif command -v dnf >/dev/null 2>&1; then
        echo -e "${BLUE}➜ 检测到 dnf，尝试安装 cronie...${RESET}"
        run_with_sudo_if_needed "dnf install -y cronie"
    elif command -v zypper >/dev/null 2>&1; then
        echo -e "${BLUE}➜ 检测到 zypper，尝试安装 cron...${RESET}"
        run_with_sudo_if_needed "zypper install -y cron"
    elif command -v pacman >/dev/null 2>&1; then
        echo -e "${BLUE}➜ 检测到 pacman，尝试安装 cronie...${RESET}"
        run_with_sudo_if_needed "pacman -Sy --noconfirm cronie"
    else
        echo -e "${RED}✖ 未找到常见包管理器，无法自动安装 cron。${RESET}"
        echo -e "${YELLOW}请手动安装 cron / cronie 后再运行本脚本。${RESET}"
        exit 1
    fi

    if ! command -v crontab >/dev/null 2>&1; then
        echo -e "${RED}✖ 安装完成后仍未检测到 crontab，请手动检查系统。${RESET}"
        exit 1
    fi

    echo -e "${GREEN}✔ crontab 安装成功。${RESET}"

    if command -v systemctl >/dev/null 2>&1; then
        for svc in cron crond cronie; do
            if systemctl list-unit-files | grep -q "^${svc}.service"; then
                echo -e "${BLUE}➜ 尝试启动并设置 ${svc} 开机自启...${RESET}"
                run_with_sudo_if_needed "systemctl enable --now ${svc}.service" || true
            fi
        done
    fi
}

# ====== 通用显示 ======
show_header() {
    clear
    divider
    printf "%b┃%b %-43s %b┃%b\n" "$CYAN" "$RESET" "Linux 定时任务管理工具" "$CYAN" "$RESET"
    divider
    echo -e "当前用户：${YELLOW}$(whoami)${RESET}"
    echo
}

# ====== 工具函数 ======

read_int_in_range() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local value

    while true; do
        read -rp "$prompt" value
        if [[ -z "$value" ]]; then
            echo ""
            return 0
        fi
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}✖ 请输入数字。${RESET}"
            continue
        fi
        if (( value < min || value > max )); then
            echo -e "${RED}✖ 取值范围应为 ${min}-${max}。${RESET}"
            continue
        fi
        echo "$value"
        return 0
    done
}

ensure_runner_script() {
    if [[ -f "$RUNNER_SCRIPT" ]]; then
        return 0
    fi

    cat > "$RUNNER_SCRIPT" << 'EOF'
#!/usr/bin/env bash
LOG_FILE="${HOME}/.cron_easy.log"
ts="$(date '+%F %T')"
cmd="$*"
/bin/bash -c "$cmd"
exit_code=$?
status="FAIL"
if [[ $exit_code -eq 0 ]]; then
    status="OK"
fi
echo "$ts | $status | exit=$exit_code | cmd=$cmd" >> "$LOG_FILE"
exit $exit_code
EOF

    chmod +x "$RUNNER_SCRIPT"
}

# ====== 查看定时任务 ======
list_cron() {
    show_header
    echo -e "${BOLD}${GREEN}📋 当前定时任务：${RESET}"
    divider

    tmpfile="$(mktemp)"
    if crontab -l 2>/dev/null | sed '/^\s*$/d' >"$tmpfile"; then
        if [[ ! -s "$tmpfile" ]]; then
            echo -e "${YELLOW}（当前没有任何定时任务）${RESET}"
        else
            nl -ba "$tmpfile" | sed "s/^/┃ /"
        fi
    else
        echo -e "${YELLOW}（当前没有任何定时任务）${RESET}"
    fi
    rm -f "$tmpfile"
    divider
    pause
}

# ====== 添加定时任务 ======
add_cron() {
    show_header
    echo -e "${BOLD}${GREEN}➕ 添加定时任务${RESET}"
    divider
    echo -e "请选择任务执行频率："
    echo -e "  ${CYAN}1${RESET}) 每小时       （固定某分钟）"
    echo -e "  ${CYAN}2${RESET}) 每天         （时:分）"
    echo -e "  ${CYAN}3${RESET}) 每周         （星期 + 时:分）"
    echo -e "  ${CYAN}4${RESET}) 每月         （某日 + 时:分）"
    echo -e "  ${CYAN}5${RESET}) 每年         （月/日 + 时:分）"
    echo -e "  ${CYAN}6${RESET}) 自定义 cron 表达式"
    echo
    read -rp "请输入选项编号： " mode

    local minute hour day month week
    local schedule

    case "$mode" in
        1)
            echo
            echo -e "${MAGENTA}▶ 每小时执行${RESET}"
            minute=$(read_int_in_range "请输入分钟 (0-59)： " 0 59)
            [[ -z "$minute" ]] && echo -e "${RED}✖ 不能为空。${RESET}" && pause && return
            schedule="${minute} * * * *"
            ;;
        2)
            echo
            echo -e "${MAGENTA}▶ 每天执行${RESET}"
            hour=$(read_int_in_range "请输入小时 (0-23)： " 0 23)
            minute=$(read_int_in_range "请输入分钟 (0-59)： " 0 59)
            if [[ -z "$hour" || -z "$minute" ]]; then
                echo -e "${RED}✖ 时和分不能为空。${RESET}"
                pause; return
            fi
            schedule="${minute} ${hour} * * *"
            ;;
        3)
            echo
            echo -e "${MAGENTA}▶ 每周执行${RESET}"
            echo -e "星期说明：0 或 7=周日，1=周一，...，6=周六"
            week=$(read_int_in_range "请输入星期 (0-7)： " 0 7)
            hour=$(read_int_in_range "请输入小时 (0-23)： " 0 23)
            minute=$(read_int_in_range "请输入分钟 (0-59)： " 0 59)
            if [[ -z "$week" || -z "$hour" || -z "$minute" ]]; then
                echo -e "${RED}✖ 星期、时、分不能为空。${RESET}"
                pause; return
            fi
            schedule="${minute} ${hour} * * ${week}"
            ;;
        4)
            echo
            echo -e "${MAGENTA}▶ 每月执行${RESET}"
            day=$(read_int_in_range "请输入日期 (1-31)： " 1 31)
            hour=$(read_int_in_range "请输入小时 (0-23)： " 0 23)
            minute=$(read_int_in_range "请输入分钟 (0-59)： " 0 59)
            if [[ -z "$day" || -z "$hour" || -z "$minute" ]]; then
                echo -e "${RED}✖ 日、时、分不能为空。${RESET}"
                pause; return
            fi
            schedule="${minute} ${hour} ${day} * *"
            ;;
        5)
            echo
            echo -e "${MAGENTA}▶ 每年执行${RESET}"
            month=$(read_int_in_range "请输入月份 (1-12)： " 1 12)
            day=$(read_int_in_range "请输入日期 (1-31)： " 1 31)
            hour=$(read_int_in_range "请输入小时 (0-23)： " 0 23)
            minute=$(read_int_in_range "请输入分钟 (0-59)： " 0 59)
            if [[ -z "$month" || -z "$day" || -z "$hour" || -z "$minute" ]]; then
                echo -e "${RED}✖ 月、日、时、分不能为空。${RESET}"
                pause; return
            fi
            schedule="${minute} ${hour} ${day} ${month} *"
            ;;
        6)
            echo
            echo -e "${MAGENTA}▶ 自定义 cron 表达式${RESET}"
            echo -e "格式：${YELLOW}分 时 日 月 周${RESET}，例如：${YELLOW}0 3 * * *${RESET}"
            read -rp "请输入完整 cron 表达式： " schedule
            schedule="$(echo "$schedule" | sed 's/^[ \t]*//;s/[ \t]*$//')"
            [[ -z "$schedule" ]] && echo -e "${RED}✖ 表达式不能为空。${RESET}" && pause && return
            ;;
        *)
            echo -e "${RED}✖ 无效选项。${RESET}"
            pause; return
            ;;
    esac

    echo
    echo -e "${CYAN}🕒 时间表达式：${YELLOW}${schedule}${RESET}"
    read -rp "请输入要执行的命令（尽量写绝对路径）： " cmd
    cmd="$(echo "$cmd" | sed 's/^[ \t]*//;s/[ \t]*$//')"
    [[ -z "$cmd" ]] && echo -e "${RED}✖ 命令不能为空。${RESET}" && pause && return

    echo
    echo -e "${BOLD}请选择输出处理方式：${RESET}"
    echo -e "  ${CYAN}1${RESET}) 保留输出（不处理）"
    echo -e "  ${CYAN}2${RESET}) 丢弃所有输出（>/dev/null 2>&1）"
    echo -e "  ${CYAN}3${RESET}) 写入指定日志文件（>> file 2>&1）"
    echo
    read -rp "请输入选项编号： " out_mode

    local cmd_final log_path

    case "$out_mode" in
        1|"")
            cmd_final="${cmd}"
            ;;
        2)
            cmd_final="${cmd} >/dev/null 2>&1"
            ;;
        3)
            read -rp "请输入日志文件路径（例如 /var/log/myjob.log）： " log_path
            log_path="$(echo "$log_path" | sed 's/^[ \t]*//;s/[ \t]*$//')"
            [[ -z "$log_path" ]] && echo -e "${RED}✖ 日志文件路径不能为空。${RESET}" && pause && return
            cmd_final="${cmd} >>${log_path} 2>&1"
            ;;
        *)
            echo -e "${YELLOW}未知选项，默认保留输出。${RESET}"
            cmd_final="${cmd}"
            ;;
    esac

    echo
    echo -e "${BOLD}是否启用执行日志（用于“今日执行情况”）？${RESET}"
    echo -e "  ${CYAN}y${RESET}) 是，记录到 ${YELLOW}${LOG_FILE}${RESET}"
    echo -e "  其他） 否，不记录"
    read -rp "选择 (y/N): " log_choice

    if [[ "$log_choice" == "y" || "$log_choice" == "Y" ]]; then
        ensure_runner_script
        cmd_final="${RUNNER_SCRIPT} ${cmd_final}"
    fi

    new_line="${schedule} ${cmd_final}"

    tmpfile="$(mktemp)"
    if crontab -l 2>/dev/null >"$tmpfile"; then :; else : >"$tmpfile"; fi
    echo "$new_line" >>"$tmpfile"
    crontab "$tmpfile"
    rm -f "$tmpfile"

    echo
    divider
    echo -e "${GREEN}✔ 定时任务添加成功：${RESET}"
    echo -e "  ${BOLD}${new_line}${RESET}"
    if [[ "$log_choice" == "y" || "$log_choice" == "Y" ]]; then
        echo -e "  🔎 已开启执行日志，稍后可在菜单 [6] 查看今日执行情况"
    fi
    divider
    pause
}

# ====== 删除定时任务 ======
delete_cron() {
    show_header
    echo -e "${BOLD}${GREEN}🗑 删除定时任务${RESET}"
    divider

    tmpfile="$(mktemp)"
    if ! crontab -l 2>/dev/null | sed '/^\s*$/d' >"$tmpfile"; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    echo -e "${CYAN}当前任务列表：${RESET}"
    nl -ba "$tmpfile" | sed "s/^/┃ /"
    divider
    echo -e "请输入要删除的行号（多个用空格隔开），直接回车取消："
    read -rp "行号： " line_nums

    if [[ -z "$line_nums" ]]; then
        echo "已取消删除。"
        rm -f "$tmpfile"; pause; return
    fi

    if ! echo "$line_nums" | grep -Eq '^[0-9 ]+$'; then
        echo -e "${RED}✖ 输入格式错误，只能是数字和空格。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    sed_cmd=()
    for n in $line_nums; do
        sed_cmd+=("-e" "${n}d")
    done

    tmpfile_new="$(mktemp)"
    if sed "${sed_cmd[@]}" "$tmpfile" >"$tmpfile_new"; then
        crontab "$tmpfile_new"
        echo
        echo -e "${GREEN}✔ 删除完成，当前 crontab：${RESET}"
        divider
        if [[ -s "$tmpfile_new" ]]; then
            nl -ba "$tmpfile_new" | sed "s/^/┃ /"
        else
            echo -e "${YELLOW}（已没有任何任务）${RESET}"
        fi
        divider
    else
        echo -e "${RED}✖ 删除时出错，crontab 未修改。${RESET}"
    fi

    rm -f "$tmpfile" "$tmpfile_new"
    pause
}

# ====== 暂停定时任务 ======
pause_cron() {
    show_header
    echo -e "${BOLD}${GREEN}⏸ 暂停定时任务${RESET}"
    divider

    tmpfile="$(mktemp)"
    if ! crontab -l 2>/dev/null >"$tmpfile"; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    echo -e "${CYAN}当前任务（含已暂停）：${RESET}"
    nl -ba "$tmpfile" | sed "s/^/┃ /"
    divider
    echo -e "请输入要暂停的行号（多个用空格隔开），直接回车取消："
    read -rp "行号： " line_nums

    if [[ -z "$line_nums" ]]; then
        echo "已取消暂停。"
        rm -f "$tmpfile"; pause; return
    fi

    if ! echo "$line_nums" | grep -Eq '^[0-9 ]+$'; then
        echo -e "${RED}✖ 输入格式错误，只能是数字和空格。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    sed_cmd=()
    for n in $line_nums; do
        sed_cmd+=("-e" "${n}s/^/# [PAUSED] /")
    done

    tmpfile_new="$(mktemp)"
    if sed "${sed_cmd[@]}" "$tmpfile" >"$tmpfile_new"; then
        crontab "$tmpfile_new"
        echo
        echo -e "${GREEN}✔ 暂停完成，当前 crontab：${RESET}"
        divider
        nl -ba "$tmpfile_new" | sed "s/^/┃ /"
        divider
    else
        echo -e "${RED}✖ 暂停时出错，crontab 未修改。${RESET}"
    fi

    rm -f "$tmpfile" "$tmpfile_new"
    pause
}

# ====== 恢复定时任务 ======
resume_cron() {
    show_header
    echo -e "${BOLD}${GREEN}▶ 恢复定时任务${RESET}"
    divider

    tmpfile="$(mktemp)"
    if ! crontab -l 2>/dev/null >"$tmpfile"; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    if ! grep -q "\[PAUSED\]" "$tmpfile"; then
        echo -e "${YELLOW}当前没有被标记为 [PAUSED] 的任务。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    echo -e "${CYAN}已暂停任务列表：${RESET}"
    nl -ba "$tmpfile" | grep "\[PAUSED\]" | sed "s/^/┃ /"
    divider
    echo -e "请输入要恢复的行号（多个用空格隔开），直接回车取消："
    read -rp "行号： " line_nums

    if [[ -z "$line_nums" ]]; then
        echo "已取消恢复。"
        rm -f "$tmpfile"; pause; return
    fi

    if ! echo "$line_nums" | grep -Eq '^[0-9 ]+$'; then
        echo -e "${RED}✖ 输入格式错误，只能是数字和空格。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    sed_cmd=()
    for n in $line_nums; do
        sed_cmd+=("-e" "${n}s/^[[:space:]]*#\s*\[PAUSED\]\s*//")
    done

    tmpfile_new="$(mktemp)"
    if sed "${sed_cmd[@]}" "$tmpfile" >"$tmpfile_new"; then
        crontab "$tmpfile_new"
        echo
        echo -e "${GREEN}✔ 恢复完成，当前 crontab：${RESET}"
        divider
        nl -ba "$tmpfile_new" | sed "s/^/┃ /"
        divider
    else
        echo -e "${RED}✖ 恢复时出错，crontab 未修改。${RESET}"
    fi

    rm -f "$tmpfile" "$tmpfile_new"
    pause
}

# ====== 今日执行情况（按日志显示成功/失败） ======
show_today_status() {
    show_header
    echo -e "${BOLD}${GREEN}⚡ 今日定时任务执行情况${RESET}"
    divider

    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${YELLOW}当前没有日志文件：${LOG_FILE}${RESET}"
        echo -e "只有通过本工具添加，并选择“启用执行日志”的任务才会记录。"
        divider
        pause
        return
    fi

    today="$(date +%F)"   # YYYY-MM-DD
    today_log="$(mktemp)"
    grep "^${today} " "$LOG_FILE" > "$today_log" 2>/dev/null || true

    if [[ ! -s "$today_log" ]]; then
        echo -e "${YELLOW}今日暂无任何执行记录（${today}）。${RESET}"
        rm -f "$today_log"
        divider
        pause
        return
    fi

    echo -e "${CYAN}日志文件：${LOG_FILE}${RESET}"
    echo -e "${CYAN}日期：${today}${RESET}"
    divider

    while IFS= read -r line; do
        status_field="$(echo "$line" | awk -F'|' '{gsub(/^ *| *$/,"",$2); print $2}')"
        if [[ "$status_field" == "OK" ]]; then
            printf "%b✅ %s%b\n" "$GREEN" "$line" "$RESET"
        else
            printf "%b❌ %s%b\n" "$RED" "$line" "$RESET"
        fi
    done < "$today_log"

    rm -f "$today_log"
    divider
    pause
}

# ====== 立即执行某条任务（手动测试） ======
run_task_once() {
    show_header
    echo -e "${BOLD}${GREEN}🚀 立即执行某条定时任务（手动测试）${RESET}"
    divider

    tmpfile="$(mktemp)"
    # 只取非空、非注释行（不包括暂停任务）
    crontab -l 2>/dev/null | sed '/^\s*$/d;/^\s*#/d' >"$tmpfile" 2>/dev/null || true

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}当前没有可执行的定时任务。${RESET}"
        rm -f "$tmpfile"
        divider
        pause
        return
    fi

    echo -e "${CYAN}当前可执行任务列表：${RESET}"
    nl -ba "$tmpfile" | sed "s/^/┃ /"
    divider
    read -rp "请输入要立即执行的行号（单个数字），直接回车取消： " n

    if [[ -z "$n" ]]; then
        echo "已取消执行。"
        rm -f "$tmpfile"; pause; return
    fi

    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✖ 请输入数字行号。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    chosen_line="$(sed -n "${n}p" "$tmpfile" 2>/dev/null || true)"
    if [[ -z "$chosen_line" ]]; then
        echo -e "${RED}✖ 行号不存在。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    # 命令部分：第 6 列及之后
    cmd_to_run="$(echo "$chosen_line" | awk '{for(i=6;i<=NF;i++){printf $i; if(i<NF)printf " "}}')"

    if [[ -z "$cmd_to_run" ]]; then
        echo -e "${RED}✖ 无法解析该行命令部分。${RESET}"
        rm -f "$tmpfile"; pause; return
    fi

    echo
    echo -e "选中任务：${YELLOW}${chosen_line}${RESET}"
    echo -e "即将执行命令：${CYAN}${cmd_to_run}${RESET}"
    echo
    echo -e "${BOLD}请选择执行模式：${RESET}"
    echo -e "  ${CYAN}1${RESET}) 模拟 cron 执行（非交互，stdin=/dev/null）"
    echo -e "  ${CYAN}2${RESET}) 普通执行（当前终端，可交互）"
    read -rp "选择执行模式 [默认 1]： " exec_mode

    [[ -z "$exec_mode" ]] && exec_mode=1

    read -rp "确认立即执行？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo "已取消执行。"
        rm -f "$tmpfile"; pause; return
    fi

    echo
    echo -e "${BLUE}▶ 开始执行...${RESET}"

    if [[ "$exec_mode" -eq 2 ]]; then
        # 普通执行：允许交互
        bash -c "$cmd_to_run"
    else
        # 模拟 cron：无交互，把 stdin 丢到 /dev/null
        bash -c "$cmd_to_run" </dev/null
    fi

    exit_code=$?

    echo
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✔ 执行成功（退出码：0）${RESET}"
    else
        echo -e "${RED}❌ 执行失败（退出码：${exit_code}）${RESET}"
        if [[ "$exec_mode" -eq 1 ]]; then
            echo -e "${YELLOW}提示：这是按 cron 的“非交互”方式执行的，如果脚本需要输入，很可能会失败。${RESET}"
        fi
    fi
    divider
    rm -f "$tmpfile"
    pause
}


# ====== 主菜单 ======
main_menu() {
    install_cron_if_needed

    while true; do
        show_header
        echo -e "${BOLD}请选择操作：${RESET}"
        echo
        echo -e "  ${CYAN}1${RESET}) ➕ 添加定时任务"
        echo -e "  ${CYAN}2${RESET}) 📋 查看当前定时任务"
        echo -e "  ${CYAN}3${RESET}) 🗑 删除定时任务"
        echo -e "  ${CYAN}4${RESET}) ⏸ 暂停定时任务"
        echo -e "  ${CYAN}5${RESET}) ▶ 恢复定时任务"
        echo -e "  ${CYAN}6${RESET}) ⚡ 今日执行情况"
        echo -e "  ${CYAN}7${RESET}) 🚀 立即执行某条任务"
        echo -e "  ${CYAN}0${RESET}) 🚪 退出"
        echo
        divider
        read -rp "请输入选项编号： " choice

        case "$choice" in
            1) add_cron ;;
            2) list_cron ;;
            3) delete_cron ;;
            4) pause_cron ;;
            5) resume_cron ;;
            6) show_today_status ;;
            7) run_task_once ;;
            0)
                echo
                echo -e "${GREEN}✔ 已退出，再见。${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}✖ 无效选项，请重新输入。${RESET}"
                sleep 1
                ;;
        esac
    done
}

main_menu
