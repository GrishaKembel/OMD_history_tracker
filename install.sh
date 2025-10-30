#!/bin/bash
export PATH="C:\Users\deryabinve\db\pgsql\bin:$PATH"
# ==================================================================
# Скрипт автоматической установки OpenMetadata History Tracker
# Версия: 1.0
# ==================================================================

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции для красивого вывода
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_step() {
    echo -e "${PURPLE}▶ $1${NC}"
}

# Баннер
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
  ___  __  __   _  _ _     _                   
 / _ \|  \/  | | || (_)___| |_ ___ _ _ _  _   
| (_) | |\/| | | __ | (_-<  _/ _ \ '_| || |  
 \___/|_|  |_| |_||_|_/__/\__\___/_|  \_, |  
                                       |__/   
 _____             _            
|_   _| _ __ _ ___| |_____ _ _  
  | || '_/ _` / __| / / -_) '_| 
  |_||_| \__,_\___|_\_\___|_|   
                                
EOF
    echo -e "${NC}"
    echo -e "${BLUE}OpenMetadata History Tracker - Установка${NC}"
    echo -e "${BLUE}v1.0${NC}"
    echo ""
}

# Проверка, что скрипт не запущен от root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then 
        print_error "Не запускайте этот скрипт от root!"
        print_info "Используйте: ./install.sh (без sudo)"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    print_header "Проверка зависимостей"
    
    local missing_deps=()
    local optional_deps=()
    
    # Проверка Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_success "Docker установлен: $DOCKER_VERSION"
    else
        print_warning "Docker не установлен"
        missing_deps+=("docker")
    fi
    
    # Проверка Docker Compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version)
        print_success "Docker Compose установлен: $COMPOSE_VERSION"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        print_success "Docker Compose (plugin) установлен: $COMPOSE_VERSION"
        DOCKER_COMPOSE_CMD="docker compose"
    else
        print_warning "Docker Compose не установлен"
        missing_deps+=("docker-compose")
    fi
    
    # Устанавливаем команду для docker-compose
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        DOCKER_COMPOSE_CMD="docker-compose"
    fi
    
    # Проверка Python (для локальной установки)
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version)
        print_success "Python установлен: $PYTHON_VERSION"
    else
        print_warning "Python3 не установлен"
        optional_deps+=("python3")
    fi
    
    # Проверка pip
    if command -v pip3 &> /dev/null; then
        print_success "pip3 установлен"
    else
        print_warning "pip3 не установлен (опционально)"
        optional_deps+=("python3-pip")
    fi
    
    # Проверка PostgreSQL client
    if command -v psql &> /dev/null; then
        print_success "PostgreSQL client установлен"
    else
        print_warning "PostgreSQL client не установлен (опционально, для работы с БД)"
        optional_deps+=("postgresql-client")
    fi
    
    # Проверка curl
    if command -v curl &> /dev/null; then
        print_success "curl установлен"
    else
        print_warning "curl не установлен"
        missing_deps+=("curl")
    fi
    
    # Если есть отсутствующие критичные зависимости
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        print_error "Отсутствуют критичные зависимости: ${missing_deps[*]}"
        echo ""
        print_info "Для установки на Ubuntu/Debian:"
        echo "  sudo apt-get update"
        [ " ${missing_deps[@]} " =~ " docker " ] && echo "  sudo apt-get install -y docker.io"
        [ " ${missing_deps[@]} " =~ " docker-compose " ] && echo "  sudo apt-get install -y docker-compose"
        [ " ${missing_deps[@]} " =~ " curl " ] && echo "  sudo apt-get install -y curl"
        echo ""
        print_info "Для установки на CentOS/RHEL:"
        [ " ${missing_deps[@]} " =~ " docker " ] && echo "  sudo yum install -y docker"
        [ " ${missing_deps[@]} " =~ " docker-compose " ] && echo "  sudo yum install -y docker-compose"
        [ " ${missing_deps[@]} " =~ " curl " ] && echo "  sudo yum install -y curl"
        echo ""
        print_info "После установки запустите Docker:"
        echo "  sudo systemctl start docker"
        echo "  sudo systemctl enable docker"
        echo "  sudo usermod -aG docker $USER"
        echo "  newgrp docker  # или перелогиньтесь"
        echo ""
        read -p "Продолжить установку без этих зависимостей? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Информация об опциональных зависимостях
    if [ ${#optional_deps[@]} -gt 0 ]; then
        echo ""
        print_info "Опциональные зависимости (можно установить позже): ${optional_deps[*]}"
    fi
    
    echo ""
}

# Проверка существующих файлов
check_existing_files() {
    print_header "Проверка существующих файлов"
    
    local files_exist=false
    
    if [ -f "webhook_listener.py" ]; then
        print_warning "Файл webhook_listener.py уже существует"
        files_exist=true
    fi
    
    if [ -f ".env" ]; then
        print_warning "Файл .env уже существует"
        files_exist=true
    fi
    
    if [ -f "docker-compose.yml" ]; then
        print_warning "Файл docker-compose.yml уже существует"
        files_exist=true
    fi
    
    if [ "$files_exist" = true ]; then
        echo ""
        read -p "Перезаписать существующие файлы? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена. Существующие файлы не изменены."
            exit 0
        fi
    else
        print_success "Файлы проекта отсутствуют, можно продолжать"
    fi
}

# Выбор режима установки
choose_installation_mode() {
    print_header "Выбор режима установки"
    
    echo ""
    echo "Выберите режим установки:"
    echo ""
    echo "  1) Docker (рекомендуется для продакшена)"
    echo "     • Автоматическая настройка PostgreSQL"
    echo "     • Изолированное окружение"
    echo "     • Простое управление (docker-compose)"
    echo ""
    echo "  2) Локально (для разработки)"
    echo "     • Требуется PostgreSQL"
    echo "     • Запуск через Python venv"
    echo "     • Удобно для отладки"
    echo ""
    read -p "Ваш выбор (1 или 2): " mode
    
    case $mode in
        1)
            INSTALL_MODE="docker"
            print_success "Выбран режим: Docker"
            ;;
        2)
            INSTALL_MODE="local"
            print_success "Выбран режим: Локальная установка"
            ;;
        *)
            print_error "Неверный выбор"
            exit 1
            ;;
    esac
}

