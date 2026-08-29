#!/bin/bash
set -e

cd backend

# Generate APP_KEY if not set
php artisan key:generate --force

# Run migrations
php artisan migrate --force

# Clear caches
php artisan config:clear
php artisan cache:clear
php artisan view:clear

# Start PHP server on port 8080
php artisan serve --host=0.0.0.0 --port=8080
