#!/bin/bash

# 脚本在遇到错误或管道错误时立即退出
set -eo pipefail

# --- 依赖检查与自动安装函数 ---
check_dependencies() {
    # ... (这部分与原脚本相同，为了简洁此处省略) ...
    local missing_deps_pm=()
    local missing_speedtest=false
    # 检查所有需要的命令 (已将 iperf3 替换为 speedtest)
    for cmd in sysbench fio speedtest jq curl nproc lsb_release date grep rm top awk; do # 新增 top 和 awk 检查
        if ! command -v "$cmd" &> /dev/null; then
            if [ "$cmd" = "lsb_release" ]; then
                missing_deps_pm+=("lsb-release")
            elif [ "$cmd" = "speedtest" ]; then
                missing_speedtest=true
            elif [ "$cmd" = "top" ]; then
                # top 通常包含在 procps 或 procps-ng 包中
                if command -v apt-get &> /dev/null; then
                    missing_deps_pm+=("procps")
                else
                    missing_deps_pm+=("procps-ng")
                fi
            else
                missing_deps_pm+=("$cmd")
            fi
        fi
    done

    # 汇总所有缺失的依赖项用于提示
    local all_missing_deps=("${missing_deps_pm[@]}")
    if [ "$missing_speedtest" = true ]; then
        all_missing_deps+=("speedtest")
    fi

    if [ ${#all_missing_deps[@]} -ne 0 ]; then
        echo "检测到以下依赖缺失: ${all_missing_deps[*]}"
        read -p "是否尝试自动安装这些依赖? (y/n): " choice
        case "$choice" in
          y|Y )
            echo "正在尝试安装依赖..."
            local SUDO_CMD=""
            if [ "$(id -u)" -ne 0 ]; then
                SUDO_CMD="sudo"
            fi

            # 1. 安装通过常规包管理器可以安装的依赖
            if [ ${#missing_deps_pm[@]} -ne 0 ]; then
                if command -v apt-get &> /dev/null; then
                    $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y "${missing_deps_pm[@]}"
                elif command -v yum &> /dev/null; then
                    $SUDO_CMD yum install -y "${missing_deps_pm[@]}"
                elif command -v dnf &> /dev/null; then
                    $SUDO_CMD dnf install -y "${missing_deps_pm[@]}"
                else
                    echo "错误: 无法识别您的包管理器 (apt/yum/dnf)，无法自动安装 ${missing_deps_pm[*]}。"
                fi
            fi

            # 2. 特殊处理 Speedtest 的安装 (兼容 CentOS, Ubuntu, Debian)
            if [ "$missing_speedtest" = true ]; then
                echo "正在安装 Speedtest CLI..."
                if ! command -v curl &> /dev/null; then
                    echo "错误: 安装 Speedtest 需要 curl，请先手动安装 curl。"
                    exit 1
                fi
                # 判断系统是 Debian系 还是 RedHat系
                if command -v apt-get &> /dev/null; then # Debian/Ubuntu
                    curl -s https://install.speedtest.net/app/cli/install.deb.sh | $SUDO_CMD bash
                    $SUDO_CMD apt-get install -y speedtest
                elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then # CentOS/RHEL/Fedora
                    curl -s https://install.speedtest.net/app/cli/install.rpm.sh | $SUDO_CMD bash
                    $SUDO_CMD yum install -y speedtest
                else
                    echo "错误: 无法为您的操作系统自动安装 Speedtest。请访问 https://www.speedtest.net/apps/cli 手动安装。"
                fi
            fi

            # 最终检查以确保所有依赖安装成功
            for cmd in sysbench fio speedtest jq curl nproc lsb_release date grep rm top awk; do
                if ! command -v "$cmd" &> /dev/null; then
                    local pkg_name="$cmd"
                    if [ "$cmd" = "lsb_release" ]; then pkg_name="lsb-release"; fi
                    if [ "$cmd" = "speedtest" ]; then pkg_name="Speedtest CLI"; fi
                    echo "错误: 依赖 $pkg_name 自动安装失败，请手动安装。"
                    exit 1
                fi
            done
            echo "依赖安装成功。"
            ;;
          * )
            echo "操作已取消。请在手动安装依赖后重新运行脚本。"
            exit 1
            ;;
        esac
    fi
}

display_server_info() {
    echo "正在获取服务器信息..."
    # 使用ipinfo.io获取公网信息，jq解析
    IP_INFO=$(curl -s ipinfo.io)
    
    # 基础信息
    HOSTNAME=$(hostname)
    OS_VERSION=$(lsb_release -ds)
    LINUX_VERSION=$(uname -r)
    CPU_ARCH=$(uname -m)
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo | uniq | cut -d ':' -f2- | sed 's/^[ \t]*//')
    CPU_CORES=$(nproc)
    CPU_FREQ=$(grep 'cpu MHz' /proc/cpuinfo | head -n1 | awk '{print $4}')" MHz"
    
    # 实时状态
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    SYS_LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
    MEM_INFO=$(free -m | grep Mem)
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_USAGE=$(awk "BEGIN {printf \"%.2f%%\", $MEM_USED/$MEM_TOTAL*100}")
    SWAP_INFO=$(free -m | grep Swap)
    SWAP_TOTAL=$(echo "$SWAP_INFO" | awk '{print $2}')
    SWAP_USED=$(echo "$SWAP_INFO" | awk '{print $3}')
    SWAP_USAGE=$(if [ "$SWAP_TOTAL" -eq 0 ]; then echo "0%"; else awk "BEGIN {printf \"%.2f%%\", $SWAP_USED/$SWAP_TOTAL*100}"; fi)
    DISK_INFO=$(df -h / | awk 'NR==2')
    DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
    DISK_USAGE=$(echo "$DISK_INFO" | awk '{print $5}')
    
    # 网络信息
    NET_DATA=$(ip -s link | grep "RX:" -A 3 | grep -v "RX:" | awk '{sum1+=$1; sum2+=$5} END {print sum1, sum2}')
    TOTAL_RX=$(numfmt --to=iec --format="%.2f" $(echo "$NET_DATA" | awk '{print $1}'))
    TOTAL_TX=$(numfmt --to=iec --format="%.2f" $(echo "$NET_DATA" | awk '{print $2}'))
    NET_ALGO=$(sysctl net.ipv4.tcp_congestion_control | awk -F '= ' '{print $2}')
    
    # 公网信息
    OPERATOR=$(echo "$IP_INFO" | jq -r '.org // "N/A"')
    IPV4_ADDR=$(echo "$IP_INFO" | jq -r '.ip // "N/A"')
    IPV6_ADDR=$(curl -s 6.ipw.cn || echo "N/A")
    DNS_SERVERS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    LOCATION=$(echo "$IP_INFO" | jq -r '(.city // "") + ", " + (.region // "") + ", " + (.country // "")')
    SYS_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
    UPTIME=$(uptime -p)

    # 格式化输出 (添加了边框和标题)
    echo ""
    echo "----------------------"
    printf "%-14s: %s\n" "主机名" "$HOSTNAME"
    printf "%-14s: %s\n" "系统版本" "$OS_VERSION"
	echo "----------------------"
    printf "%-14s: %s\n" "Linux版本" "$LINUX_VERSION"
    printf "%-14s: %s\n" "CPU架构" "$CPU_ARCH"
    printf "%-14s: %s\n" "CPU型号" "$CPU_MODEL"
    printf "%-14s: %s\n" "CPU核心数" "$CPU_CORES"
    printf "%-14s: %s\n" "CPU频率" "$CPU_FREQ"
	echo "----------------------"
    printf "%-14s: %s\n" "CPU占用" "$CPU_USAGE"
    printf "%-14s: %s\n" "系统负载" "$SYS_LOAD"
    printf "%-14s: %s / %sMB (%s)\n" "物理内存" "$MEM_USED" "$MEM_TOTAL" "$MEM_USAGE"
    printf "%-14s: %s / %sMB (%s)\n" "虚拟内存" "$SWAP_USED" "$SWAP_TOTAL" "$SWAP_USAGE"
    printf "%-14s: %s / %s (%s)\n" "硬盘占用" "$DISK_USED" "$DISK_TOTAL" "$DISK_USAGE"
	echo "----------------------"
    printf "%-14s: %s\n" "总接收" "$TOTAL_RX"
    printf "%-14s: %s\n" "总发送" "$TOTAL_TX"
	echo "----------------------"
    printf "%-14s: %s\n" "网络算法" "$NET_ALGO"
	echo "----------------------"
    printf "%-14s: %s\n" "运营商" "$OPERATOR"
    printf "%-14s: %s\n" "IPv4地址" "$IPV4_ADDR"
    printf "%-14s: %s\n" "IPv6地址" "$IPV6_ADDR"
    printf "%-14s: %s\n" "DNS地址" "$DNS_SERVERS"
    printf "%-14s: %s\n" "地理位置" "$LOCATION"
    printf "%-14s: %s\n" "系统时间" "$SYS_TIME"
	echo "----------------------"
    printf "%-14s: %s\n" "运行时长" "$UPTIME"
}


### NEW ###
# --- 服务器超售检测函数 ---
check_overselling() {
    echo ">>> CPU 资源争抢 (超售) 检测" | tee -a "$LOG_FILE"
    echo "正在检测 CPU Steal Time... (这在虚拟化环境中是关键指标)" | tee -a "$LOG_FILE"

    # 使用 top 命令在批处理模式下运行1次，然后提取 %st (steal time)
    # 对于多核CPU，top会显示一个总的百分比
    steal_time=$(top -b -n 1 | grep '%Cpu(s)' | awk '{print $10}' | sed 's/,/./')

    if [[ -z "$steal_time" ]]; then
        # 如果无法获取到值，可能是一些特殊的系统（如物理机），steal time为0
        steal_time="0.0"
    fi

    # 将浮点数转换为整数进行比较
    steal_time_int=$(printf "%.0f" "$steal_time")

    echo "CPU Steal Time: ${steal_time}%" | tee -a "$LOG_FILE"

    local score=0
    local conclusion=""

    if (( steal_time_int < 1 )); then
        score=10
        conclusion="表现优异。CPU几乎没有资源争抢，性能稳定，很可能不是超售机器或邻居负载极低。"
    elif (( steal_time_int < 3 )); then
        score=8
        conclusion="表现良好。有轻微的CPU资源争抢，但在可接受范围内，对绝大多数应用无明显影响。"
    elif (( steal_time_int < 5 )); then
        score=6
        conclusion="表现中等。存在一定的CPU资源争抢，可能在高峰期对性能敏感型应用造成影响。"
    elif (( steal_time_int < 10 )); then
        score=4
        conclusion="表现较差。存在明显的CPU资源争抢，表明宿主机负载较高，有超售嫌疑，性能会受到影响。"
    else
        score=1
        conclusion="表现极差！CPU资源争抢严重，宿主机严重超售，性能会受到严重影响，不建议用于生产环境。"
    fi

    echo "超售检测评分: ${score}/10" | tee -a "$LOG_FILE"
    echo "结论: ${conclusion}" | tee -a "$LOG_FILE"
}
### NEW END ###

#输出服务器信息
display_server_info

# 脚本开始时执行检查
check_dependencies

echo "优纪服务器性能AI分析 V 2.1版本 (已优化)"
echo "------------------------------------"

# --- 日志文件管理 (使用时间戳) ---
LOG_FILE="benchmark_$(date +%Y%m%d_%H%M%S).log"
echo "本次测试的日志将保存到: $LOG_FILE"
echo ""

# --- 交互式参数输入 ---
echo "--- 服务器性能测试脚本配置 ---"
read -p "是否进行 Speedtest 公网测速? (y/n) [默认为 n]: " RUN_SPEEDTEST
read -p "请输入 AI 分析的 API Key (直接回车可跳过 AI 分析): " API_KEY

# 只有在输入了 API Key 的情况下才询问模型
if [[ -n "$API_KEY" ]]; then
    read -p "请输入 AI 模型名称 [默认为 Qwen/QwQ-32B]: " model_input
    AI_MODEL=${model_input:-"Qwen/QwQ-32B"}
fi
echo "--- 配置完成，测试即将开始 ---"
echo ""


# --- 脚本主体 ---
echo "========== 服务器性能压测开始 ==========" | tee "$LOG_FILE"
echo "测试时间: $(date)" | tee -a "$LOG_FILE"
echo "操作系统: $(lsb_release -d | cut -f2)" | tee -a "$LOG_FILE"
echo "内核版本: $(uname -r)" | tee -a "$LOG_FILE"
echo "架构: $(uname -m)" | tee -a "$LOG_FILE"
echo "CPU 核心数: $(nproc)" | tee -a "$LOG_FILE"
echo "CPU 型号: $(grep 'model name' /proc/cpuinfo | uniq | cut -d ':' -f2-)" | tee -a "$LOG_FILE"
echo "物理内存: $(free -h | grep Mem | awk '{print $2}')" | tee -a "$LOG_FILE"
echo "磁盘信息:" | tee -a "$LOG_FILE"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"

### CPU 压测
echo ">>> CPU 单线程压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=1 run | tee -a "$LOG_FILE"

echo ">>> CPU 多线程压测 (sysbench, 使用 $(nproc) 线程)" | tee -a "$LOG_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | tee -a "$LOG_FILE"

# --- 在CPU测试后执行超售检测 ---
check_overselling | tee -a "$LOG_FILE"

echo ">>> CPU AES加解密性能测试 (openssl)" | tee -a "$LOG_FILE"
openssl speed -elapsed -evp aes-256-gcm | tee -a "$LOG_FILE"

### 线程调度压测
echo ">>> 线程调度压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench threads --threads=64 --thread-yields=100 --thread-locks=4 run | tee -a "$LOG_FILE"

### 内存压测
echo ">>> 内存压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench memory --memory-block-size=4K --memory-total-size=4G run | tee -a "$LOG_FILE"


### OPTIMIZED ###
# ==================== 硬盘 IO 测试 (sysbench, 优化流程) ====================
echo ">>> 磁盘 IO 压测 (sysbench, 准备 1G 测试文件...)" | tee -a "$LOG_FILE"
# 为兼容新版 sysbench，进入专用目录执行测试
mkdir -p test-data
cd test-data

# 优化流程: 准备一次，运行多次，清理一次
sysbench fileio --file-total-size=1G --threads=4 prepare > /dev/null

echo ">>> 磁盘 IO 压测 (sysbench, 随机读写, 4线程, 30秒)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=1G --file-test-mode=rndrw --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=30 run | tee -a "../$LOG_FILE"

echo ">>> 磁盘 IO 压测 (sysbench, 顺序写, 4线程, 30秒)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=1G --file-test-mode=seqwr --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=30 run | tee -a "../$LOG_FILE"

echo ">>> 磁盘 IO 压测 (sysbench, 顺序读, 4线程, 30秒)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=1G --file-test-mode=seqrd --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=30 run | tee -a "../$LOG_FILE"

echo ">>> 磁盘 IO 压测 (sysbench, 清理测试文件...)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=1G cleanup > /dev/null

# 返回上级目录并清理文件夹
cd ..
rm -rf test-data
# ==================== 优化结束 ====================
### OPTIMIZED END ###


### 磁盘 IO 压测 (fio)
echo ">>> 磁盘 IO 压测 (fio, 随机写)" | tee -a "$LOG_FILE"
fio --name=randwrite --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k --direct=1 --size=512M --numjobs=4 --runtime=10 --time_based --group_reporting | tee -a "$LOG_FILE"
# 自动清理 fio 生成的测试文件
rm -f randwrite.*

### 公网网速压测 (Speedtest)
case "$RUN_SPEEDTEST" in
  y|Y )
    echo ">>> 公网网速压测 (Speedtest)" | tee -a "$LOG_FILE"
    # 使用 --accept-license 和 --accept-gdpr 来避免脚本因交互而暂停
    speedtest --accept-license --accept-gdpr | tee -a "$LOG_FILE"
    ;;
  * )
    echo ">>> 公网网速压测 (Speedtest) 跳过" | tee -a "$LOG_FILE"
    ;;
