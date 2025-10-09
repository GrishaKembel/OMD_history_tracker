# 🚀 Шпаргалка - OpenMetadata History Tracker

## ⚡ Быстрый старт

```bash
# Автоматическая установка
chmod +x install.sh
./install.sh

# Или вручную через Docker
docker-compose up -d

# Проверка
curl http://localhost:5000/health
```

## 🔧 Основные команды

### Docker

```bash
# Запуск
docker-compose up -d

# Остановка
docker-compose down

# Рестарт
docker-compose restart webhook_listener

# Логи
docker-compose logs -f webhook_listener

# Последние 100 строк
docker-compose logs --tail=100 webhook_listener

# Статус
docker-compose ps
```

### Локальный запуск

```bash
# Активация виртуального окружения
source venv/bin/activate

# Запуск
python webhook_listener.py

# Запуск в фоне
nohup python webhook_listener.py > webhook.log 2>&1 &

# Остановка
kill $(cat webhook.pid)
```

## 📊 SQL Команды

### Подключение к БД

```bash
# Docker
docker exec -it om_history_db psql -U postgres -d openmetadata_history

# Локально
psql -U postgres -d openmetadata_history
```

### Часто используемые запросы

```sql
-- Последние 10 событий
SELECT * FROM recent_changes LIMIT 10;

-- История конкретной таблицы
SELECT * FROM get_entity_history('mydb.schema.table_name');

-- Все удалённые сущности
SELECT entity_fqn, deleted_by, deleted_at 
FROM deleted_entities 
ORDER BY deleted_at DESC;

-- Топ активных пользователей
SELECT * FROM user_activity_stats 
ORDER BY total_changes DESC LIMIT 10;

-- Изменения за сегодня
SELECT event_type, entity_fqn, updated_by, event_time
FROM metadata_change_events
WHERE DATE(event_time) = CURRENT_DATE
ORDER BY event_time DESC;

-- Количество событий по типам
SELECT event_type, COUNT(*) 
FROM metadata_change_events 
GROUP BY event_type;
```

## 🌐 API Endpoints

### Health Check

```bash
curl http://localhost:5000/health
```

**Ответ:**
```json
{"status": "healthy", "database": "connected"}
```

### Получить события

```bash
# Все события (последние 100)
curl http://localhost:5000/events

# Для конкретной таблицы
curl "http://localhost:5000/events?entity_fqn=mydb.schema.customers"

# По типу события
curl "http://localhost:5000/events?event_type=entityDeleted"

# Ограничить количество
curl "http://localhost:5000/events?limit=50"

# Комбинация фильтров
curl "http://localhost:5000/events?entity_type=table&event_type=entityUpdated&limit=20"
```

### Отправить тестовое событие

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SECRET" \
  -d '{
    "eventType": "entityUpdated",
    "entityFQN": "test.schema.table",
    "userName": "test@example.com"
  }'
```

## 🔐 Настройка Webhook в OpenMetadata

### Шаг за шагом

1. **Откройте OpenMetadata UI** → Settings (⚙️)
2. **Integrations** → **Webhooks** → **Add Webhook**
3. **Заполните форму:**
   - Name: `History Tracker`
   - Endpoint: `http://YOUR_SERVER:5000/webhook`
   - Secret: `ваш_секрет_из_.env`
   - Event Filters: ✅ All или выберите нужные
   - Entity Filters: ✅ All или выберите типы
4. **Save** и включите (toggle ON)
5. **Test** — проверьте отправку

### URL форматы

| Сценарий | URL |
|----------|-----|
| Локальная разработка | `http://localhost:5000/webhook` |
| Docker на том же хосте | `http://host.docker.internal:5000/webhook` |
| Отдельный сервер | `http://192.168.1.100:5000/webhook` |
| С доменом | `https://webhook.yourdomain.com/webhook` |

## 🧪 Тестирование

```bash
# Автоматический тест
python test_webhook.py

# Или вручную измените таблицу в OpenMetadata UI
# и проверьте логи/БД
```

## 🗄️ Структура таблиц

```sql
-- Основные события
\d metadata_change_events

-- Изменения полей
\d field_changes

-- Удалённые сущности
\d deleted_entities
```

## 🔍 Troubleshooting

### Webhook не получает события

```bash
# 1. Проверьте сервис
curl http://localhost:5000/health

# 2. Проверьте логи
docker-compose logs webhook_listener | grep ERROR

# 3. Проверьте настройки webhook в OM UI

# 4. Убедитесь, что URL доступен из контейнера OM
# Для Docker используйте: host.docker.internal
```

