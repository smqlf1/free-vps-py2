#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}====== Python Xray Argo 一键部署脚本 ======${NC}"

# 检查依赖
check_dep() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${YELLOW}缺少依赖: $1，正在安装...${NC}"
        if command -v apt &> /dev/null; then
            apt update && apt install -y $1
        elif command -v yum &> /dev/null; then
            yum install -y $1
        fi
    fi
}

check_dep python3
check_dep unzip
check_dep git
check_dep curl

# 拉取代码
rm -rf python-xray-argo
git clone https://github.com/eooce/python-xray-argo
cd python-xray-argo || exit
chmod +x app.py

# 用户选择模式
echo -e "${YELLOW}请选择模式:${NC}"
echo "1) 极速模式（仅UUID和CFIP）"
echo "2) 完整模式（全部可配置）"
echo "3) 查看节点信息"
echo "4) 查看保活状态"
read -p "输入选项(1/2/3/4): " mode

if [[ $mode == "1" ]]; then
    read -p "请输入UUID: " UUID
    read -p "请输入CF优选IP或域名 (留空则默认 joeyblog.net): " CFIP
    if [[ -z "$CFIP" ]]; then
        CFIP="joeyblog.net"
    fi
    sed -i "s|UUID = .*|UUID = '$UUID'|" app.py
    sed -i "s|CFIP = .*|CFIP = '$CFIP'|" app.py
    echo -e "${GREEN}极速模式配置完成${NC}"
elif [[ $mode == "2" ]]; then
    read -p "请输入UUID (默认随机): " UUID
    [[ -z "$UUID" ]] && UUID=$(cat /proc/sys/kernel/random/uuid)

    read -p "请输入端口 (默认8080): " PORT
    [[ -z "$PORT" ]] && PORT=8080

    read -p "请输入Argo隧道JSON (可选): " ARGO_JSON

    read -p "请输入CF优选IP或域名 (留空则默认 joeyblog.net): " CFIP
    if [[ -z "$CFIP" ]]; then
        CFIP="joeyblog.net"
    fi

    read -p "请输入订阅路径 (默认sub): " SUB_PATH
    [[ -z "$SUB_PATH" ]] && SUB_PATH="sub"

    read -p "是否启用哪吒监控 (y/n): " NEZHA_ENABLE
    if [[ $NEZHA_ENABLE == "y" ]]; then
        read -p "请输入哪吒服务器: " NEZHA_SERVER
        read -p "请输入哪吒端口: " NEZHA_PORT
        read -p "请输入哪吒密钥: " NEZHA_KEY
    fi

    read -p "是否启用TG机器人推送 (y/n): " TG_ENABLE
    if [[ $TG_ENABLE == "y" ]]; then
        read -p "请输入TG机器人TOKEN: " TG_TOKEN
        read -p "请输入TG用户ID: " TG_USERID
    fi

    sed -i "s|UUID = .*|UUID = '$UUID'|" app.py
    sed -i "s|PORT = .*|PORT = $PORT|" app.py
    sed -i "s|ARGO_JSON = .*|ARGO_JSON = '''$ARGO_JSON'''|" app.py
    sed -i "s|CFIP = .*|CFIP = '$CFIP'|" app.py
    sed -i "s|SUB_PATH = .*|SUB_PATH = '$SUB_PATH'|" app.py
    sed -i "s|NEZHA_ENABLE = .*|NEZHA_ENABLE = $([[ $NEZHA_ENABLE == "y" ]] && echo True || echo False)|" app.py
    sed -i "s|NEZHA_SERVER = .*|NEZHA_SERVER = '$NEZHA_SERVER'|" app.py
    sed -i "s|NEZHA_PORT = .*|NEZHA_PORT = $NEZHA_PORT|" app.py
    sed -i "s|NEZHA_KEY = .*|NEZHA_KEY = '$NEZHA_KEY'|" app.py
    sed -i "s|TG_ENABLE = .*|TG_ENABLE = $([[ $TG_ENABLE == "y" ]] && echo True || echo False)|" app.py
    sed -i "s|TG_TOKEN = .*|TG_TOKEN = '$TG_TOKEN'|" app.py
    sed -i "s|TG_USERID = .*|TG_USERID = '$TG_USERID'|" app.py

    echo -e "${GREEN}完整模式配置完成${NC}"
elif [[ $mode == "3" ]]; then
    cat nodes.txt
    exit 0
elif [[ $mode == "4" ]]; then
    tail -f keep_alive_status.log
    exit 0
fi

# 增加YT分流与80端口节点
cat >> config.json <<EOF

,
{
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["youtube.com", "youtu.be", "googlevideo.com"],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

cat >> nodes.txt <<EOF
# 额外生成80端口无TLS节点
{
  "add": "$CFIP",
  "port": "80",
  "id": "$UUID",
  "net": "ws",
  "type": "none",
  "host": "$CFIP",
  "path": "/",
  "tls": "false"
}
EOF

# 保活脚本
cat > keep_alive_task.sh <<EOF
#!/bin/bash
HF_REPO_ID="your-hf-repo"
HF_TOKEN="your-hf-token"

while true; do
    status_code=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer \$HF_TOKEN" "https://huggingface.co/api/spaces/\$HF_REPO_ID")
    if [ "\$status_code" -eq 200 ]; then
        echo "Hugging Face 保活成功 (Spaces, 状态码: 200) - \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
    else
        status_code_model=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer \$HF_TOKEN" "https://huggingface.co/api/models/\$HF_REPO_ID")
        if [ "\$status_code_model" -eq 200 ]; then
            echo "Hugging Face 保活成功 (Model, 状态码: 200) - \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        else
            echo "保活失败 (状态码: \$status_code/\$status_code_model) - \$(date '+%Y-%m-%d %H:%M:%S')" > keep_alive_status.log
        fi
    fi
    sleep 60
done
EOF

chmod +x keep_alive_task.sh
nohup ./keep_alive_task.sh > keep_alive.log 2>&1 &
KEEPALIVE_PID=$!

# 启动主服务
nohup python3 app.py > app.log 2>&1 &
PID=$!
echo $PID > app.pid

echo -e "${GREEN}服务已启动，PID: $PID${NC}"
echo -e "${GREEN}保活任务已启动，PID: $KEEPALIVE_PID${NC}"

echo -e "${YELLOW}========== 节点信息 ==========${NC}"
cat nodes.txt
echo -e "${YELLOW}==============================${NC}"

# 自动生成订阅链接
echo -e "${GREEN}正在生成订阅链接...${NC}"
base64 -w 0 nodes.txt > sub.txt
SUB_CONTENT=$(cat sub.txt)
echo -e "${YELLOW}订阅链接如下 (可复制到客户端):${NC}"
echo "data:application/octet-stream;base64,$SUB_CONTENT"

