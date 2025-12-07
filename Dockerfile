# 使用 Alpine Linux 作为基础镜像，体积极小 (~5MB)
FROM alpine:latest

# 设置元数据
LABEL maintainer="YourName"
LABEL description="Sing-box automated node"

# 安装必要的依赖
# bash: 脚本解释器
# curl/wget: 下载核心文件
# openssl: 生成证书依赖
# util-linux: uuidgen 工具
# ca-certificates: 确保 HTTPS 请求正常
# tzdata: 允许用户通过 TZ 环境变量设置时区
# grep/sed/awk: 脚本处理逻辑所需
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    openssl \
    ca-certificates \
    util-linux \
    grep \
    sed \
    coreutils \
    tzdata \
    && rm -rf /var/cache/apk/*

# 设置工作目录
WORKDIR /app

# 复制启动脚本
COPY entrypoint.sh /app/entrypoint.sh

# 赋予脚本执行权限
RUN chmod +x /app/entrypoint.sh

# 定义数据卷挂载点，用于持久化证书、配置和二进制文件
VOLUME ["/data"]

# 设置容器启动命令
ENTRYPOINT ["/app/entrypoint.sh"]
