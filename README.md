# AutoBench-AI: 智能服务器性能 AI 分析脚本
### AI-Powered Server Benchmark & Analysis Script


一份强大且智能的 Linux 服务器综合性能评测脚本。它不仅能执行专业的基准测试，更能利用大语言模型（LLM）对测试结果进行深度分析，自动生成一份专业、易读的服务器“体检报告”。

This is a powerful and intelligent benchmark script for Linux servers. It not only runs professional-grade benchmarks but also leverages a Large Language Model (LLM) to provide an in-depth analysis of the results, automatically generating a human-readable server "Health Check Report".

---

### 核心特性 ✨

* **全方位性能测试**: 覆盖 CPU（单核/多核）、内存带宽、磁盘 I/O（随机/顺序）、系统线程调度及网络吞吐量测试。
* **AI 智能分析**: 连接 AI 模型，将冰冷的测试数据转化为通俗易懂的结论、场景建议和优化方案。
* **自动化依赖处理**: 脚本自动检测并提示安装所需的测试工具（如 `sysbench`, `fio`），支持 `apt`, `yum`, `dnf` 包管理器。
* **终端友好输出**: 经过精心优化的纯文本报告格式，在任何 SSH 终端下都能完美显示，清晰整洁。
* **高度兼容**: 在主流 Linux 发行版（Debian, Ubuntu, CentOS等）上经过测试，兼容性良好。
* **开箱即用**: 无需复杂配置，下载即可运行。

### 报告输出示例

告别杂乱的原始数据，获得由 AI 生成的、结构清晰的专业分析报告。

```text
---------------- AI 性能体检报告 ----------------
===== 1. 整体体检结论 =====

综合来看，该服务器CPU性能强劲，内存带宽优秀，但磁盘随机IO性能较弱，是一台典型的计算密集型服务器。
综合性能评分: 82分 (CPU和内存表现突出，但受限于磁盘IO性能)


===== 2. 分项指标分析 =====

指标: CPU 性能
数据: 单线程 events/s: 2105.11, 多线程 events/s: 16755.33
结论: CPU性能非常出色，无论是单核计算还是多核并行处理能力都处于较高水平。

指标: 磁盘 IO
数据: 随机写 IOPS: 5497, 顺序写吞吐: 153.2MiB/s
结论: 随机IO性能是主要短板，远低于企业级SSD标准，不适合高并发数据库。顺序读写尚可。

... (其他项目以此类推)


===== 4. 应用场景建议 =====

  - 最适合的场景:
    - 高并发Web/API服务器集群
    - 大数据分析与科学计算
    - CI/CD编译构建服务器

  - 不太适合的场景:
    - 高并发交易型数据库 (OLTP)
    - 大型搜索引擎或数据仓库


===== 5. 瓶颈与优化建议 =====

最主要的性能短板在于磁盘随机IO性能过低。

  - 具体优化建议:
    - [硬件升级] 更换为NVMe SSD是解决性能瓶颈最根本的方案。
    - [软件调优] 针对数据库，增大缓存以减少磁盘读写。
    - [架构调整] 考虑读写分离或使用分布式存储方案来分摊IO压力。

------------------------------------------------
```

### 快速开始 🚀

1.  **克隆仓库**
    ```bash
    git clone [https://github.com/你的用户名/你的仓库名.git](https://github.com/你的用户名/你的仓库名.git)
    cd 你的仓库名
    ```
    或者直接下载脚本文件:
    ```bash
    curl -O [https://raw.githubusercontent.com/你的用户名/你的仓库名/main/benchmark.sh](https://raw.githubusercontent.com/你的用户名/你的仓库名/main/benchmark.sh)
    ```

2.  **授予执行权限**
    ```bash
    chmod +x benchmark.sh
    ```

3.  **执行脚本**

    * **基础测试 (不含AI分析和网络)**
        ```bash
        ./benchmark.sh
        ```

    * **完整测试 (包含AI分析和网络)**
        ```bash
        # 将 YOUR_API_KEY 替换为你的AI模型API Key
        # 将 IPERF3_SERVER_IP 替换为你的 iperf3 服务器地址
        ./benchmark.sh -k YOUR_API_KEY -s IPERF3_SERVER_IP
        ```

### 使用说明

#### 依赖工具

脚本会自动检测以下依赖，如果缺失会提示您自动安装：
`sysbench`, `fio`, `iperf3`, `jq`, `curl`, `nproc`, `lsb_release`

#### 命令行参数

* `-k <API_KEY>`: 设置用于 AI 分析的 API Key。
* `-s <SERVER_IP>`: 设置用于网络测试的 `iperf3` 服务器 IP 地址。
* `-m <MODEL_NAME>`: (可选) 指定 AI 模型名称，默认为 `Qwen/QwQ-32B`。
* `-h`: 显示帮助信息。

### 自定义配置

您可以直接编辑 `benchmark.sh` 脚本头部的全局配置区域，来调整各项测试的参数，例如：

* `CPU_MAX_PRIME`: CPU 测试强度。
* `DISK_TEST_SIZE`: 磁盘测试文件的大小。
* `DISK_TEST_TIME`: 磁盘测试的持续时间。

### 测试工具说明

本脚本通过调用业界标准的开源工具来完成性能评估：

* **Sysbench**: 用于对 CPU、内存、线程调度和磁盘 I/O 进行综合性基准测试。
* **FIO (Flexible I/O Tester)**: 用于提供更精细化的磁盘 I/O 性能测试，作为 Sysbench 的补充。
* **iperf3**: 用于测量网络带宽和吞吐量。

### 贡献

欢迎任何形式的贡献！如果您有好的想法、建议或发现了 Bug，请随时提交 Pull Request 或创建 Issue。