### Ошибка подключения к БД

```bash
# Проверьте PostgreSQL
docker ps | grep postgres

# Проверьте .env файл
cat .env

# Попробуйте подключиться
psql -h localhost -U postgres -d openmetadata_history

# Проверьте пароль
PGPASSWORD=your_password psql -h localhost -U postgres
```

### События не сохраняются

```sql
-- Проверьте таблицы
\dt

-- Проверьте права
SELECT current_user;

-- Проверьте последние ошибки в логах
SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction';
```

## 📁 Файлы конфигурации

### .env файл

```bash
DB_HOST=localhost
DB_PORT=5432
DB_NAME=openmetadata_history
DB_USER=postgres
DB_PASSWORD=your_password
WEBHOOK_SECRET=your_secret_key
PORT=5000
```

### docker-compose.yml (минимальный)

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: openmetadata_history
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: your_password
    ports:
      - "5432:5432"
  
  webhook_listener:
    build: .
    environment:
      DB_HOST: postgres
      DB_PORT: 5432
    ports:
      - "5000:5000"
    depends_on:
      - postgres
```

## 🛠️ Обслуживание

### Бэкап БД

```bash
# Создать бэкап
docker exec om_history_db pg_dump -U postgres openmetadata_history > backup_$(date +%Y%m%d).sql

# Восстановить бэкап
docker exec -i om_history_db psql -U postgres openmetadata_history < backup_20251008.sql
```

### Очистка старых данных

```sql
-- Удалить события старше 90 дней
SELECT * FROM cleanup_old_events(90);

-- Вручную
DELETE FROM field_changes 
WHERE event_id IN (
  SELECT event_id FROM metadata_change_events 
  WHERE event_time < NOW() - INTERVAL '90 days'
);

DELETE FROM metadata_change_events 
WHERE event_time < NOW() - INTERVAL '90 days';
```

### Мониторинг размера БД

```sql
-- Размер таблиц
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- Общий размер БД
SELECT pg_size_pretty(pg_database_size('openmetadata_history'));

-- Количество записей
SELECT 
    'metadata_change_events' as table_name,
    COUNT(*) as rows
FROM metadata_change_events
UNION ALL
SELECT 
    'field_changes',
    COUNT(*)
FROM field_changes
UNION ALL
SELECT 
    'deleted_entities',
    COUNT(*)
FROM deleted_entities;
```

## 🔄 Обновление

```bash
# Docker
git pull
docker-compose down
docker-compose build
docker-compose up -d

# Локально
git pull
source venv/bin/activate
pip install -r requirements.txt
pkill -f webhook_listener
python webhook_listener.py &
```

## 📊 Полезные SQL Views

```sql
-- Создать view для быстрого доступа
CREATE VIEW daily_stats AS
SELECT 
    DATE(event_time) as date,
    COUNT(*) as total_events,
    COUNT(DISTINCT entity_fqn) as unique_entities,
    COUNT(DISTINCT updated_by) as active_users
FROM metadata_change_events
WHERE event_time > NOW() - INTERVAL '30 days'
GROUP BY DATE(event_time)
ORDER BY date DESC;

-- Использование
SELECT * FROM daily_stats;
```

## 🔐 Безопасность

### Генерация секрета

```bash
# Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# OpenSSL
openssl rand -base64 32

# /dev/urandom
head -c 32 /dev/urandom | base64
```

### Ограничение доступа

```bash
# Firewall (ufw)
sudo ufw allow from 192.168.1.0/24 to any port 5000

