#!/bin/bash

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# 项目根目录
PROJECT_ROOT="$SCRIPT_DIR/datiya/"
mkdir -p ${PROJECT_ROOT}
# 日期信息
TODAY=$(date +%Y%m%d)
# 下载URL
DOWNLOAD_URL="https://free.datiya.com/uploads/${TODAY}-clash.yaml"
# 临时文件
TEMP_FILE="$SCRIPT_DIR/${TODAY}-clash.yaml"
# 输出文件
OUTPUT_FILE="$PROJECT_ROOT/${TODAY}-v2ray.txt"
# Python脚本路径
PYTHON_SCRIPT="$SCRIPT_DIR/clash2v2ray.py"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 错误处理函数
error_exit() {
    log "错误: $1"
    cleanup
    exit 1
}

# 清理函数
cleanup() {
    if [ -f "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
        log "已清理临时文件: $TEMP_FILE"
    fi
}

# 检查依赖
check_dependencies() {
    log "检查依赖..."
    
    # 检查curl
    if ! command -v curl &> /dev/null; then
        error_exit "curl 未安装"
    fi
    
    # 检查python3
    if ! command -v python3 &> /dev/null; then
        error_exit "python3 未安装"
    fi
    
    # 检查python依赖
    if ! python3 -c "import yaml" 2> /dev/null; then
        log "安装python依赖..."
        pip3 install --quiet pyyaml
    fi
    
    log "依赖检查完成"
}

# 下载配置文件
download_config() {
    log "开始下载配置文件..."
    log "下载URL: $DOWNLOAD_URL"
    
    # 下载文件
    curl -k -s -o "$TEMP_FILE" "$DOWNLOAD_URL"
    
    # 检查下载是否成功
    if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
        error_exit "下载失败，文件不存在或为空"
    fi
    
    log "下载成功，文件大小: $(du -h "$TEMP_FILE" | cut -f1)"
}

# 转换配置文件
convert_config() {
    log "开始转换配置文件..."
    log "输入文件: $TEMP_FILE"
    log "输出文件: $OUTPUT_FILE"
    
    # 执行转换
    python3 "$PYTHON_SCRIPT" "$TEMP_FILE" "$OUTPUT_FILE"
    
    # 检查转换是否成功
    if [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
        error_exit "转换失败，输出文件不存在或为空"
    fi
    
    # 统计输出文件行数
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
    log "转换成功，生成 $LINE_COUNT 个节点链接"
}

# 主函数
main() {
    log "开始处理 datiya 配置..."
    
    # 检查依赖
    check_dependencies
    
    # 下载配置文件
    download_config
    
    # 转换配置文件
    convert_config
    
    # 清理临时文件
    cleanup
    
    log "处理完成！"
    log "结果文件: $OUTPUT_FILE"
}

# 执行主函数
main
