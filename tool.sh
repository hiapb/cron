#!/usr/bin/env bash
# 简化版 Linux 定时任务管理脚本（基于 crontab）
# 功能：查看 / 添加 / 删除 当前用户的定时任务
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

# ====== 依赖检测 & 安装 ======

run_with_sudo_if_needed() {
    if [[ $EUID -eq 0 ]]; then
        # 已经是 root
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

    # 判断包管理器
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

    # 尝试启动 cron 服务（尽力而为，不强制要求成功）
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
    printf "%b┃%b %-43s %b┃%b\n" "$CYAN" "$RESET" "Linux 定时任务管理工具（简化版）" "$CYAN" "$RESET"
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
        # 允许直接回车返回空
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
            # 带行号显示
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
            minute=$(read_int_in_range "请输入分钟 (0-59)，如 5： " 0 59)
            if [[ -z "$minute" ]]; then
                echo -e "${RED}✖ 不能为空。${RESET}"
                pause
                return
            fi
            schedule="${minute} * * * *"
            ;;
        2)
            echo
            echo -e "${MAGENTA}▶ 每天执行${RESET}"
            hour=$(read_int_in_range "请输入小时 (0-23)，如 2： " 0 23)
            minute=$(read_int_in_range "请输入分钟 (0-59)，如 30： " 0 59)
            if [[ -z "$hour" || -z "$minute" ]]; then
                echo -e "${RED}✖ 时和分不能为空。${RESET}"
                pause
                return
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
                pause
                return
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
                pause
                return
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
                pause
                return
            fi
            schedule="${minute} ${hour} ${day} ${month} *"
            ;;
        6)
            echo
            echo -e "${MAGENTA}▶ 自定义 cron 表达式${RESET}"
            echo -e "格式：${YELLOW}分 时 日 月 周${RESET}，例如：${YELLOW}0 2 * * *${RESET}"
            read -rp "请输入完整 cron 表达式： " schedule
            schedule="$(echo "$schedule" | sed 's/^[ \t]*//;s/[ \t]*$//')"
            if [[ -z "$schedule" ]]; then
                echo -e "${RED}✖ 表达式不能为空。${RESET}"
                pause
                return
            fi
            ;;
        *)
            echo -e "${RED}✖ 无效选项。${RESET}"
            pause
            return
            ;;
    esac

    echo
    echo -e "${CYAN}📝 将使用时间表达式：${YELLOW}${schedule}${RESET}"
    read -rp "请输入要执行的命令（尽量写绝对路径）： " cmd
    cmd="$(echo "$cmd" | sed 's/^[ \t]*//;s/[ \t]*$//')"
    if [[ -z "$cmd" ]]; then
        echo -e "${RED}✖ 命令不能为空。${RESET}"
        pause
        return
    fi

    new_line="${schedule} ${cmd}"

    # 追加到当前 crontab
    tmpfile="$(mktemp)"
    if crontab -l 2>/dev/null >"$tmpfile"; then
        :
    else
        : >"$tmpfile"
    fi

    echo "$new_line" >>"$tmpfile"
    crontab "$tmpfile"
    rm -f "$tmpfile"

    echo
    divider
    echo -e "${GREEN}✔ 定时任务添加成功：${RESET}"
    echo -e "  ${BOLD}${new_line}${RESET}"
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
        rm -f "$tmpfile"
        pause
        return
    fi

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}当前没有任何定时任务。${RESET}"
        rm -f "$tmpfile"
        pause
        return
    fi

    echo -e "${CYAN}当前任务列表：${RESET}"
    nl -ba "$tmpfile" | sed "s/^/┃ /"
    divider
    echo -e "请输入要删除的行号（多个用空格隔开），直接回车取消："
    read -rp "行号： " line_nums

    if [[ -z "$line_nums" ]]; then
        echo "已取消删除。"
        rm -f "$tmpfile"
        pause
        return
    fi

    if ! echo "$line_nums" | grep -Eq '^[0-9 ]+$'; then
        echo -e "${RED}✖ 输入格式错误，只能是数字和空格。${RESET}"
        rm -f "$tmpfile"
        pause
        return
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

# ====== 主菜单 ======
main_menu() {
    install_cron_if_needed

    while true; do
        show_header
        echo -e "${BOLD}请选择操作：${RESET}"
        echo
        echo -e "  ${CYAN}1${RESET}) 📋 查看当前定时任务"
        echo -e "  ${CYAN}2${RESET}) ➕ 添加定时任务"
        echo -e "  ${CYAN}3${RESET}) 🗑 删除定时任务"
        echo -e "  ${CYAN}0${RESET}) 🚪 退出"
        echo
        divider
        read -rp "请输入选项编号： " choice

        case "$choice" in
            1) list_cron ;;
            2) add_cron ;;
            3) delete_cron ;;
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
