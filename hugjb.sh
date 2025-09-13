#!/bin/bash
set -e

# 默认参数
UUID=$(cat /proc/sys/kernel/random/uuid)
CFIP="cdn.xn--b6gac.eu.org"   # 默认优选 IP

echo "==== Xray Argo 精简部署 (No-Root) ===="
echo "UUID: $UUID"

# 自动分配一个系统可用端口
PORT=$(python3 - <<EOF
import socket
s=socket.socket()
s.bind(('',0))
print(s.getsockname()[1])
s.close()
EOF
)
echo "使用系统分配的端口: $PORT"

read -p "是否自定义优选IP? (默认: $CFIP): " input_cfip
if [ -n "$input_cfip" ]; then CFIP=$input_cfip; fi

echo "最终配置: UUID=$UUID, PORT=$PORT, CFIP=$CFIP"
sleep 1

# 环境检查
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 运行环境没有 python3, 请手动安装."
  exit 1
fi

pip3 install --user requests >/dev/null 2>&1 || true

# 克隆仓库
REPO_MAIN="https://github.com/smqlf1/python-xray-argo"
REPO_BACKUP="https://github.com/arloor/python-xray-argo"

if [ ! -d "python-xray-argo" ]; then
  echo "正在尝试克隆主仓库: $REPO_MAIN"
  if ! git clone "$REPO_MAIN"; then
    echo "主仓库失败，尝试备用仓库: $REPO_BACKUP"
    git clone "$REPO_BACKUP"
    mv python-xray-argo-main python-xray-argo 2>/dev/null || true
  fi
fi

cd python-xray-argo

# 修改 app.py 默认参数（确保所有端口都被替换）
sed -i "s|UUID = .*|UUID = '$UUID'|" app.py
sed -i "s|PORT = .*|PORT = $PORT|" app.py
sed -i "s|CFIP = .*|CFIP = '$CFIP'|" app.py
sed -i "s|('0.0.0.0', [0-9]\+)|('0.0.0.0', $PORT)|" app.py

# Hugging Face 保活配置
read -p "是否启用 Hugging Face 保活? (y/n): " enable_hf
if [[ "$enable_hf" == "y" ]]; then
  read -p "输入 HF_TOKEN: " HF_TOKEN
  read -p "输入 HF_REPO (例: username/space-name): " HF_REPO
  cat > keep_alive_task.sh <<EOF
#!/bin/bash
while true; do
  curl -s -X GET -H "Authorization: Bearer $HF_TOKEN" \\
    https://huggingface.co/api/spaces/$HF_REPO > /dev/null
  date +"[%Y-%m-%d %H:%M:%S] HF KeepAlive OK" >> keep_alive.log
  sleep 120
done
EOF
  chmod +x keep_alive_task.sh
  nohup ./keep_alive_task.sh >/dev/null 2>&1 &
  echo "HF 保活已启用 ✅"
fi

# 清除旧日志
rm -f app.log 2>/dev/null || true

# 启动服务
echo "正在启动 Xray Argo..."
nohup python3 app.py > app.log 2>&1 &
APP_PID=$!
echo "Xray Argo 已启动 ✅ (PID: $APP_PID)"

# 等待应用启动并提取订阅链接
echo "等待应用启动并生成订阅链接..."
sleep 20

# 检查应用是否仍在运行
if ! ps -p $APP_PID > /dev/null; then
  echo "应用已停止运行，检查日志..."
  tail -n 20 app.log
  exit 1
fi

echo "==== 提取订阅链接 ===="

# 直接从日志里找常见的订阅链接
LINKS=$(grep -Eo "(vmess|vless|trojan|ss)://[^[:space:]]+" app.log | head -10)
if [ -n "$LINKS" ]; then
  echo "找到订阅链接:"
  echo "$LINKS"
  echo "$LINKS" > subscriptions.txt
fi

# 显示 ARGO 域名
ARGO_DOMAIN=$(grep -o "ArgoDomain: [^ ]*" app.log | cut -d' ' -f2)
if [ -n "$ARGO_DOMAIN" ]; then
  echo "ARGO 域名: $ARGO_DOMAIN"
  echo "$ARGO_DOMAIN" > argo_domain.txt
fi

echo ""
echo "==== 部署状态 ===="
echo "应用 PID: $APP_PID"
echo "日志文件: $(pwd)/app.log"
echo "订阅链接文件: $(pwd)/subscriptions.txt"
echo "停止应用命令: kill $APP_PID"
echo "查看实时日志: tail -f $(pwd)/app.log"

# 最后显示几行日志
echo ""
echo "最后日志输出:"
tail -n 10 app.log
