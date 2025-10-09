# 📚 OpenMetadata History Tracker

Система для автоматического сохранения истории всех изменений метаданных в OpenMetadata через webhooks.

## 🎯 Что это даёт

- ✅ **Полная история изменений** — каждое изменение описания, тегов, владельца сохраняется
- ✅ **Архив удалённых данных** — можно восстановить информацию об удалённых таблицах/дашбордах
- ✅ **Аудит действий** — кто, когда и что изменил
- ✅ **Сравнение версий** — посмотреть разницу между версиями сущности
- ✅ **API для запросов** — получить историю программно

## 🚀 Быстрый старт

### 1. Клонируйте файлы проекта

Вам нужны:
- `webhook_listener.py` — основной сервис
- `requirements.txt` — зависимости Python
- `.env.example` — пример конфигурации
- `docker-compose.yml` — для запуска через Docker
- `Dockerfile` — образ приложения

### 2. Выберите способ запуска

#### Вариант A: Docker (рекомендуется)

```bash
# 1. Отредактируйте docker-compose.yml - замените пароли
nano docker-compose.yml

# 2. Запустите
docker-compose up -d

# 3. Проверьте
curl http://localhost:5000/health
```

#### Вариант B: Локально

```bash
# 1. Создайте виртуальное окружение
python -m venv venv
source venv/bin/activate

# 2. Установите зависимости
pip install -r requirements.txt

# 3. Настройте конфигурацию
cp .env.example .env
nano .env  # Замените значения

# 4. Запустите PostgreSQL (если ещё не запущен)

# 5. Запустите сервис
python webhook_listener.py
```

### 3. Настройте Webhook в OpenMetadata

1. Откройте OpenMetadata UI → **Settings** → **Integrations** → **Webhooks**
2. Нажмите **"Add Webhook"**
3. Заполните:
   - **Name**: `History Tracker`
   - **Endpoint URL**: `http://YOUR_SERVER:5000/webhook`
   - **Secret Key**: ваш секрет из `.env`
   - **Event Filters**: выберите `entityCreated`, `entityUpdated`, `entityDeleted`
   - **Entity Filters**: выберите типы сущностей или "All"
4. Нажмите **Save** и включите webhook

### 4. Протестируйте

```bash
# Автоматический тест
python test_webhook.py

# Или вручную измените любую таблицу в OpenMetadata
# и проверьте логи:
docker-compose logs -f webhook_listener
```

## 📊 Как использовать

### Через SQL

```bash
# Подключитесь к БД
psql -U postgres -d openmetadata_history

# Посмотрите последние изменения
SELECT * FROM recent_changes;

# История конкретной таблицы
SELECT * FROM get_entity_history('mydb.schema.customers');

# Все удалённые сущности
SELECT * FROM deleted_entities ORDER BY deleted_at DESC;
```

Больше запросов в файле `useful_queries.sql`

### Через API

```bash
# Все события
curl http://localhost:5000/events

# Для конкретной таблицы
curl "http://localhost:5000/events?entity_fqn=mydb.schema.table1"

# Только удаления
curl "http://localhost:5000/events?event_type=entityDeleted"

# Последние 50
curl "http://localhost:5000/events?limit=50"
```

## 📁 Структура проекта

```
openmetadata-history/
├── webhook_listener.py      # Основной сервис
├── requirements.txt          # Python зависимости
├── .env.example             # Пример конфигурации
├── docker-compose.yml       # Docker конфигурация
├── Dockerfile               # Docker образ
├── test_webhook.py          # Скрипт тестирования
├── useful_queries.sql       # Полезные SQL запросы
└── README.md               # Эта инструкция
```

## 🗄️ Структура БД

### `metadata_change_events`
Все события изменений:
- `event_id` — уникальный ID события
- `event_type` — тип: entityCreated/Updated/Deleted
- `entity_fqn` — полное имя сущности (например, `mydb.schema.table`)
- `entity_type` — тип: table, dashboard, pipeline и т.д.
- `updated_by` — кто внёс изменение
- `event_time` — когда произошло
- `full_payload` — полный JSON события

### `field_changes`
Детальные изменения полей:
- `field_name` — название поля (description, tags, owner)
- `old_value` — предыдущее значение
- `new_value` — новое значение
- `change_type` — added/updated/deleted

### `deleted_entities`
Архив удалённых сущностей:
- `entity_fqn` — что было удалено
- `deleted_at` — когда удалено
- `deleted_by` — кем удалено
- `last_snapshot` — полное состояние перед удалением (JSON)

## 🔍 Примеры использования

### Найти все изменения конкретной таблицы

```sql
SELECT 
    event_time,
    event_type,
    updated_by,
    change_description
FROM metadata_change_events
WHERE entity_fqn = 'sample_db.public.customers'
ORDER BY event_time DESC;
```

### Узнать, кто удалил таблицу

```sql
SELECT 
    entity_fqn,
    deleted_by,
    deleted_at,
    last_snapshot
FROM deleted_entities
WHERE entity_fqn LIKE '%customers%';
```

### Посмотреть историю изменения описаний

```sql
SELECT 
    e.entity_fqn,
    e.updated_by,
    e.event_time,
    f.old_value as old_description,
    f.new_value as new_description
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE f.field_name = 'description'
ORDER BY e.event_time DESC;
```

### Самые активные пользователи

```sql
SELECT * FROM user_activity_stats
ORDER BY total_changes DESC
LIMIT 10;
```

## 🛠️ Настройка и конфигурация

### Переменные окружения (.env)

