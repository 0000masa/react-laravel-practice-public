FROM composer:2 as composer-builder

WORKDIR /app

# 依存関係定義ファイルのみコピー（キャッシュ効率化のため）
COPY backend/www/composer.json backend/www/composer.lock ./

RUN composer install --no-dev --optimize-autoloader --no-scripts --prefer-dist --ignore-platform-reqs

FROM php:8.2-fpm-bullseye

WORKDIR /var/www/html

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
    
#    パフォーマンスチューニング設定が含まれたファイルをコピー
COPY ./environment/ecr/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY ./environment/ecr/zz-custom.conf /usr/local/etc/php-fpm.d/zz-custom.conf

COPY --from=composer-builder /app/vendor ./vendor

COPY backend/www/ .

RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

EXPOSE 9000
CMD ["php-fpm"]