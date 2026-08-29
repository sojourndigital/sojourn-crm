FROM php:8.3-fpm

# Install system dependencies including Node.js
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    libpq-dev \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /app

# Copy entire project
COPY . .

# Install PHP dependencies
RUN cd backend && composer install --no-dev --optimize-autoloader

# Build frontend assets
RUN cd backend && npm install --ignore-scripts && npm run build

# Expose port
EXPOSE 8080

# Create startup script
RUN echo '#!/bin/bash\ncd /app/backend\nphp artisan key:generate --force\nphp artisan migrate --force\nphp artisan config:clear\nphp artisan serve --host=0.0.0.0 --port=8080' > /app/start.sh && chmod +x /app/start.sh

# Run startup script
CMD ["/app/start.sh"]
