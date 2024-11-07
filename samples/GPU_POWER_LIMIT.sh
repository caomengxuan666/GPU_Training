#!/bin/bash

# 检查nvidia-smi是否可用
if ! nvidia-smi > /dev/null 2>&1; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 错误：未找到nvidia-smi命令或GPU不可用！" | tee -a "$LOG_FILE"
    exit 1
fi

# 该脚本由伟大的开源程序员曹梦轩贡献
# ps aux | grep 'monitor_gpu' | grep -v 'grep'   使用这个指令可以找到后台运行的进程，友情提示。

# 输出启动信息到控制台
echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU 温控监测脚本启动..." | tee /dev/tty

# 参数设置
UPPER_TEMP=85                # 触发降频的温度上限
LOWER_TEMP=75                # 恢复正常频率的温度下限
LOW_POWER=150                # 降频时的功率上限（单位：瓦）
HIGH_POWER=400               # 恢复正常频率时的功率上限（单位：瓦）
LOG_FILE="/var/log/gpu_monitor.log"  # 日志文件路径
LOG_INTERVAL=120             # 正常温度时打印日志的间隔（次）,对应30s检测一次，一个小时一条日志
DAY_INTERVAL=86400           # 每 24 小时打印日期

# 确保日志文件可写
touch "$LOG_FILE" && chmod 644 "$LOG_FILE"

# 初始化计数器
normal_temp_count=0
trigger_count=0             # 计数器：记录温度正常轮次
low_power_triggered=false  # 标志符：是否已经触发过降频

# 获取并显示初始温度
echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU 初始温度：" | tee -a "$LOG_FILE"
nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits | while read -r index temp; do
    echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU $index 初始温度为 ${temp}°C" | tee -a "$LOG_FILE"
done

# 后台运行脚本的循环
monitor_gpu_temp() {
    while true; do
        # 获取每个GPU的温度，逐行处理
        nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits | while read -r index temp; do
            # 如果温度超过上限，输出信息并调整功率
            if (( temp > UPPER_TEMP )); then
                # 如果温度超过上限，触发降频
                if [ "$low_power_triggered" = false ]; then
                    # 输出信息到日志文件
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU $index 温度为 ${temp}°C，开始降频至 ${LOW_POWER}W..." | tee -a "$LOG_FILE"
                    # 输出信息到控制台
                    echo "警告：GPU $index 温度过高！当前温度为 ${temp}°C，降频至 ${LOW_POWER}W。"
                    # 设置功率上限为降频值
                    nvidia-smi -i $index -pl $LOW_POWER
                    low_power_triggered=true  # 标记降频已触发
                fi
                # 重置正常计数器
                trigger_count=0
            # 如果温度降至恢复温度以下，恢复正常功率
            elif (( temp < LOWER_TEMP )); then
                # 如果之前触发过降频，恢复功率
                if [ "$low_power_triggered" = true ]; then
                    # 输出信息到日志文件
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU $index 温度已降至 ${temp}°C，恢复功率上限至 ${HIGH_POWER}W..." | tee -a "$LOG_FILE"
                    # 输出信息到控制台
                    echo "信息：GPU $index 温度恢复正常，当前温度为 ${temp}°C，恢复功率上限至 ${HIGH_POWER}W。"
                    # 恢复功率上限为正常值
                    nvidia-smi -i $index -pl $HIGH_POWER
                    low_power_triggered=false  # 重置标记，表示恢复正常
                fi
                # 重置正常计数器
                trigger_count=0
            else
                # 如果温度在正常范围内，增加计数器
                if [ "$trigger_count" -lt 10 ]; then
                    trigger_count=$((trigger_count + 1))
                fi
            fi

            # 如果 10轮都没有触发降频，显示正常温度
            if [ "$trigger_count" -ge 10 ]; then
                if [ "$low_power_triggered" = false ]; then
                    # 输出信息到日志文件（正常状态时）
                    if (( normal_temp_count % LOG_INTERVAL == 0 )); then
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): GPU $index 温度为 ${temp}°C，维持当前功率设置。" | tee -a "$LOG_FILE"
                    fi
                    normal_temp_count=$((normal_temp_count + 1))
                fi
            fi
        done
        # 等待30秒
        sleep 30
    done
}

# 启动后台运行温控检测
monitor_gpu_temp &

# 确保后台进程开始时，立即在控制台显示
echo "$(date '+%Y-%m-%d %H:%M:%S'): 启动完成，开始GPU温度监控..." | tee /dev/tty
