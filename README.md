# Xray Argo Lite (No-Root)

这是一个精简版的 **Xray + Argo 一键部署脚本**，适用于 **Hugging Face / Replit / 无 root VPS** 等环境。  
特点：
- 自动生成 UUID
- 支持自定义端口和优选 IP
- 后台运行，日志保存到 `app.log`
- 可选 Hugging Face 保活

---

## 🚀 一键部署

在终端中执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/<你的GitHub用户名>/<仓库名>/refs/heads/main/hugjb.sh)