```bash
# База данных
DB_HOST=localhost           # Хост PostgreSQL
DB_PORT=5432               # Порт PostgreSQL
DB_NAME=openmetadata_history  # Имя БД
DB_USER=postgres           # Пользователь
DB_PASSWORD=your_password  # Пароль

# Безопасность
WEBHOOK_SECRET=your_secret_key  # Секрет для проверки webhook

# Сервис
PORT=5000                  # Порт Flask приложения
```

### Настройка webhook в OpenMetadata

**URL форматы для разных сценариев:**

- **Локальная разработка**: `http://localhost:5000/webhook`
- **Docker на том же хосте**: `http://host.docker.internal:5000/webhook`
- **Отдельный сервер**: `http://your-server-ip:5000/webhook`
- **С reverse proxy**: `https://your-domain.com/webhook`

**Важно**: Убедитесь, что URL доступен из контейнера OpenMetadata!

## 📈 Мониторинг и обслуживание

### Проверка здоровья сервиса

```bash
curl http://localhost:5000/health
```

Ответ должен быть:
```json
{
  "status": "healthy",
  "database": "connected"
}
```

### Просмотр логов

```bash
# Docker
docker-compose logs -f webhook_listener

# Локально
# Логи выводятся в терминал
```

### Очистка старых данных

```sql
-- Удалить события старше 180 дней
SELECT * FROM cleanup_old_events(180);
```

### Мониторинг размера БД

```sql
-- Размер таблиц
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## 🔧 Troubleshooting

### Проблема: Webhook не получает события

**Диагностика:**
```bash
# 1. Проверьте, что сервис запущен
curl http://localhost:5000/health

# 2. Проверьте логи
docker-compose logs webhook_listener

# 3. Проверьте настройки webhook в OpenMetadata UI
# Settings → Integrations → Webhooks → ваш webhook → Test
```

**Решения:**
- Убедитесь, что URL доступен из контейнера OpenMetadata
- Проверьте firewall/security groups
- Для Docker: используйте `host.docker.internal` вместо `localhost`

### Проблема: Ошибка подключения к БД

```bash
# Проверьте PostgreSQL
docker ps | grep postgres

# Попробуйте подключиться вручную
psql -h localhost -U postgres -d openmetadata_history

# Проверьте credentials в .env
cat .env
```

### Проблема: События не сохраняются

**Проверьте логи:**
```bash
docker-compose logs webhook_listener | grep ERROR
```

**Проверьте таблицы:**
```sql
-- Подключитесь к БД
psql -U postgres -d openmetadata_history

-- Проверьте структуру
\dt

-- Должны быть:
-- metadata_change_events
-- field_changes
-- deleted_entities
```

## 🔐 Безопасность для продакшена

### 1. Используйте сильные пароли

```bash
# Генерация секрета
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

### 2. Используйте HTTPS

Настройте reverse proxy (Nginx/Traefik):
```nginx
server {
    listen 443 ssl;
    server_name webhook.yourdomain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. Ограничьте доступ к БД

```bash
# В docker-compose.yml уберите публикацию порта БД
# Закомментируйте:
# ports:
#   - "5432:5432"
```

### 4. Настройте бэкапы

```bash
# Автоматический бэкап через cron
0 2 * * * pg_dump -U postgres openmetadata_history > /backups/om_history_$(date +\%Y\%m\%d).sql
```

### 5. Rotation логов

Добавьте в `docker-compose.yml`:
```yaml
webhook_listener:
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
```

## 📊 Расширения и улучшения

### 1. Добавить уведомления

Интегрируйте отправку в Slack/Email при критичных изменениях:

```python
# В webhook_listener.py добавьте:
def send_alert(event):
    if event.get('eventType') == 'entityDeleted':
        # Отправить в Slack
        requests.post(SLACK_WEBHOOK, json={
            'text': f"🚨 Удалена сущность: {event.get('entityFQN')}"
        })
```

### 2. Grafana Dashboard

Создайте визуализацию метрик:
- Количество изменений по времени
- Активность пользователей
- Топ изменяемых таблиц

### 3. Восстановление из истории

Добавьте функцию для восстановления старых версий:

```python
@app.route('/restore/<entity_id>/<version>', methods=['POST'])
def restore_version(entity_id, version):
    # Получить snapshot из БД
    # Отправить PUT запрос в OpenMetadata API
    pass
```

### 4. Экспорт отчётов

```python
@app.route('/export', methods=['GET'])
def export_report():
    # Генерация CSV/Excel отчёта
    # За определённый период
    pass
```

## 📚 Дополнительные ресурсы

- [OpenMetadata Webhooks Documentation](https://docs.open-metadata.org/latest/developers/webhooks)
- [OpenMetadata API Reference](https://docs.open-metadata.org/latest/api-reference/overview)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## 🤝 Поддержка

При возникновении проблем:

1. Проверьте секцию **Troubleshooting** выше
2. Запустите тестовый скрипт: `python test_webhook.py`
3. Проверьте логи: `docker-compose logs -f`
4. Убедитесь, что версии совместимы

## 📝 Changelog

### v1.0.0 (2025-10-08)
- ✅ Первая версия
- ✅ Поддержка всех типов событий OpenMetadata
- ✅ Сохранение истории в PostgreSQL
- ✅ API для запросов
- ✅ Docker поддержка
- ✅ Готовые SQL запросы

## 📄 Лицензия

MIT License - используйте свободно для личных и коммерческих проектов.

---

**Разработано для упрощения работы с историей метаданных в OpenMetadata**

🌟 Если проект полезен, поставьте звезду!