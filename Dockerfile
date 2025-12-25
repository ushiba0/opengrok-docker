# --- Stage 1: Build Universal Ctags ---
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y \
    git \
    autoconf \
    pkg-config \
    build-essential

RUN git clone https://github.com/universal-ctags/ctags.git /tmp/ctags \
    && cd /tmp/ctags \
    && ./autogen.sh \
    && ./configure \
    && make -j 4 \
    && make install

# --- Stage 2: Final Image ---
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# 必要なパッケージのインストール
RUN apt-get update \
    && apt-get install -y \
    default-jre \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Tomcat のインストール
RUN cd /tmp \
    && curl -s -L -o /tmp/tomcat.tar.gz http://ftp.riken.jp/net/apache/tomcat/tomcat-10/v10.1.50/bin/apache-tomcat-10.1.50.tar.gz \
    && tar xf /tmp/tomcat.tar.gz \
    && mkdir -p /opt/tomcat \
    && mv /tmp/apache-tomcat*/* /opt/tomcat \
    && useradd -M -d /opt/tomcat/home -s /bin/false tomcat \
    && chown -R tomcat:tomcat /opt/tomcat \
    && rm -rf /tmp/tomcat.tar.gz /tmp/apache-tomcat*

# OpenGrok のセットアップ
RUN mkdir /opengrok \
    && curl -s -L -o /tmp/opengrok.tar.gz https://github.com/oracle/opengrok/releases/download/1.14.4/opengrok-1.14.4.tar.gz \
    && tar xf /tmp/opengrok.tar.gz -C /opengrok \ 
    && rm -f /tmp/opengrok.tar.gz \
    && mv /opengrok/opengrok*/* /opengrok \
    && rmdir /opengrok/opengrok-* 

# 構成用ディレクトリの作成
RUN mkdir -p /opengrok/src /opengrok/data /opengrok/etc \
    && cp /opengrok/lib/source.war /opt/tomcat/webapps/ \
    && cp /opengrok/doc/logging.properties /opengrok/etc/

# ビルドした ctags をコピー
COPY --from=builder /usr/local/bin/ctags /usr/local/bin/ctags

# 起動スクリプトの作成
COPY <<EOF /entrypoint.sh
#!/bin/bash
# Start Tomcat.
/opt/tomcat/bin/startup.sh

until curl http://localhost:8080; do sleep 5; echo Waiting for webserver; done

# OpenGrok のインデックス作成（初回 & 起動時）
echo "Running OpenGrok indexer..."
java -Dfile.encoding=UTF-8  -Djava.util.logging.config.file=/opengrok/etc/logging.properties -jar /opengrok/lib/opengrok.jar -c /usr/local/bin/ctags -s /opengrok/src -d /opengrok/data -H -P -S -G -U http://localhost:8080/source

sleep infinity
EOF

RUN chmod +x /entrypoint.sh

# 権限の設定
RUN chown -R tomcat:tomcat /opengrok /opt/tomcat/webapps/

USER tomcat
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]

