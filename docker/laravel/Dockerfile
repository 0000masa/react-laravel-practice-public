FROM php:8.3-fpm

ENV TZ=Asia/Tokyo

# 拡張機能インストール
RUN apt-get update && apt-get install -y --no-install-recommends\
    git \
    unzip \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    imagemagick \
    libmagickwand-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
    gd \
    pdo_mysql \
    mbstring \
    zip \
    pcntl \
    bcmath \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* 

# mlocati/install-php-extensions を使って OpenTelemetry 拡張を入れる
RUN curl -sSLf -o /usr/local/bin/install-php-extensions \
      https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions opentelemetry

RUN mkdir -p /var/www/env && \
    chown -R root:root /var/www/env

# Composerインストール
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

RUN groupadd -g 1000 sail && useradd -u 1000 -ms /bin/bash -g sail sail
USER sail

WORKDIR /var/www/php/www
