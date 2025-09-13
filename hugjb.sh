#!/bin/bash
echo "==== Xray Argo 自动部署增强版 ===="

# 获取当前目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
echo "使用的 UUID: $UUID"

# 端口
read -p "是否自定义端口? (默认: 8080): " PORT
PORT=${PORT:-8080}

# 检查端口是否被占用
while lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; do
    echo "端口 $PORT 已被占用，尝试其他端口"
    PORT=$((PORT + 1))
done
echo "使用端口: $PORT"

# 优选 IP
read -p "是否自定义优选IP? (默认: cdn.xn--b6gac.eu.org): " CFIP
CFIP=${CFIP:-cdn.xn--b6gac.eu.org}

echo "最终配置: UUID=$UUID, PORT=$PORT, CFIP=$CFIP"

# 检查依赖
command -v git >/dev/null 2>&1 || { echo "错误: 未安装 git"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "错误: 未安装 python3"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "警告: 未安装 curl，尝试安装..." && sudo apt-get update && sudo apt-get install -y curl; }

# 克隆仓库
if [ ! -d "python-xray-argo" ]; then
    echo "正在克隆仓库..."
    if ! git clone https://github.com/smqlf1/python-xray-argo; then
        echo "克隆仓库失败，请检查网络或URL"
        exit 1
    fi
fi

cd python-xray-argo || { echo "进入目录失败"; exit 1; }

# 检查 app.py 是否存在
if [ ! -f "app.py" ]; then
    echo "错误: 在 python-xray-argo 目录中未找到 app.py"
    exit 1
fi

# 确保 app.py 可执行
chmod +x app.py

# 安装 Python 依赖
if [ -f "requirements.txt" ]; then
    echo "正在安装 Python 依赖..."
    if ! pip3 install -r requirements.txt; then
        echo "安装依赖失败，尝试使用 --user 标志..."
        pip3 install --user -r requirements.txt
    fi
fi

# 停止旧进程
pkill -f "python3 app.py" 2>/dev/null
sleep 2

# 导出环境变量
export UUID=$UUID
export PORT=$PORT
export CFIP=$CFIP

echo "启动参数: UUID=$UUID, PORT=$PORT, CFIP=$CFIP"

# 启动应用
echo "正在启动 Xray Argo..."
if ! nohup python3 app.py > app.log 2>&1 & then
    echo "启动 app.py 失败，检查 app.log 获取详情:"
    sleep 2
    cat app.log
    exit 1
fi

# 存储后台进程的 PID
APP_PID=$!
echo "应用已启动，PID: $APP_PID"

# 等待应用初始化
echo "等待应用启动..."
MAX_WAIT=60
WAITED=0
STARTED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    sleep 5
    WAITED=$((WAITED + 5))
    
    # 检查应用是否仍在运行
    if ! ps -p $APP_PID > /dev/null; then
        echo "应用 (PID: $APP_PID) 已停止运行"
        echo "app.log 内容:"
        tail -n 50 app.log
        exit 1
    fi
    
    # 检查日志中是否有成功启动的迹象
    if grep -q "启动成功\|启动完成\|running\|started" app.log; then
        echo "应用启动成功"
        STARTED=1
        break
    fi
    
    echo "等待应用启动... ($WAITED/$MAX_WAIT 秒)"
done

if [ $STARTED -eq 0 ]; then
    echo "警告: 应用启动可能未完成，但进程仍在运行"
fi

echo "==== 提取订阅链接 ===="
# 提取订阅链接
SUB_LINKS=$(grep -Eo "vmess://[^\s]+|vless://[^\s]+|trojan://[^\s]+|ss://[^\s]+|https://[^\s]+sub[^\s]*" app.log)

if [ -n "$SUB_LINKS" ]; then
    echo "订阅链接:"
    echo "$SUB_LINKS"
    
    # 尝试将链接保存到文件
    echo "$SUB_LINKS" > subscription_links.txt
    echo "订阅链接已保存到: $SCRIPT_DIR/python-xray-argo/subscription_links.txt"
else
    echo "⚠️ 未在 app.log 中找到订阅地址，请手动检查:"
    echo "当前目录: $(pwd)"
    echo "日志文件最后50行:"
    tail -n 50 app.log
fi

echo ""
echo "==== 部署状态 ===="
echo "应用 PID: $APP_PID"
echo "日志文件: $SCRIPT_DIR/python-xray-argo/app.log"
echo "订阅文件: $SCRIPT_DIR/python-xray-argo/subscription_links.txt"
echo "停止应用命令: kill $APP_PID"
echo "查看日志命令: tail -f $SCRIPT_DIR/python-xray-argo/app.log"

# 等待用户确认
read -p "按回车键继续..."