# Генерация конфигурации
generate_config() {
    print_header "Настройка конфигурации"

#    # Генерация случайного секрета
#    print_step "Генерация секретного ключа..."
#    if command -v python3 &> /dev/null; then
#        WEBHOOK_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null)
#    elif command -v openssl &> /dev/null; then
#        WEBHOOK_SECRET=$(openssl rand -base64 32 | tr -d '\n')
#    else
#        WEBHOOK_SECRET="please_change_this_secret_$(date +%s)"
#        print_warning "Не удалось сгенерировать секрет автоматически"
#    fi
#
#    print_success "Секрет сгенерирован"

    # Запрос параметров БД
    echo ""
    print_info "Настройка базы данных PostgreSQL"
    echo ""
    
    if [ "$INSTALL_MODE" = "docker" ]; then
        print_info "Для Docker можно использовать значения по умолчанию"
        DB_HOST="postgres"
    else
        read -p "Хост БД [localhost]: " DB_HOST
        DB_HOST=${DB_HOST:-localhost}
    fi
    
    read -p "Порт БД [5432]: " DB_PORT
    DB_PORT=${DB_PORT:-5432}
    
    read -p "Имя БД [openmetadata_history]: " DB_NAME
    DB_NAME=${DB_NAME:-openmetadata_history}
    
    read -p "Пользователь БД [postgres]: " DB_USER
    DB_USER=${DB_USER:-postgres}
    
    echo ""
    read -sp "Пароль БД (оставьте пустым для генерации): " DB_PASSWORD
    echo ""
    
    if [ -z "$DB_PASSWORD" ]; then
        if command -v openssl &> /dev/null; then
            DB_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')
            print_success "Пароль сгенерирован автоматически"
        else
            DB_PASSWORD="changeme_$(date +%s)"
            print_warning "Пароль по умолчанию установлен, измените его!"
        fi
    fi
    
    read -p "Порт для webhook сервиса [5000]: " PORT
    PORT=${PORT:-5000}
    
    # Создание .env файла
    print_step "Создание файла .env..."
    cat > .env << EOF
# Настройки базы данных PostgreSQL
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD

# Секретный ключ для webhook
#WEBHOOK_SECRET=$WEBHOOK_SECRET

# Порт для Flask-приложения
PORT=$PORT
EOF
    
    chmod 600 .env  # Ограничиваем доступ к файлу с паролями
    print_success "Файл .env создан (chmod 600)"
    
    echo ""
    print_warning "ВАЖНО! Сохраните эти данные:"
    echo ""
    #echo -e "  ${CYAN}Webhook Secret:${NC} $WEBHOOK_SECRET"
    echo -e "  ${CYAN}DB Password:${NC} $DB_PASSWORD"
    echo ""
    print_info "Webhook Secret понадобится для настройки webhook в OpenMetadata"
    echo ""
}

