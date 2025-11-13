"""
OpenMetadata Webhook Listener Service
Принимает события изменений из OpenMetadata и сохраняет их в PostgreSQL
"""

from flask import Flask, request, jsonify
import psycopg2
from psycopg2.extras import Json
import logging
from datetime import datetime
import os
from typing import Dict, Any

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Настройки подключения к БД (можно вынести в .env)
DB_CONFIG = {
    'host': os.getenv('DB_HOST', '172.24.64.1'),
    'port': os.getenv('DB_PORT', '5432'),
    'database': os.getenv('DB_NAME', 'openmetadata_history'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'postgres')
}

# Секретный ключ для проверки webhook (настраивается в OM)
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', 'your_secret_key')


def get_db_connection():
    """Создаёт подключение к PostgreSQL"""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Exception as e:
        logger.error(f"Ошибка подключения к БД: {e}")
        raise


def init_database():
    """Инициализация таблиц в БД при первом запуске"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Таблица для хранения событий изменений
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS metadata_change_events (
                id SERIAL PRIMARY KEY,
                event_id VARCHAR(255) UNIQUE,
                event_type VARCHAR(100) NOT NULL,
                event_time TIMESTAMP NOT NULL,
                entity_type VARCHAR(100),
                entity_id VARCHAR(255),
                entity_fqn TEXT,
                entity_name VARCHAR(500),
                change_description TEXT,
                updated_by VARCHAR(255),
                previous_version DECIMAL,
                current_version DECIMAL,
                full_payload JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)

        # Индексы для metadata_change_events
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_entity_fqn 
            ON metadata_change_events(entity_fqn);
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_event_type 
            ON metadata_change_events(event_type);
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_event_time 
            ON metadata_change_events(event_time);
        """)

        # Таблица для хранения конкретных изменений полей
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS field_changes (
                id SERIAL PRIMARY KEY,
                event_id VARCHAR(255) REFERENCES metadata_change_events(event_id),
                field_name VARCHAR(255),
                old_value TEXT,
                new_value TEXT,
                change_type VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)

        # Индексы для field_changes
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_field_changes_event_id 
            ON field_changes(event_id);
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_field_changes_name 
            ON field_changes(field_name);
        """)

        # Таблица для софт-удалённых сущностей
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS deleted_entities (
                id SERIAL PRIMARY KEY,
                entity_id VARCHAR(255) UNIQUE,
                entity_type VARCHAR(100),
                entity_fqn TEXT,
                entity_name VARCHAR(500),
                deleted_at TIMESTAMP,
                deleted_by VARCHAR(255),
                last_snapshot JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)

        # Индексы для deleted_entities
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_entity_type 
            ON deleted_entities(entity_type);
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_deleted_at 
            ON deleted_entities(deleted_at);
        """)

        conn.commit()
        cursor.close()
        conn.close()
        logger.info("База данных инициализирована успешно")

    except Exception as e:
        logger.error(f"Ошибка инициализации БД: {e}")
        conn.rollback()
        cursor.close()
        conn.close()
        raise

