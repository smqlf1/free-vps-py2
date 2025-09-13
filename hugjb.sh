#!/bin/bash
echo "==== Xray Argo 自动部署增强版 ===="

# UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
echo "使用的 UUID: $UUID"

# 端口
read -p "是否自定义端口? (默认: 8080): " PORT
PORT=${PORT:-8080}

# 优选 IP
read -p "是否自定义优选IP? (默认: cdn.xn--b6gac.eu.org): " CFIP
CFIP=${CFIP:-cdn.xn--b6gac.eu.org}

echo "最终配置: UUID=$UUID, PORT=$PORT, CFIP=$CFIP"

# 克隆仓库（如果没有）
if [ ! -d "python-xray-argo" ]; then
  git clone https://github.com/smqlf1/python-xray-argo
fi

cd python-xray-argo || exit 1

# 停掉旧进程
pkill -f "python3 app.py"

# 后台启动并写日志
nohup python3 app.py > app.log 2>&1 &

echo "Xray Argo 已启动 ✅"
sleep 10

echo "==== 提取订阅链接 ===="
# 提取常见的节点协议行
SUB_LINKS=$(grep -Eo "vmess://[^\s]+|vless://[^\s]+|trojan://[^\s]+|ss://[^\s]+|https://[^\s]+sub[^\s]*" app.log)

if [ -n "$SUB_LINKS" ]; then
    echo "$SUB_LINKS"
else
    echo "⚠️ 没有在 app.log 找到订阅地址，请手动检查："
    echo "  tail -f python-xray-argo/app.log"
fi