# Создание необходимых файлов
create_project_files() {
    print_header "Создание файлов проекта"
    
    # Проверяем наличие основного файла
    if [ ! -f "webhook_listener.py" ]; then
        print_error "Файл webhook_listener.py не найден!"
        print_info "Создайте файл webhook_listener.py из артефакта перед запуском установки"
        echo ""
        print_info "Или скопируйте содержимое из артефакта 'OpenMetadata Webhook Listener'"
        exit 1
    else
        print_success "webhook_listener.py найден"
    fi
    
    # Проверяем requirements.txt
    if [ ! -f "requirements.txt" ]; then
        print_warning "requirements.txt не найден, создаю..."
        cat > requirements.txt << 'EOF'
Flask==3.0.0
psycopg2-binary==2.9.9
python-dotenv==1.0.0
requests==2.31.0
gunicorn==21.2.0
EOF
        print_success "requirements.txt создан"
    else
        print_success "requirements.txt найден"
    fi
    
    # Создаем Dockerfile если нужно
    if [ "$INSTALL_MODE" = "docker" ] && [ ! -f "Dockerfile" ]; then
        print_step "Создание Dockerfile..."
        cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY webhook_listener.py .

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "webhook_listener:app"]
EOF
        print_success "Dockerfile создан"
    fi
    
    # Создаем docker-compose.yml если нужно
    if [ "$INSTALL_MODE" = "docker" ] && [ ! -f "docker-compose.yml" ]; then
        print_step "Создание docker-compose.yml..."
        cat > docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: om_history_db
    environment:
      POSTGRES_DB: $DB_NAME
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASSWORD
    ports:
      - "$DB_PORT:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $DB_USER"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - om_history_network

  webhook_listener:
    build: .
    container_name: om_webhook_listener
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
      DB_NAME: $DB_NAME
      DB_USER: $DB_USER
      DB_PASSWORD: $DB_PASSWORD
      #WEBHOOK_SECRET: $WEBHOOK_SECRET
      PORT: $PORT
    ports:
      - "$PORT:$PORT"
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - om_history_network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  postgres_data:

networks:
  om_history_network:
    driver: bridge
EOF
        print_success "docker-compose.yml создан"
    fi
}

