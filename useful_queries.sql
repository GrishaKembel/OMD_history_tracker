-- ==================================================================
-- ПОЛЕЗНЫЕ SQL ЗАПРОСЫ ДЛЯ АНАЛИЗА ИСТОРИИ МЕТАДАННЫХ
-- ==================================================================

-- Подключение к БД:
-- psql -U postgres -d openmetadata_history -f useful_queries.sql

\echo '\n=== ОБЩАЯ СТАТИСТИКА ==='

-- Общее количество событий
SELECT 
    'Всего событий' as metric,
    COUNT(*) as value
FROM metadata_change_events;

-- События за последние 7 дней
SELECT 
    'События за последние 7 дней' as metric,
    COUNT(*) as value
FROM metadata_change_events
WHERE event_time > NOW() - INTERVAL '7 days';

-- Распределение по типам событий
SELECT 
    event_type,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM metadata_change_events
GROUP BY event_type
ORDER BY count DESC;


\echo '\n=== ТОП АКТИВНЫХ ПОЛЬЗОВАТЕЛЕЙ ==='

-- Кто больше всего меняет метаданные
SELECT 
    updated_by,
    COUNT(*) as changes_count,
    COUNT(DISTINCT entity_fqn) as unique_entities,
    MIN(event_time) as first_change,
    MAX(event_time) as last_change
FROM metadata_change_events
WHERE updated_by IS NOT NULL
GROUP BY updated_by
ORDER BY changes_count DESC
LIMIT 10;


\echo '\n=== САМЫЕ ИЗМЕНЯЕМЫЕ СУЩНОСТИ ==='

-- Таблицы с наибольшим количеством изменений
SELECT 
    entity_fqn,
    entity_type,
    COUNT(*) as change_count,
    COUNT(DISTINCT updated_by) as users_modified,
    MAX(event_time) as last_modified
FROM metadata_change_events
WHERE entity_type = 'table'
GROUP BY entity_fqn, entity_type
ORDER BY change_count DESC
LIMIT 20;


\echo '\n=== ИСТОРИЯ КОНКРЕТНОЙ ТАБЛИЦЫ ==='

