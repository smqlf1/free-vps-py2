#!/bin/bash
set -e

# 默认参数
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=8080
CFIP="cdn.xn--b6gac.eu.org"   # 默认优选 IP

echo "==== Xray Argo 精简部署 (No-Root) ===="
echo "UUID: $UUID"
read -p "是否自定义端口? (默认: $PORT): " input_port
if [ -n "$input_port" ]; then PORT=$input_port; fi
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

# 克隆仓库（优先用你的 Fork，失败用备用镜像）
REPO_MAIN="https://github.com/smqlf1/python-xray-argo"  # 修改为实际仓库
REPO_BACKUP="https://github.com/eooce/python-xray-argo"

if [ ! -d "python-xray-argo" ]; then
  echo "正在尝试克隆主仓库: $REPO_MAIN"
  if ! git clone "$REPO_MAIN"; then
    echo "主仓库失败，尝试备用仓库: $REPO_BACKUP"
    git clone "$REPO_BACKUP"
    mv python-xray-argo-main python-xray-argo 2>/dev/null || true
  fi
fi

cd python-xray-argo

# 修改 app.py 默认参数
sed -i "s|UUID = .*|UUID = '$UUID'|" app.py
sed -i "s|PORT = .*|PORT = $PORT|" app.py
sed -i "s|CFIP = .*|CFIP = '$CFIP'|" app.py

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

# 启动服务
echo "正在启动 Xray Argo..."
nohup python3 app.py > app.log 2>&1 &
APP_PID=$!
echo "Xray Argo 已启动 ✅ (PID: $APP_PID)"

# 等待应用启动并提取订阅链接
echo "等待应用启动并生成订阅链接..."
sleep 15

# 尝试从日志中提取订阅链接
MAX_ATTEMPTS=5
ATTEMPT=1
SUB_LINK=""

while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ -z "$SUB_LINK" ]; do
  echo "尝试 $ATTEMPT/$MAX_ATTEMPTS 提取订阅链接..."
  
  # 尝试多种格式的订阅链接
  SUB_LINK=$(grep -Eo "(vmess|vless|trojan|ss)://[^[:space:]]+" app.log | head -1)
  
  if [ -z "$SUB_LINK" ]; then
    SUB_LINK=$(grep -Eo "https://[^[:space:]]+(sub|subscribe)[^[:space:]]*" app.log | head -1)
  fi
  
  if [ -z "$SUB_LINK" ]; then
    # 尝试从本地服务获取订阅
    if curl -s -m 10 http://localhost:$PORT >/dev/null; then
      # 尝试常见的订阅路径
      SUB_PATHS=("/sub" "/subscribe" "/link" "/config" "/v2ray" "/api/sub")
      for path in "${SUB_PATHS[@]}"; do
        response=$(curl -s -m 5 "http://localhost:$PORT$path" || true)
        if [ -n "$response" ] && echo "$response" | grep -qE "(vmess|vless|trojan|ss)://"; then
          SUB_LINK=$(echo "$response" | grep -Eo "(vmess|vless|trojan|ss)://[^[:space:]]+" | head -1)
          break
        fi
      done
    fi
  fi
  
  if [ -z "$SUB_LINK" ]; then
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
  fi
done

# 显示结果
echo ""
echo "==== 部署结果 ===="
if [ -n "$SUB_LINK" ]; then
  echo "✅ 订阅链接: $SUB_LINK"
  echo "$SUB_LINK" > subscription_link.txt
  echo "订阅链接已保存到: $(pwd)/subscription_link.txt"
else
  echo "❌ 未能提取到订阅链接"
  echo "请查看日志文件获取更多信息: $(pwd)/app.log"
  echo "日志最后20行:"
  tail -n 20 app.log
fi

echo ""
echo "日志文件: $(pwd)/app.log"
echo "停止应用命令: kill $APP_PID"
echo "查看实时日志: tail -f $(pwd)/app.log"