# Установка через Docker
install_docker() {
    print_header "Установка через Docker"
    
    print_step "Остановка существующих контейнеров (если есть)..."
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    
    print_step "Сборка Docker образа..."
    if $DOCKER_COMPOSE_CMD build; then
        print_success "Образ собран успешно"
    else
        print_error "Ошибка сборки образа"
        exit 1
    fi
    
    print_step "Запуск контейнеров..."
    if $DOCKER_COMPOSE_CMD up -d; then
        print_success "Контейнеры запущены"
    else
        print_error "Ошибка запуска контейнеров"
        exit 1
    fi
    
    # Ожидание запуска
    print_step "Ожидание готовности сервисов (макс. 60 сек)..."
    local count=0
    while [ $count -lt 60 ]; do
        if curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
            echo ""
            print_success "Сервис запущен и работает!"
            return 0
        fi
        echo -n "."
        sleep 2
        count=$((count + 2))
    done
    
    echo ""
    print_warning "Сервис не ответил за 60 секунд"
    print_info "Проверьте логи: $DOCKER_COMPOSE_CMD logs webhook_listener"
}

# Локальная установка
install_local() {
    print_header "Локальная установка"
    
    # Создание виртуального окружения
    if [ ! -d "venv" ]; then
        print_step "Создание виртуального окружения..."
        python3 -m venv venv
        print_success "Виртуальное окружение создано"
    else
        print_info "Виртуальное окружение уже существует"
    fi
    
    # Активация
    print_step "Активация виртуального окружения..."
    source venv/bin/activate
    
    # Установка зависимостей
    print_step "Установка Python зависимостей..."
    pip install --upgrade pip > /dev/null 2>&1
    if pip install -r requirements.txt; then
        print_success "Зависимости установлены"
    else
        print_error "Ошибка установки зависимостей"
        exit 1
    fi
    
    # Проверка PostgreSQL
    print_step "Проверка подключения к PostgreSQL..."
    if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d postgres -c "SELECT 1" > /dev/null 2>&1; then
        print_success "Подключение к PostgreSQL успешно"
        
        # Проверка существования БД
        if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d postgres -lqt | cut -d \| -f 1 | grep -qw $DB_NAME; then
            print_info "База данных $DB_NAME уже существует"
        else
            print_step "Создание базы данных $DB_NAME..."
            if PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME;"; then
                print_success "База данных создана"
            else
                print_warning "Не удалось создать БД (возможно уже существует)"
            fi
        fi
    else
        print_error "Не удалось подключиться к PostgreSQL"
        print_info "Убедитесь, что:"
        print_info "  • PostgreSQL установлен и запущен"
        print_info "  • Параметры подключения в .env правильные"
        print_info "  • Пользователь $DB_USER существует и имеет права"
        exit 1
    fi
    
    # Запуск сервиса
    print_step "Запуск сервиса в фоновом режиме..."
    nohup python webhook_listener.py > webhook.log 2>&1 &
    echo $! > webhook.pid
    print_success "Сервис запущен с PID: $(cat webhook.pid)"
    
    # Ожидание запуска
    print_step "Проверка работоспособности..."
    sleep 5
    
    if curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
        print_success "Сервис работает корректно!"
    else
        print_error "Сервис не отвечает"
        print_info "Проверьте логи: tail -f webhook.log"
    fi
}

