FROM ubuntu:22.04

LABEL maintainer="Sistema de Migração"

ARG WWWGROUP=1000
ARG NODE_VERSION=20

WORKDIR /var/www/html

ENV DEBIAN_FRONTEND noninteractive
ENV TZ=UTC

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update \
    && mkdir -p /etc/apt/keyrings \
    && apt-get install -y gnupg gosu curl ca-certificates zip unzip git supervisor sqlite3 libcap2-bin libpng-dev python3 dnsutils librsvg2-bin fswatch zbar-tools cron \
    && curl -sS 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x14aa40ec0831756756d7f66c4f4ea0aae5267a6c' | gpg --dearmor | tee /etc/apt/keyrings/ppa_ondrej_php.gpg > /dev/null \
    && echo "deb [signed-by=/etc/apt/keyrings/ppa_ondrej_php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main" > /etc/apt/sources.list.d/ppa_ondrej_php.list \
    && apt-get update \
    && apt-get install -y php5.6-fpm php5.6-cli php5.6-dev \
    php5.6-sqlite3 php5.6-gd php5.6-imagick \
    php5.6-curl \
    php5.6-imap php5.6-mysql php5.6-mbstring \
    php5.6-xml php5.6-zip php5.6-bcmath php5.6-soap \
    php5.6-intl php5.6-readline \
    php5.6-ldap \
    php5.6-msgpack php5.6-igbinary php5.6-mcrypt \
    php5.6-json \
    && curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer \
    && apt-get update \
    && apt-get install -y mysql-client \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN setcap "cap_net_bind_service=+ep" /usr/bin/php5.6

# Configurar usuário
RUN usermod -u 1000 www-data
RUN groupmod -g 1000 www-data

# Configurar PHP-FPM
RUN mkdir -p /run/php
COPY php.ini /etc/php/5.6/fpm/conf.d/99-custom.ini
COPY php.ini /etc/php/5.6/cli/conf.d/99-custom.ini
COPY fpm-pool.conf /etc/php/5.6/fpm/pool.d/www.conf

# Criar entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
