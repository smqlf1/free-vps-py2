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

# Check dependencies
command -v git >/dev/null 2>&1 || { echo "Error: git is not installed."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 is not installed."; exit 1; }

# Clone repository
if [ ! -d "python-xray-argo" ]; then
  echo "Cloning repository..."
  if ! git clone https://github.com/smqlf1/python-xray-argo; then
    echo "Failed to clone repository. Check network or URL."
    exit 1
  fi
fi

cd python-xray-argo || { echo "Failed to enter directory."; exit 1; }

# Check if app.py exists
if [ ! -f "app.py" ]; then
  echo "Error: app.py not found in python-xray-argo directory."
  exit 1
fi

# Ensure app.py is executable
chmod +x app.py

# Install Python dependencies (if requirements.txt exists)
if [ -f "requirements.txt" ]; then
  echo "Installing Python dependencies..."
  if ! pip3 install -r requirements.txt; then
    echo "Failed to install dependencies."
    exit 1
  fi
fi

# Stop old processes
pkill -f "python3 app.py" 2>/dev/null

# Export environment variables for app.py
export UUID=$UUID
export PORT=$PORT
export CFIP=$CFIP

# Start application
echo "Starting Xray Argo..."
if ! nohup python3 app.py > app.log 2>&1 & then
  echo "Failed to start app.py. Check app.log for details:"
  cat app.log
  exit 1
fi

# Store the PID of the background process
APP_PID=$!
echo "Application started with PID: $APP_PID"

# Wait for application to initialize
echo "Waiting for application to start..."
sleep 30

# Check if the application is still running
if ! ps -p $APP_PID > /dev/null; then
  echo "Application (PID: $APP_PID) is not running. Check app.log for errors:"
  cat app.log
  exit 1
fi

echo "==== 提取订阅链接 ===="
# Extract subscription links
SUB_LINKS=$(grep -Eo "vmess://[^\s]+|vless://[^\s]+|trojan://[^\s]+|ss://[^\s]+|https://[^\s]+sub[^\s]*" app.log)

if [ -n "$SUB_LINKS" ]; then
  echo "订阅链接:"
  echo "$SUB_LINKS"
else
  echo "⚠️ 没有在 app.log 找到订阅地址，请手动检查："
  # 输出最后50行日志，避免过多输出
  tail -n 50 app.log
fi