# Тестирование
run_tests() {
    print_header "Тестирование установки"
    
    print_step "Проверка health endpoint..."
    if curl -s http://localhost:$PORT/health | grep -q "healthy"; then
        print_success "Health check пройден"
    else
        print_error "Health check не пройден"
        return 1
    fi
    
    print_step "Проверка подключения к БД..."
    local health_response=$(curl -s http://localhost:$PORT/health)
    if echo "$health_response" | grep -q '"database":"connected"'; then
        print_success "Подключение к БД работает"
    else
        print_warning "Проблема с подключением к БД"
    fi
    
    if [ -f "test_webhook.py" ]; then
        echo ""
        read -p "Запустить автоматические тесты? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_step "Запуск тестов..."
            python3 test_webhook.py || print_warning "Некоторые тесты не прошли"
        fi
    else
        print_info "Файл test_webhook.py не найден, пропускаем автотесты"
    fi
}

# Инструкции после установки
print_post_install() {
    print_header "Установка завершена!"
    
    echo ""
    print_success "Webhook listener успешно запущен!"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Сервис работает на: ${CYAN}http://localhost:$PORT${NC}"
    echo -e "${GREEN}✓${NC} Health check: ${CYAN}http://localhost:$PORT/health${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    print_info "Следующие шаги:"
    echo ""
    echo "1️⃣  Настройте webhook в OpenMetadata:"
    echo "   • Откройте OpenMetadata UI"
    echo "   • Settings → Integrations → Webhooks → Add Webhook"
    echo ""
    echo "   Параметры webhook:"
    echo -e "   ${CYAN}Name:${NC}           History Tracker"
    echo -e "   ${CYAN}Endpoint URL:${NC}   http://YOUR_SERVER_IP:$PORT/webhook"
    echo -e "   ${CYAN}Secret Key:${NC}     $WEBHOOK_SECRET"
    echo -e "   ${CYAN}Event Filters:${NC}  ✓ entityCreated, entityUpdated, entityDeleted"
    echo -e "   ${CYAN}Entity Types:${NC}   ✓ All (или выберите нужные)"
    echo ""
    
    echo "2️⃣  Проверьте работу:"
    echo "   • Измените описание любой таблицы в OpenMetadata"
    if [ "$INSTALL_MODE" = "docker" ]; then
        echo "   • Проверьте логи: ${CYAN}$DOCKER_COMPOSE_CMD logs -f webhook_listener${NC}"
    else
        echo "   • Проверьте логи: ${CYAN}tail -f webhook.log${NC}"
    fi
    echo ""
    
    echo "3️⃣  Подключитесь к БД для просмотра истории:"
    if [ "$INSTALL_MODE" = "docker" ]; then
        echo "   ${CYAN}docker exec -it om_history_db psql -U $DB_USER -d $DB_NAME${NC}"
    else
        echo "   ${CYAN}psql -h $DB_HOST -U $DB_USER -d $DB_NAME${NC}"
    fi
    echo "   ${CYAN}SELECT * FROM metadata_change_events ORDER BY event_time DESC LIMIT 10;${NC}"
    echo ""
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "Полезные команды:"
    echo ""
    if [ "$INSTALL_MODE" = "docker" ]; then
        echo "   Остановить:    ${CYAN}$DOCKER_COMPOSE_CMD down${NC}"
        echo "   Перезапустить: ${CYAN}$DOCKER_COMPOSE_CMD restart${NC}"
        echo "   Логи:          ${CYAN}$DOCKER_COMPOSE_CMD logs -f webhook_listener${NC}"
        echo "   Статус:        ${CYAN}$DOCKER_COMPOSE_CMD ps${NC}"
    else
        echo "   Остановить:    ${CYAN}kill \$(cat webhook.pid)${NC}"
        echo "   Перезапустить: ${CYAN}./install.sh${NC}"
        echo "   Логи:          ${CYAN}tail -f webhook.log${NC}"
        echo "   Статус:        ${CYAN}ps aux | grep webhook_listener${NC}"
    fi
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    print_warning "⚠️  ВАЖНО: Сохраните секретный ключ!"
    echo ""
    echo -e "   ${YELLOW}Webhook Secret:${NC} $WEBHOOK_SECRET"
    echo ""
    echo "   Этот ключ нужно использовать при настройке webhook в OpenMetadata"
    echo ""
    
    print_success "Готово! Ваша система отслеживания истории запущена 🚀"
    echo ""
}

# Основной процесс установки
main() {
    show_banner
    
    # Проверки
    check_not_root
    check_dependencies
    check_existing_files
    
    # Выбор режима
    choose_installation_mode
    
    # Генерация конфига
    generate_config
    
    # Создание файлов
    create_project_files
    
    # Установка
    case $INSTALL_MODE in
        docker)
            install_docker
            ;;
        local)
            install_local
            ;;
    esac
    
    # Тестирование
    run_tests
    
    # Итоговые инструкции
    print_post_install
}

# Обработка ошибок
trap 'print_error "Установка прервана"; exit 1' INT TERM

# Запуск
main "$@"