-- Замените 'your.table.name' на реальное имя таблицы
-- Все изменения конкретной таблицы
CREATE OR REPLACE FUNCTION get_entity_history(p_entity_fqn TEXT)
RETURNS TABLE (
    event_time TIMESTAMP,
    event_type VARCHAR,
    version DECIMAL,
    changed_by VARCHAR,
    description TEXT,
    field_changes_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.event_time,
        e.event_type,
        e.current_version,
        e.updated_by,
        e.change_description,
        COUNT(f.id) as field_changes_count
    FROM metadata_change_events e
    LEFT JOIN field_changes f ON e.event_id = f.event_id
    WHERE e.entity_fqn = p_entity_fqn
    GROUP BY e.event_time, e.event_type, e.current_version, 
             e.updated_by, e.change_description
    ORDER BY e.event_time DESC;
END;
$$ LANGUAGE plpgsql;

-- Пример использования:
-- SELECT * FROM get_entity_history('mydb.schema.customers');


\echo '\n=== ИЗМЕНЕНИЯ ПО ТИПАМ ПОЛЕЙ ==='

-- Какие поля чаще всего меняются
SELECT 
    field_name,
    change_type,
    COUNT(*) as change_count
FROM field_changes
GROUP BY field_name, change_type
ORDER BY change_count DESC
LIMIT 20;


\echo '\n=== ИЗМЕНЕНИЯ ОПИСАНИЙ ==='

-- Все изменения описаний таблиц
SELECT 
    e.entity_fqn,
    e.updated_by,
    e.event_time,
    SUBSTRING(f.old_value, 1, 50) as old_description,
    SUBSTRING(f.new_value, 1, 50) as new_description
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE f.field_name = 'description'
ORDER BY e.event_time DESC
LIMIT 20;


\echo '\n=== ИЗМЕНЕНИЯ ТЕГОВ ==='

-- Все изменения тегов
SELECT 
    e.entity_fqn,
    e.entity_type,
    e.updated_by,
    e.event_time,
    f.old_value as old_tags,
    f.new_value as new_tags
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE f.field_name LIKE '%tag%'
ORDER BY e.event_time DESC
LIMIT 20;


\echo '\n=== УДАЛЁННЫЕ СУЩНОСТИ ==='

-- Все удалённые сущности
SELECT 
    entity_type,
    entity_fqn,
    entity_name,
    deleted_by,
    deleted_at,
    AGE(NOW(), deleted_at) as deleted_ago
FROM deleted_entities
ORDER BY deleted_at DESC;

-- Удалённые сущности за последний месяц
SELECT 
    entity_type,
    COUNT(*) as deleted_count
FROM deleted_entities
WHERE deleted_at > NOW() - INTERVAL '30 days'
GROUP BY entity_type
ORDER BY deleted_count DESC;


\echo '\n=== АКТИВНОСТЬ ПО ДНЯМ ==='

-- События по дням за последний месяц
SELECT 
    DATE(event_time) as date,
    COUNT(*) as events_count,
    COUNT(DISTINCT entity_fqn) as unique_entities,
    COUNT(DISTINCT updated_by) as active_users
FROM metadata_change_events
WHERE event_time > NOW() - INTERVAL '30 days'
GROUP BY DATE(event_time)
ORDER BY date DESC;


\echo '\n=== АКТИВНОСТЬ ПО ЧАСАМ ==='

-- Пиковые часы активности
SELECT 
    EXTRACT(HOUR FROM event_time) as hour,
    COUNT(*) as events_count
FROM metadata_change_events
WHERE event_time > NOW() - INTERVAL '7 days'
GROUP BY EXTRACT(HOUR FROM event_time)
ORDER BY hour;


\echo '\n=== АУДИТ: ИЗМЕНЕНИЯ ЗА СЕГОДНЯ ==='

-- Все изменения за сегодня
SELECT 
    event_time,
    event_type,
    entity_type,
    entity_fqn,
    updated_by
FROM metadata_change_events
WHERE DATE(event_time) = CURRENT_DATE
ORDER BY event_time DESC;


\echo '\n=== ВОССТАНОВЛЕНИЕ: ПОСЛЕДНЕЕ СОСТОЯНИЕ ПЕРЕД УДАЛЕНИЕМ ==='

-- Получить snapshot удалённой сущности
CREATE OR REPLACE FUNCTION get_deleted_entity_snapshot(p_entity_fqn TEXT)
RETURNS JSONB AS $$
DECLARE
    snapshot JSONB;
BEGIN
    SELECT last_snapshot INTO snapshot
    FROM deleted_entities
    WHERE entity_fqn = p_entity_fqn
    ORDER BY deleted_at DESC
    LIMIT 1;
    
    RETURN snapshot;
END;
$$ LANGUAGE plpgsql;

-- Пример использования:
-- SELECT get_deleted_entity_snapshot('mydb.schema.deleted_table');


\echo '\n=== СРАВНЕНИЕ ВЕРСИЙ ==='

-- Сравнить две последовательные версии сущности
CREATE OR REPLACE FUNCTION compare_versions(
    p_entity_fqn TEXT,
    p_version1 DECIMAL,
    p_version2 DECIMAL
)
RETURNS TABLE (
    field_name VARCHAR,
    version1_value TEXT,
    version2_value TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.field_name,
        f.old_value as version1_value,
        f.new_value as version2_value
    FROM metadata_change_events e
    JOIN field_changes f ON e.event_id = f.event_id
    WHERE e.entity_fqn = p_entity_fqn
      AND e.previous_version = p_version1
      AND e.current_version = p_version2;
END;
$$ LANGUAGE plpgsql;


\echo '\n=== ПОИСК КОНКРЕТНЫХ ИЗМЕНЕНИЙ ==='

-- Найти все изменения owner
SELECT 
    e.entity_fqn,
    e.entity_type,
    e.event_time,
    e.updated_by,
    f.old_value as old_owner,
    f.new_value as new_owner
FROM metadata_change_events e
JOIN field_changes f ON e.event_id = f.event_id
WHERE f.field_name = 'owner'
ORDER BY e.event_time DESC;


\echo '\n=== СОЗДАНИЕ VIEW ДЛЯ ЧАСТЫХ ЗАПРОСОВ ==='

-- View: Последние изменения
CREATE OR REPLACE VIEW recent_changes AS
SELECT 
    e.event_time,
    e.event_type,
    e.entity_type,
    e.entity_fqn,
    e.entity_name,
    e.updated_by,
    COUNT(f.id) as fields_changed
FROM metadata_change_events e
LEFT JOIN field_changes f ON e.event_id = f.event_id
WHERE e.event_time > NOW() - INTERVAL '7 days'
GROUP BY e.event_id, e.event_time, e.event_type, e.entity_type, 
         e.entity_fqn, e.entity_name, e.updated_by
ORDER BY e.event_time DESC;

-- View: Статистика по пользователям
CREATE OR REPLACE VIEW user_activity_stats AS
SELECT 
    updated_by,
    COUNT(*) as total_changes,
    COUNT(DISTINCT entity_fqn) as unique_entities,
    COUNT(DISTINCT DATE(event_time)) as active_days,
    MIN(event_time) as first_activity,
    MAX(event_time) as last_activity
FROM metadata_change_events
WHERE updated_by IS NOT NULL
GROUP BY updated_by;

-- View: Статистика по типам сущностей
CREATE OR REPLACE VIEW entity_type_stats AS
SELECT 
    entity_type,
    COUNT(DISTINCT entity_fqn) as unique_entities,
    COUNT(*) as total_changes,
    MAX(event_time) as last_change
FROM metadata_change_events
WHERE entity_type IS NOT NULL
GROUP BY entity_type;


\echo '\n=== ОЧИСТКА СТАРЫХ ДАННЫХ ==='

-- Функция для очистки событий старше N дней
CREATE OR REPLACE FUNCTION cleanup_old_events(days_to_keep INTEGER DEFAULT 90)
RETURNS TABLE (
    deleted_events BIGINT,
    deleted_field_changes BIGINT
) AS $$
DECLARE
    v_deleted_events BIGINT;
    v_deleted_changes BIGINT;
    cutoff_date TIMESTAMP;
BEGIN
    cutoff_date := NOW() - (days_to_keep || ' days')::INTERVAL;
    
    -- Удаляем field_changes для старых событий
    DELETE FROM field_changes
    WHERE event_id IN (
        SELECT event_id FROM metadata_change_events
        WHERE event_time < cutoff_date
    );
    GET DIAGNOSTICS v_deleted_changes = ROW_COUNT;
    
    -- Удаляем старые события
    DELETE FROM metadata_change_events
    WHERE event_time < cutoff_date;
    GET DIAGNOSTICS v_deleted_events = ROW_COUNT;
    
    RETURN QUERY SELECT v_deleted_events, v_deleted_changes;
END;
$$ LANGUAGE plpgsql;

-- Пример: удалить события старше 180 дней
-- SELECT * FROM cleanup_old_events(180);


\echo '\n=== ИНДЕКСЫ ДЛЯ ОПТИМИЗАЦИИ ==='

-- Дополнительные индексы для ускорения запросов
CREATE INDEX IF NOT EXISTS idx_event_time_desc 
    ON metadata_change_events(event_time DESC);

CREATE INDEX IF NOT EXISTS idx_entity_type_fqn 
    ON metadata_change_events(entity_type, entity_fqn);

CREATE INDEX IF NOT EXISTS idx_updated_by_time 
    ON metadata_change_events(updated_by, event_time);

CREATE INDEX IF NOT EXISTS idx_field_changes_name 
    ON field_changes(field_name, change_type);


\echo '\n=== ГОТОВО ==='
\echo 'Все функции и view созданы.'
\echo 'Используйте: SELECT * FROM recent_changes;'