# Docker network isolation
# В docker-compose.yml не публикуйте порт БД наружу
```

### HTTPS через Nginx

```nginx
server {
    listen 443 ssl;
    server_name webhook.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 📈 Примеры анализа

### Кто больше всего работает с метаданными?

```sql
SELECT 
    updated_by,
    COUNT(*) as changes,
    COUNT(DISTINCT DATE(event_time)) as active_days,
    AVG(EXTRACT(EPOCH FROM (MAX(event_time) - MIN(event_time)))/86400)::numeric(10,2) as avg_days_between_changes
FROM metadata_change_events
WHERE updated_by IS NOT NULL
  AND event_time > NOW() - INTERVAL '30 days'
GROUP BY updated_by
ORDER BY changes DESC
LIMIT 10;
```

### Какие таблицы чаще всего меняются?

```sql
SELECT 
    entity_fqn,
    COUNT(*) as change_count,
    COUNT(DISTINCT updated_by) as different_users,
    MAX(event_time) as last_change,
    STRING_AGG(DISTINCT event_type, ', ') as event_types
FROM metadata_change_events
WHERE entity_type = 'table'
  AND event_time > NOW() - INTERVAL '7 days'
GROUP BY entity_fqn
ORDER BY change_count DESC
LIMIT 20;
```

### График активности по дням недели

```sql
SELECT 
    TO_CHAR(event_time, 'Day') as day_of_week,
    COUNT(*) as events
FROM metadata_change_events
WHERE event_time > NOW() - INTERVAL '30 days'
GROUP BY TO_CHAR(event_time, 'Day'), EXTRACT(DOW FROM event_time)
ORDER BY EXTRACT(DOW FROM event_time);
```

### Топ изменяемых полей

```sql
SELECT 
    field_name,
    change_type,
    COUNT(*) as count,
    COUNT(DISTINCT event_id) as unique_events
FROM field_changes
GROUP BY field_name, change_type
ORDER BY count DESC
LIMIT 20;
```

## 🎯 Частые сценарии

### Восстановить удалённую таблицу

```sql
-- Найти удалённую таблицу
SELECT * FROM deleted_entities 
WHERE entity_fqn LIKE '%customers%';

-- Получить её последний snapshot
SELECT last_snapshot 
FROM deleted_entities 
WHERE entity_fqn = 'mydb.public.customers';

-- Скопировать JSON и восстановить через OpenMetadata API
```

### Узнать, кто изменил описание

```sql
SELECT 
    e.entity_fqn,
    e.updated_by,
    e.event_time,
    f.old_value as old_description,
    f.new_value as new_description
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE e.entity_fqn = 'mydb.public.users'
  AND f.field_name = 'description'
ORDER BY e.event_time DESC;
```

### История владельцев таблицы

```sql
SELECT 
    e.event_time,
    e.updated_by as changed_by,
    f.old_value as previous_owner,
    f.new_value as new_owner
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE e.entity_fqn = 'mydb.public.orders'
  AND f.field_name = 'owner'
ORDER BY e.event_time;
```

## 🚨 Алерты и мониторинг

### Настроить алерт на удаление

```python
# В webhook_listener.py добавьте:
def send_alert(event):
    if event.get('eventType') == 'entityDeleted':
        # Slack webhook
        requests.post(
            'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
            json={'text': f"⚠️ Удалена сущность: {event.get('entityFQN')}"}
        )
```

### Мониторинг задержки событий

```sql
-- События, которые пришли с задержкой > 1 минута
SELECT 
    event_id,
    entity_fqn,
    event_time,
    created_at,
    EXTRACT(EPOCH FROM (created_at - event_time)) as delay_seconds
FROM metadata_change_events
WHERE created_at - event_time > INTERVAL '1 minute'
ORDER BY delay_seconds DESC;
```

## 📝 Логирование

### Просмотр логов

```bash
# Docker - последние 100 строк
docker-compose logs --tail=100 webhook_listener

# Docker - следить в реальном времени
docker-compose logs -f webhook_listener

# Docker - с временными метками
docker-compose logs -t webhook_listener

# Локально
tail -f webhook.log

# Grep по ошибкам
docker-compose logs webhook_listener | grep ERROR
```

### Rotation логов (Docker)

Добавьте в `docker-compose.yml`:

```yaml
webhook_listener:
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "5"
```

## 💾 Экспорт данных

### CSV экспорт

```bash
# Из БД в CSV
psql -U postgres -d openmetadata_history -c "\copy (SELECT * FROM metadata_change_events WHERE event_time > NOW() - INTERVAL '30 days') TO '/tmp/events.csv' CSV HEADER"
```

### JSON экспорт

```sql
-- Экспорт в JSON
COPY (
  SELECT json_agg(row_to_json(t))
  FROM (
    SELECT * FROM metadata_change_events
    WHERE event_time > NOW() - INTERVAL '7 days'
  ) t
) TO '/tmp/events.json';
```

## 🔗 Полезные ссылки

- 📖 **Полная документация**: `README.md`
- 🔧 **SQL запросы**: `useful_queries.sql`
- 🧪 **Тестирование**: `test_webhook.py`
- 🚀 **Автоустановка**: `install.sh`

## 💡 Советы

1. **Регулярно делайте бэкапы БД**
2. **Настройте cleanup старых событий** (например, >180 дней)
3. **Мониторьте размер БД** (`SELECT pg_size_pretty(...)`)
4. **Используйте индексы** для часто запрашиваемых полей
5. **Настройте алерты** на критичные изменения
6. **Документируйте** важные изменения метаданных

---

**🎯 Этого достаточно для 95% задач!**

Если нужно больше - смотрите полную документацию в `README.md`