esac

### AI 分析报告
if [[ -n "$API_KEY" ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo ">>> 正在使用模型 $AI_MODEL 生成 AI 分析报告..." | tee -a "$LOG_FILE"

    # --- AI 服务配置 ---
    API_URL="https://api.siliconflow.cn/v1/chat/completions"

    # 定义 AI 系统 Prompt (优化为纯文本输出，并增加了超售检测分析)
    AI_PROMPT='你是一名顶级的服务器性能分析专家。请根据以下压测日志，撰写一份专业、清晰、适合在终端直接阅读的纯文本「服务器性能体检报告」。
请严格遵守以下格式要求，不要使用任何 Markdown 语法 (如 ##, *, |, > 等)。

1.  **章节标题**: 使用 `===== [章节标题] =====` 格式，例如 `===== 1. 整体体检结论 =====`。
2.  **分项格式**: 对于分项指标，必须使用三行格式：
    指标: [指标名称]
    数据: [关键数据和表现]
    结论: [结论和分析]
3.  **列表**: 使用 `  - ` (两个空格+横杠) 开头的缩进列表。
4.  **布局**: 适当使用空行来分隔内容，保持报告整洁。

报告必须包含以下部分：

1.  **整体体检结论**:
    - 综合一句话总结。
    - 综合性能评分 (100分制) 及简要依据。

2.  **分项指标分析**:
    - CPU 性能 (单线程、多线程、加解密性能)
    - CPU 资源争抢 (超售) 检测  <-- 新增分析项
    - 系统调度性能
    - 内存带宽
    - 磁盘 IO (随机与顺序)
    - 网络吞吐

3.  **典型场景性能估算**:
    - 推算作为数据库、内存服务器、Web/API服务器、文件服务器的大致性能范围 (QPS, TPS等)。
    - 必须明确指出这只是理论推测。

4.  **应用场景建议**:
    - 列出最适合的应用场景。
    - 列出不太适合的应用场景。

5.  **瓶颈与优化建议**:
    - 指出最可能的性能短板。
    - 给出具体、可行的优化建议 (硬件/软件/架构)。'

    # 为了让AI更好地分析，我们在发送日志前，先把AI分析这部分从日志中排除
    temp_log_for_ai=$(grep -v ">>> AI 分析报告" "$LOG_FILE" | grep -v "正在生成 AI 分析报告")

    # 将日志内容和Prompt组合成发送给API的user content
    USER_CONTENT="以下是压测日志，请根据此日志撰写报告：\n\n$temp_log_for_ai"

    # 使用 jq 构建 JSON payload，更安全、清晰
    json_payload=$(jq -n --arg model "$AI_MODEL" --arg system_prompt "$AI_PROMPT" --arg user_content "$USER_CONTENT" \
      '{
        "model": $model,
        "messages": [
          {"role": "system", "content": $system_prompt},
          {"role": "user", "content": $user_content}
        ]
      }')

    analysis=$(curl -s "$API_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$json_payload" | jq -r '.choices[0].message.content')

    echo "" | tee -a "$LOG_FILE"
    echo "---------------- AI 性能体检报告 ----------------" | tee -a "$LOG_FILE"
    echo "$analysis" | tee -a "$LOG_FILE"
    echo "------------------------------------------------" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "========== 压测完成，日志保存至 $LOG_FILE =========="
