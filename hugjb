#!/bin/bash
set -e

# 默认参数
UUID=$(cat /proc/sys/kernel/random/uuid)
PORT=8080
CFIP="cdn.xn--b6gac.eu.org"   # 默认优选 IP

echo "==== Xray Argo 精简部署 ===="
echo "UUID: $UUID"
read -p "是否自定义端口? (默认: $PORT): " input_port
if [ -n "$input_port" ]; then PORT=$input_port; fi
read -p "是否自定义优选IP? (默认: $CFIP): " input_cfip
if [ -n "$input_cfip" ]; then CFIP=$input_cfip; fi

echo "最终配置: UUID=$UUID, PORT=$PORT, CFIP=$CFIP"
sleep 1

# 依赖
apt-get update -y
apt-get install -y python3 python3-pip
pip3 install requests

# 拉取代码
if [ ! -d "python-xray-argo" ]; then
  git clone https://github.com/3Kmfi6HP/python-xray-argo
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
nohup python3 app.py > app.log 2>&1 &
echo "Xray Argo 已启动 ✅"
echo "日志文件: $(pwd)/app.log"
echo "订阅链接会输出在日志里"
