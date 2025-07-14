#!/bin/bash

# 智能下载工具 - 支持HTTP/FTP协议，断点续传和自动完成检测
# 使用方法: smart_downloader.sh [URL] [选项]

# 默认配置
URL=""
TARGET_DIR="downloads"
CHECK_INTERVAL=600  # 检查间隔(秒)
SIZE_TOLERANCE=5    # 文件大小误差容忍度(%)
LOG_FILE="download.log"
VERBOSE=0
BUFFER_SIZE=8192    # 输出缓冲区大小(字节)

# 帮助信息
function show_help {
    echo "用法: $0 [选项] <URL>"
    echo "选项:"
    echo "  -d, --directory <目录>   指定下载目录 (默认: downloads)"
    echo "  -i, --interval <秒>      指定检查间隔 (默认: 600秒)"
    echo "  -t, --tolerance <百分比> 指定文件大小误差容忍度 (默认: 5%)"
    echo "  -l, --log <文件>        指定日志文件 (默认: download.log)"
    echo "  -v, --verbose           启用详细输出"
    echo "  -b, --buffer <大小>     设置输出缓冲区大小 (默认: 8192字节)"
    echo "  -h, --help              显示此帮助信息"
    exit 1
}

# 日志函数
function log {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directory)
            TARGET_DIR="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -t|--tolerance)
            SIZE_TOLERANCE="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -b|--buffer)
            BUFFER_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            if [[ -z "$URL" ]]; then
                URL="$1"
                shift
            else
                echo "错误: 未知参数 $1"
                show_help
            fi
            ;;
    esac
done

# 验证URL
if [[ -z "$URL" ]]; then
    echo "错误: 必须指定下载URL"
    show_help
fi

# 检测URL协议
PROTOCOL=$(echo "$URL" | awk -F'://' '{print $1}')
if [[ "$PROTOCOL" != "http" && "$PROTOCOL" != "https" && "$PROTOCOL" != "ftp" ]]; then
    echo "错误: 不支持的协议 '$PROTOCOL'，仅支持 http/https/ftp"
    exit 1
fi

# 创建下载目录
mkdir -p "$TARGET_DIR" || { echo "无法创建下载目录"; exit 1; }
cd "$TARGET_DIR" || { echo "无法进入下载目录"; exit 1; }

# 从URL中提取文件名
FILENAME=$(basename "$URL")
TARGET_FILE="${TARGET_DIR}/${FILENAME}"

