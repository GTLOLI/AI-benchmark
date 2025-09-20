#!/bin/bash

# 脚本在遇到错误或管道错误时立即退出
set -eo pipefail

# --- 依赖检查与自动安装函数 ---
check_dependencies() {
    local missing_deps=()
    # 检查所有需要的命令
    for cmd in sysbench fio iperf3 jq curl nproc lsb_release date grep rm; do
        if ! command -v "$cmd" &> /dev/null; then
            # 特殊处理 lsb_release，它的包名是 lsb-release
            if [ "$cmd" = "lsb_release" ]; then
                missing_deps+=("lsb-release")
            else
                missing_deps+=("$cmd")
            fi
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "检测到以下依赖缺失: ${missing_deps[*]}"
        read -p "是否尝试自动安装这些依赖? (y/n): " choice
        case "$choice" in
          y|Y )
            echo "正在尝试安装依赖..."
            # 判断当前用户是否为 root，如果不是，则在命令前加上 sudo
            local SUDO_CMD=""
            if [ "$(id -u)" -ne 0 ]; then
                SUDO_CMD="sudo"
            fi

            if command -v apt-get &> /dev/null; then
                $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y "${missing_deps[@]}"
            elif command -v yum &> /dev/null; then
                $SUDO_CMD yum install -y "${missing_deps[@]}"
            elif command -v dnf &> /dev/null; then
                $SUDO_CMD dnf install -y "${missing_deps[@]}"
            else
                echo "错误: 无法识别您的包管理器 (apt/yum/dnf)，请手动安装依赖。"
                exit 1
            fi
            # 再次检查以确保安装成功
            for cmd in sysbench fio iperf3 jq curl nproc lsb_release date grep rm; do
                if ! command -v "$cmd" &> /dev/null; then
                    # 从包名反查对应的命令名进行提示
                    local check_cmd="$cmd"
                    if [ "$cmd" = "lsb-release" ]; then
                        check_cmd="lsb_release"
                    fi
                    echo "错误: 依赖 $check_cmd 自动安装失败，请手动安装。"
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

# 脚本开始时执行检查
check_dependencies

echo "优纪服务器性能AI分析 V 1.6版本"
echo "------------------------------------"

# --- 日志文件管理 (使用时间戳) ---
LOG_FILE="benchmark_$(date +%Y%m%d_%H%M%S).log"
echo "本次测试的日志将保存到: $LOG_FILE"
echo ""

# --- 交互式参数输入 ---
echo "--- 服务器性能测试脚本配置 ---"
read -p "请输入 iperf3 服务器 IP (直接回车可跳过网络测试): " SERVER_IP
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

echo "" | tee -a "$LOG_FILE"

### CPU 压测
echo ">>> CPU 单线程压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=1 run | tee -a "$LOG_FILE"

echo ">>> CPU 多线程压测 (sysbench, 使用 $(nproc) 线程)" | tee -a "$LOG_FILE"
sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run | tee -a "$LOG_FILE"

### 线程调度压测
echo ">>> 线程调度压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench threads --threads=64 --thread-yields=100 --thread-locks=4 run | tee -a "$LOG_FILE"

### 内存压测
echo ">>> 内存压测 (sysbench)" | tee -a "$LOG_FILE"
sysbench memory --memory-block-size=4K --memory-total-size=4G run | tee -a "$LOG_FILE"


# ==================== 关键改动区域 ====================
### 磁盘 IO 压测 (sysbench)
echo ">>> 磁盘 IO 压测 (sysbench, 准备文件...)" | tee -a "$LOG_FILE"
# 为兼容新版 sysbench，进入专用目录执行测试
mkdir -p test-data
cd test-data

sysbench fileio --file-total-size=2G --file-test-mode=rndrw --file-extra-flags=direct --file-fsync-freq=0 --threads=4 prepare > /dev/null

echo ">>> 磁盘 IO 压测 (sysbench, 随机读写, 4线程)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=2G --file-test-mode=rndrw --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=60 --report-interval=10 run | tee -a "../$LOG_FILE"

echo ">>> 磁盘 IO 压测 (sysbench, 顺序写)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=2G --file-test-mode=seqwr --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=60 --report-interval=10 run | tee -a "../$LOG_FILE"

echo ">>> 磁盘 IO 压测 (sysbench, 顺序读)" | tee -a "../$LOG_FILE"
sysbench fileio --file-total-size=2G --file-test-mode=seqrd --file-extra-flags=direct --file-fsync-freq=0 --threads=4 --time=60 --report-interval=10 run | tee -a "../$LOG_FILE"

# 清理测试文件并返回上级目录
sysbench fileio --file-total-size=2G cleanup > /dev/null
cd ..
rm -rf test-data
# ==================== 改动结束 ====================


### 磁盘 IO 压测 (fio)
echo ">>> 磁盘 IO 压测 (fio, 随机写)" | tee -a "$LOG_FILE"
fio --name=randwrite --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k --direct=1 --size=512M --numjobs=4 --runtime=10 --time_based --group_reporting | tee -a "$LOG_FILE"
# 自动清理 fio 生成的测试文件
rm -f randwrite.*

### 网络吞吐压测 (iperf3)
if [[ -n "$SERVER_IP" ]]; then
    echo ">>> 网络吞吐压测 (iperf3) -> $SERVER_IP" | tee -a "$LOG_FILE"
    iperf3 -c "$SERVER_IP" -t 30 | tee -a "$LOG_FILE"
else
    echo ">>> 网络吞吐压测 (iperf3) 跳过" | tee -a "$LOG_FILE"
fi

### AI 分析报告
if [[ -n "$API_KEY" ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo ">>> 正在使用模型 $AI_MODEL 生成 AI 分析报告..." | tee -a "$LOG_FILE"

    # --- AI 服务配置 ---
    API_URL="https://api.siliconflow.cn/v1/chat/completions"

    # 定义 AI 系统 Prompt (优化为纯文本输出)
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
    - CPU 性能 (单线程与多线程)
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