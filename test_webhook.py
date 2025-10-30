#!/usr/bin/env python3
"""
Скрипт для тестирования webhook приёмника
Отправляет тестовые события, как это делает OpenMetadata
"""

import requests
import json
from datetime import datetime
import sys

# URL вашего webhook сервиса
WEBHOOK_URL = "http://localhost:5000/webhook"
WEBHOOK_SECRET = "your_secret_key_here"  # Замените на ваш секрет из .env

def send_test_event(event_type="entityUpdated"):
    """Отправляет тестовое событие"""
    
    # Пример события, максимально близкий к реальному от OpenMetadata
    test_events = {
        "entityCreated": {
            "id": "test-event-created-001",
            "eventType": "entityCreated",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "entityType": "table",
            "entityId": "550e8400-e29b-41d4-a716-446655440000",
            "entityFQN": "sample_database.sample_schema.test_table",
            "userName": "test_user@example.com",
            "entity": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "type": "table",
                "name": "test_table",
                "fullyQualifiedName": "sample_database.sample_schema.test_table",
                "description": "Тестовая таблица для проверки webhook",
                "columns": [
                    {"name": "id", "dataType": "INT"},
                    {"name": "name", "dataType": "VARCHAR"}
                ]
            },
            "currentVersion": 0.1
        },
        
        "entityUpdated": {
            "id": "test-event-updated-002",
            "eventType": "entityUpdated",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "entityType": "table",
            "entityId": "550e8400-e29b-41d4-a716-446655440000",
            "entityFQN": "sample_database.sample_schema.test_table",
            "userName": "test_user@example.com",
            "previousVersion": 0.1,
            "currentVersion": 0.2,
            "entity": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "type": "table",
                "name": "test_table",
                "fullyQualifiedName": "sample_database.sample_schema.test_table",
                "description": "Обновлённое описание тестовой таблицы"
            },
            "changeDescription": {
                "fieldsAdded": [],
                "fieldsUpdated": [
                    {
                        "name": "description",
                        "oldValue": "Тестовая таблица для проверки webhook",
                        "newValue": "Обновлённое описание тестовой таблицы"
                    },
                    {
                        "name": "tags",
                        "oldValue": [],
                        "newValue": ["PII.Sensitive", "Tier.Gold"]
                    }
                ],
                "fieldsDeleted": []
            }
        },
        
        "entityDeleted": {
            "id": "test-event-deleted-003",
            "eventType": "entityDeleted",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "entityType": "table",
            "entityId": "550e8400-e29b-41d4-a716-446655440000",
            "entityFQN": "sample_database.sample_schema.test_table",
            "userName": "admin@example.com",
            "entity": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "type": "table",
                "name": "test_table",
                "fullyQualifiedName": "sample_database.sample_schema.test_table",
                "description": "Обновлённое описание тестовой таблицы",
                "deleted": True
            },
            "previousVersion": 0.2
        }
    }
    
    event_data = test_events.get(event_type)
    if not event_data:
        print(f" Неизвестный тип события: {event_type}")
        return False
    
    headers = {
        "Content-Type": "application/json"
    }
    
    try:
        print(f"\n📤 Отправка тестового события: {event_type}")
        print(f"   Entity: {event_data.get('entityFQN')}")
        
        response = requests.post(
            WEBHOOK_URL,
            json=event_data,
            headers=headers,
            timeout=10
        )
        
        if response.status_code == 200:
            print(f" Событие успешно обработано!")
            print(f"   Response: {response.json()}")
            return True
        else:
            print(f" Ошибка: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except requests.exceptions.ConnectionError:
        print(f" Не удалось подключиться к {WEBHOOK_URL}")
        print(f"   Проверьте, что сервис запущен: curl http://localhost:5000/health")
        return False
    except Exception as e:
        print(f" Ошибка: {e}")
        return False


def check_health():
    """Проверяет работоспособность сервиса"""
    try:
        response = requests.get("http://localhost:5000/health", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f" Сервис работает")
            print(f"   Status: {data.get('status')}")
            print(f"   Database: {data.get('database')}")
            return True
        else:
            print(f" Сервис вернул статус: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f" Сервис не доступен по адресу http://localhost:5000")
        print(f"   Запустите сервис: python webhook_listener.py")
        return False
    except Exception as e:
        print(f" Ошибка проверки: {e}")
        return False


def check_saved_events():
    """Проверяет сохранённые события через API"""
    try:
        response = requests.get("http://localhost:5000/events?limit=5", timeout=5)
        if response.status_code == 200:
            data = response.json()
            count = data.get('count', 0)
            print(f"\n Сохранено событий в БД: {count}")
            
            if count > 0:
                print("\nПоследние события:")
                for event in data.get('events', [])[:5]:
                    print(f"  - {event.get('event_type')}: {event.get('entity_fqn')}")
                    print(f"    Время: {event.get('event_time')}")
                    print(f"    Пользователь: {event.get('updated_by')}")
                    print()
            return True
        else:
            print(f" Ошибка получения событий: {response.status_code}")
            return False
    except Exception as e:
        print(f" Ошибка: {e}")
        return False


def main():
    print("=" * 60)
    print(" Тестирование OpenMetadata Webhook Listener")
    print("=" * 60)
    
    # Шаг 1: Проверка работоспособности
    print("\n[1/4] Проверка работоспособности сервиса...")
    if not check_health():
        print("\n  Сервис не запущен. Запустите его командой:")
        print("   python webhook_listener.py")
        sys.exit(1)
    
    # Шаг 2: Отправка тестовых событий
    print("\n[2/4] Отправка тестовых событий...")
    
    success_count = 0
    events_to_test = ["entityCreated", "entityUpdated", "entityDeleted"]
    
    for event_type in events_to_test:
        if send_test_event(event_type):
            success_count += 1
    
    print(f"\n   Успешно отправлено: {success_count}/{len(events_to_test)}")
    
    # Шаг 3: Проверка сохранённых событий
    print("\n[3/4] Проверка сохранённых событий...")
    check_saved_events()
    
    # Шаг 4: Итоги
    print("\n[4/4] Результаты тестирования")
    print("=" * 60)
    
    if success_count == len(events_to_test):
        print(" Все тесты пройдены успешно!")
        print("\nСледующие шаги:")
        print("1. Настройте webhook в OpenMetadata UI")
        print("2. Измените метаданные любой таблицы")
        print("3. Проверьте, что события сохраняются в БД")
        print("\nПроверить БД можно командой:")
        print("  psql -U postgres -d openmetadata_history")
        print('  SELECT * FROM metadata_change_events ORDER BY event_time DESC LIMIT 5;')
    else:
        print(f"  Пройдено тестов: {success_count}/{len(events_to_test)}")
        print("\nПроверьте:")
        print("1. Сервис запущен: python webhook_listener.py")
        print("2. PostgreSQL доступна")
        print("3. Настройки в .env файле корректны")
    
    print("=" * 60)


if __name__ == "__main__":
    main()
