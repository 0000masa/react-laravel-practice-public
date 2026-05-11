FROM nginx:1.27-alpine
    
ENV TZ=Asia/Tokyo

RUN addgroup -g 1000  dev \
 && adduser  -u 1000 -G dev -h /home/dev -s /bin/sh -D dev

RUN mkdir -p /var/www/logs

# 作業ディレクトリを設定
WORKDIR /var/www/html