# 使用轻量级的 Node.js 基础镜像
FROM node:lts-alpine

# 设置工作目录
WORKDIR /app

# 先复制依赖描述文件（利用缓存机制加速构建）
COPY package.json ./

# 安装依赖
RUN npm install --production

# 复制核心代码
COPY index.js ./

# 设置时区
RUN apk add --no-cache tzdata
ENV TZ=Asia/Shanghai

# 暴露端口
EXPOSE 3000

# 启动命令
CMD ["node", "index.js"]