def save_change_event(event_data: Dict[str, Any]) -> bool:
    """Сохраняет событие изменения в БД"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        logger.info(f"event_data keys: {event_data.keys()}")
        logger.info(f"Full event_data: {event_data}")
        # Извлекаем основные данные из события
        event_id = event_data.get('id', event_data.get('eventId'))
        event_type = event_data.get('eventType')
        #timestamp = event_data.get('timestamp', datetime.utcnow().isoformat())
        raw_ts = event_data.get('timestamp')

        if isinstance(raw_ts, (int, float)):
            # Если это миллисекунды
            if raw_ts > 10**12:  # значит это ms, не секунды
                timestamp = datetime.fromtimestamp(raw_ts / 1000).isoformat()
            else:
                timestamp = datetime.fromtimestamp(raw_ts).isoformat()

        elif isinstance(raw_ts, str):
            timestamp = raw_ts  # надеемся, что строка уже ISO

        else:
            timestamp = datetime.utcnow().isoformat()

        # Если entity пришёл как JSON-строка - распарсить
        entity = event_data.get('entity', {})
        logger.info(f"Extracted entity: {entity}") #1111111111111111111111111
        logger.info(f"entity type: {type(entity)}, value: {entity}")

        if not entity or (isinstance(entity, dict) and len(entity) == 0):
            logger.warning("Entity пустой, используем данные из верхнего уровня event_data")
            # Создаём псевдо-entity из данных event_data
            entity = {
                'type': event_data.get('entityType'),
                'id': event_data.get('entityId'),
                'fullyQualifiedName': event_data.get('entityFQN') or event_data.get('entityUrn'),
                'name': event_data.get('entityName')
            }
            logger.info(f"Constructed entity from event_data: {entity}")

        if isinstance(entity, str):
            try:
                import json
                entity = json.loads(entity)
                logger.info(f"Entity распарсен из строки: {type(entity)}")
            except:
                logger.warning(f"Не удалось распарсить entity как JSON, используем пустой dict")
                entity = {}

        # Если entity всё ещё не dict - используем пустой
        if not isinstance(entity, dict):
            logger.warning(f"Entity не является dict: {type(entity)}")
            entity = {}
        # =======================================

        entity_type = entity.get('type') or event_data.get('entityType')
        entity_id = entity.get('id') or event_data.get('entityId')
        entity_fqn = entity.get('fullyQualifiedName') or event_data.get('entityFQN') or event_data.get('entityUrn')
        entity_name = entity.get('name') or event_data.get('entityName')


        # ===== ИСПРАВЛЕНИЕ: Парсинг changeDescription =====
        change_desc = event_data.get('changeDescription', {})

        # Если changeDescription пришёл как JSON-строка - распарсить
        if isinstance(change_desc, str):
            try:
                import json
                change_desc = json.loads(change_desc)
                logger.info(f"ChangeDescription распарсен из строки")
            except:
                logger.warning(f"Не удалось распарсить changeDescription как JSON")
                change_desc = {}

        # Если не dict - используем пустой
        if not isinstance(change_desc, dict):
            change_desc = {}
        # ==================================================

        updated_by = event_data.get('updatedBy') or event_data.get('userName')
        previous_version = event_data.get('previousVersion')
        current_version = event_data.get('currentVersion')

        # Логируем что получили для отладки
        logger.info(f"Обработка события: type={event_type}, entity_type={entity_type}, fqn={entity_fqn}, name={entity_name}")

        # Сохраняем основное событие
        cursor.execute("""
            INSERT INTO metadata_change_events
            (event_id, event_type, event_time, entity_type, entity_id, entity_fqn,
             entity_name, change_description, updated_by, previous_version,
             current_version, full_payload)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (event_id) DO NOTHING
        """, (
            event_id, event_type, timestamp, entity_type, entity_id, entity_fqn,
            entity_name, str(change_desc), updated_by, previous_version,
            current_version, Json(event_data)
        ))

        # Сохраняем детали изменений полей
        fields_added = change_desc.get('fieldsAdded', []) if isinstance(change_desc, dict) else []
        fields_updated = change_desc.get('fieldsUpdated', []) if isinstance(change_desc, dict) else []
        fields_deleted = change_desc.get('fieldsDeleted', []) if isinstance(change_desc, dict) else []

        for field in fields_added:
            if isinstance(field, dict):
                cursor.execute("""
                    INSERT INTO field_changes (event_id, field_name, new_value, change_type)
                    VALUES (%s, %s, %s, %s)
                """, (event_id, field.get('name'), str(field.get('newValue')), 'added'))

        for field in fields_updated:
            if isinstance(field, dict):
                cursor.execute("""
                    INSERT INTO field_changes (event_id, field_name, old_value, new_value, change_type)
                    VALUES (%s, %s, %s, %s, %s)
                """, (event_id, field.get('name'), str(field.get('oldValue')),
                      str(field.get('newValue')), 'updated'))

        for field in fields_deleted:
            if isinstance(field, dict):
                cursor.execute("""
                    INSERT INTO field_changes (event_id, field_name, old_value, change_type)
                    VALUES (%s, %s, %s, %s)
                """, (event_id, field.get('name'), str(field.get('oldValue')), 'deleted'))

        # Если это событие удаления - сохраняем в таблицу удалённых
        if event_type == 'entityDeleted':
            cursor.execute("""
                INSERT INTO deleted_entities
                (entity_id, entity_type, entity_fqn, entity_name, deleted_at,
                 deleted_by, last_snapshot)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (entity_id) DO UPDATE SET
                    deleted_at = EXCLUDED.deleted_at,
                    deleted_by = EXCLUDED.deleted_by
            """, (
                entity_id, entity_type, entity_fqn, entity_name, timestamp,
                updated_by, Json(entity if isinstance(entity, dict) else {})
            ))

        conn.commit()
        cursor.close()
        conn.close()

        logger.info(f"✓ Событие {event_id} ({event_type}) сохранено для {entity_fqn}")
        return True

    except Exception as e:
        logger.error(f"✗ Ошибка сохранения события: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return False


@app.route('/health', methods=['GET'])
def health_check():
    """Проверка работоспособности сервиса"""
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected'}), 200
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503


@app.route('/webhook', methods=['POST'])
def webhook_receiver():
    """
    Основной endpoint для приёма webhook'ов от OpenMetadata
    """
    try:
        # Проверка секретного ключа (если настроено в OM)
        auth_header = request.headers.get('Authorization')
        if WEBHOOK_SECRET and auth_header != f"Bearer {WEBHOOK_SECRET}":
            logger.warning("Неверный секретный ключ webhook")
            return jsonify({'error': 'Unauthorized'}), 401
        
        # Получаем данные события
        event_data = request.json
        
        if not event_data:
            return jsonify({'error': 'Empty payload'}), 400
        
        logger.info(f"Получено событие: {event_data.get('eventType')} для {event_data.get('entityType')}")
        
        # Сохраняем событие в БД
        success = save_change_event(event_data)
        
        if success:
            return jsonify({
                'status': 'success',
                'message': 'Event processed and saved'
            }), 200
        else:
            return jsonify({
                'status': 'error',
                'message': 'Failed to save event'
            }), 500
            
    except Exception as e:
        logger.error(f"Ошибка обработки webhook: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/events', methods=['GET'])
def get_events():
    """API для получения сохранённых событий (для отладки)"""
    try:
        entity_fqn = request.args.get('entity_fqn')
        event_type = request.args.get('event_type')
        limit = int(request.args.get('limit', 100))
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        query = "SELECT * FROM metadata_change_events WHERE 1=1"
        params = []
        
        if entity_fqn:
            query += " AND entity_fqn = %s"
            params.append(entity_fqn)
        
        if event_type:
            query += " AND event_type = %s"
            params.append(event_type)
        
        query += " ORDER BY event_time DESC LIMIT %s"
        params.append(limit)
        
        cursor.execute(query, params)
        
        columns = [desc[0] for desc in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'count': len(results),
            'events': results
        }), 200
        
    except Exception as e:
        logger.error(f"Ошибка получения событий: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    # Инициализируем БД при запуске
    try:
        init_database()
    except Exception as e:
        logger.error(f"Не удалось инициализировать БД: {e}")
        exit(1)
    
    # Запускаем Flask-сервер
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
