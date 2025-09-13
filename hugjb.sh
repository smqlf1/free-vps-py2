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

# 检查端口是否被占用并找到可用端口
while lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; do
  echo "端口 $PORT 已被占用，尝试其他端口"
  PORT=$((PORT + 1))
done
echo "使用端口: $PORT"

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
  echo "日志最后20行:"
  tail -n 20 app.log
  exit 1
fi

# 尝试从日志中提取订阅链接
echo "==== 提取订阅链接 ===="

# 查找并解码Base64订阅链接
BASE64_LINKS=$(grep -Eo "[A-Za-z0-9+/=]{100,}" app.log | head -2)

if [ -n "$BASE64_LINKS" ]; then
  echo "找到Base64编码的订阅链接，正在解码..."
  
  # 解码第一个链接 (VLESS)
  VLESS_LINK=$(echo "$BASE64_LINKS" | head -1 | base64 -d 2>/dev/null || echo "")
  if [ -n "$VLESS_LINK" ]; then
    echo "✅ VLESS 订阅链接: $VLESS_LINK"
    echo "$VLESS_LINK" > vless_subscription.txt
  fi
  
  # 解码第二个链接 (Trojan)
  TROJAN_LINK=$(echo "$BASE64_LINKS" | tail -1 | base64 -d 2>/dev/null || echo "")
  if [ -n "$TROJAN_LINK" ]; then
    echo "✅ Trojan 订阅链接: $TROJAN_LINK"
    echo "$TROJAN_LINK" > trojan_subscription.txt
  fi
  
  # 保存原始Base64链接
  echo "$BASE64_LINKS" > base64_subscriptions.txt
  echo "Base64订阅链接已保存到: $(pwd)/base64_subscriptions.txt"
fi

# 尝试查找其他格式的订阅链接
OTHER_LINKS=$(grep -Eo "(vmess|vless|trojan|ss)://[^[:space:]]+" app.log | head -5)
if [ -n "$OTHER_LINKS" ]; then
  echo "找到其他格式的订阅链接:"
  echo "$OTHER_LINKS"
  echo "$OTHER_LINKS" > other_subscriptions.txt
fi

# 尝试从本地服务获取订阅
if curl -s -m 10 http://localhost:$PORT >/dev/null; then
  echo "尝试从本地服务获取订阅..."
  # 尝试常见的订阅路径
  SUB_PATHS=("/sub" "/subscribe" "/link" "/config" "/v2ray" "/api/sub")
  for path in "${SUB_PATHS[@]}"; do
    response=$(curl -s -m 5 "http://localhost:$PORT$path" || true)
    if [ -n "$response" ] && echo "$response" | grep -qE "(vmess|vless|trojan|ss)://"; then
      SERVICE_LINKS=$(echo "$response" | grep -Eo "(vmess|vless|trojan|ss)://[^[:space:]]+")
      echo "从服务获取的订阅链接:"
      echo "$SERVICE_LINKS"
      echo "$SERVICE_LINKS" > service_subscriptions.txt
      break
    fi
  done
fi

# 检查是否有任何订阅链接被找到
if [ -z "$VLESS_LINK" ] && [ -z "$TROJAN_LINK" ] && [ -z "$OTHER_LINKS" ]; then
  echo "❌ 未能提取到订阅链接"
  echo "请查看日志文件获取更多信息: $(pwd)/app.log"
  echo "日志最后20行:"
  tail -n 20 app.log
else
  echo "✅ 订阅链接提取完成"
fi

# 显示ARGO域名
ARGO_DOMAIN=$(grep -o "ArgoDomain: [^ ]*" app.log | cut -d' ' -f2)
if [ -n "$ARGO_DOMAIN" ]; then
  echo "ARGO 域名: $ARGO_DOMAIN"
  echo "$ARGO_DOMAIN" > argo_domain.txt
fi

echo ""
echo "==== 部署状态 ===="
echo "应用 PID: $APP_PID"
echo "日志文件: $(pwd)/app.log"
echo "停止应用命令: kill $APP_PID"
echo "查看实时日志: tail -f $(pwd)/app.log"

# 显示最后几行日志
echo ""
echo "最后日志输出:"
tail -n 10 app.log