# 获取远程文件大小 (针对不同协议优化)
function get_remote_size {
    if [[ "$PROTOCOL" == "ftp" ]]; then
        # FTP协议获取文件大小
        if command -v curl &> /dev/null; then
            REMOTE_SIZE=$(curl -sI --list-only "$URL" | grep -i "$FILENAME" | awk '{print $5}' | tr -d '\r')
        else
            echo "0"
            return
        fi
    else
        # HTTP/HTTPS协议获取文件大小
        if command -v curl &> /dev/null; then
            REMOTE_SIZE=$(curl -sI "$URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
        elif command -v wget &> /dev/null; then
            REMOTE_SIZE=$(wget --spider -S "$URL" 2>&1 | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
        else
            echo "0"
            return
        fi
    fi
    
    # 验证是否获取到有效大小
    if [[ "$REMOTE_SIZE" =~ ^[0-9]+$ ]]; then
        echo "$REMOTE_SIZE"
    else
        echo "0"
    fi
}

# 获取远程文件大小
EXPECTED_SIZE=$(get_remote_size)

# 输出配置信息
log "===== 下载配置 ====="
log "协议: $PROTOCOL"
log "URL: $URL"
log "目标文件: $TARGET_FILE"
log "检查间隔: $CHECK_INTERVAL 秒"
log "大小容忍度: $SIZE_TOLERANCE%"
log "日志文件: $(realpath "$LOG_FILE")"
log "输出缓冲区大小: ${BUFFER_SIZE}B"
if [[ "$EXPECTED_SIZE" -gt 0 ]]; then
    log "远程文件大小: $EXPECTED_SIZE 字节"
else
    log "警告: 无法获取远程文件大小，将使用替代方法检测完成状态"
fi
log "==================="

# 下载函数 (针对不同协议优化)
function download_file {
    if [[ "$PROTOCOL" == "ftp" ]]; then
        # FTP下载命令
        CMD="wget -c -r -np -nH --cut-dirs=$(echo "$URL" | awk -F'/' '{print NF-3}') \
          --timeout=30 \
          --tries=10 \
          --waitretry=5 \
          "$URL" --progress=bar:force"
    else
        # HTTP/HTTPS下载命令
        CMD="wget -c -r -np -k -L -p \
          --timeout=30 \
          --tries=10 \
          --waitretry=5 \
          "$URL" --progress=bar:force"
    fi
    
    # 根据是否启用详细模式选择不同的日志记录方式
    if [[ "$VERBOSE" -eq 1 ]]; then
        if command -v stdbuf &> /dev/null; then
            stdbuf -o"$BUFFER_SIZE" $CMD 2>&1 | tee -a "$LOG_FILE"
        else
            $CMD 2>&1 | tee -a "$LOG_FILE"
        fi
    else
        if command -v stdbuf &> /dev/null; then
            stdbuf -o"$BUFFER_SIZE" $CMD >> "$LOG_FILE" 2>&1
        else
            $CMD >> "$LOG_FILE" 2>&1
        fi
    fi
}

# 循环执行下载命令
while true; do
    # 查找并终止之前的wget进程
    pkill -f "wget.*$FILENAME" 2>/dev/null
    sleep 2
    
    # 输出开始时间和状态信息
    log "开始新的下载周期"
    
    # 执行下载命令
    download_file &
    
    # 获取下载进程ID
    DOWNLOAD_PID=$!
    
    # 定期检查下载状态
    log "下载进行中... $(date)"
    for i in $(seq 1 $((CHECK_INTERVAL/30))); do
        if ps -p $DOWNLOAD_PID > /dev/null; then
            # 每30秒记录一次进度
            if [[ -f "$FILENAME" ]]; then
                CURRENT_SIZE=$(stat -c %s "$FILENAME" 2>/dev/null || wc -c < "$FILENAME")
                if [[ "$EXPECTED_SIZE" -gt 0 ]]; then
                    PERCENT=$(echo "scale=2; 100 * $CURRENT_SIZE / $EXPECTED_SIZE" | bc)
                    log "已下载: ${CURRENT_SIZE}B (${PERCENT}%)"
                else
                    log "已下载: ${CURRENT_SIZE}B"
                fi
            fi
        else
            break
        fi
        sleep 30
    done
    
    # 检查下载进程是否还在运行
    if ! ps -p $DOWNLOAD_PID > /dev/null; then
        log "下载已完成或提前终止"
        
        # 验证文件完整性
        if [ -f "$FILENAME" ]; then
            ACTUAL_SIZE=$(stat -c %s "$FILENAME" 2>/dev/null || wc -c < "$FILENAME")
            
            if [[ "$EXPECTED_SIZE" -gt 0 ]]; then
                # 比较文件大小
                SIZE_DIFF=$(echo "scale=2; 100 * abs($ACTUAL_SIZE - $EXPECTED_SIZE) / $EXPECTED_SIZE" | bc)
                
                if (( $(echo "$SIZE_DIFF < $SIZE_TOLERANCE" | bc -l) )); then
                    log "文件大小验证通过，下载完成!"
                    exit 0
                else
                    log "文件大小不匹配(差异: ${SIZE_DIFF}%)，继续下载..."
                fi
            else
                # 如果无法获取远程大小，使用替代方法检测完成
                # 检查日志中是否包含"100%"或"FINISHED"
                if grep -q "100%" "$LOG_FILE" || grep -q "FINISHED" "$LOG_FILE"; then
                    log "下载进度显示100%或FINISHED，假设下载完成"
                    exit 0
                else
                    log "下载未完成，继续下载..."
                fi
            fi
        else
            log "目标文件不存在，继续下载..."
        fi
    else
        log "下载仍在进行中，将中断并重新开始..."
    fi
done