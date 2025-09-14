
#!/bin/bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 基础环境检查
check_env() {
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}错误：curl未安装${NC}"
        exit 1
    fi
}

# 安装核心依赖
install_deps() {
    echo -e "${GREEN}[1/3] 安装系统依赖...${NC}"
    sudo apt update && sudo apt install -y \
        git python3 python3-pip \
        docker.io docker-compose
}

# 部署Xray服务
deploy_xray() {
    echo -e "${GREEN}[2/3] 拉取Xray镜像...${NC}"
    sudo docker pull teddysun/xray

    echo -e "${GREEN}[3/3] 启动服务...${NC}"
    sudo docker run -d --name xray \
        -p 443:443 -p 80:80 \
        -v /etc/xray:/etc/xray \
        --restart=always \
        teddysun/xray
}

# 主流程
main() {
    check_env
    install_deps
    deploy_xray
    
    echo -e "${GREEN}部署完成！${NC}"
    echo "管理命令：sudo docker logs xray"
}

main "$@"
