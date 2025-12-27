## Архитектура микросервисов

### Общая схема системы

```
┌─────────────────┐
│  Telegram API   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│              API Gateway / Bot Service                  │
│         (точка входа для всех команд бота)             │
└──────┬──────────────────┬───────────────────┬──────────┘
       │                  │                   │
       ▼                  ▼                   ▼
┌─────────────┐   ┌──────────────┐   ┌──────────────┐
│Subscription │   │  Ban Event   │   │    User      │
│  Service    │   │   Service    │   │  Service     │
└──────┬──────┘   └──────┬───────┘   └──────┬───────┘
       │                  │                   │
       │                  ▼                   │
       │          ┌──────────────┐            │
       │          │ Sync Service │            │
       │          └──────┬───────┘            │
       │                 │                    │
       ▼                 ▼                    ▼
┌──────────────────────────────────────────────────┐
│            Message Queue (RabbitMQ/Kafka)        │
└──────────────────────────────────────────────────┘
       │                 │                    │
       ▼                 ▼                    ▼
┌─────────────┐   ┌──────────────┐   ┌──────────────┐
│Subscription │   │  Ban Event   │   │    User      │
│     DB      │   │      DB      │   │      DB      │
└─────────────┘   └──────────────┘   └──────────────┘
```

### Список микросервисов

1. **API Gateway / Bot Service** - точка входа, обработка команд
2. **Subscription Service** - управление подписками
3. **User Service** - управление пользователями и администраторами
4. **Ban Event Service** - отслеживание и регистрация банов
5. **Sync Service** - синхронизация банов между чатами
6. **Notification Service** - отправка уведомлений
7. **Analytics Service** (опционально) - сбор статистики

---

## 1. API Gateway / Bot Service

### Назначение

Единая точка входа для всех запросов от Telegram. Маршрутизация команд к соответствующим микросервисам.

### Технический стек

- Python 3.10+
- aiogram 3.x или python-telegram-bot
- FastAPI для внутреннего API
- Redis для кэширования состояний
- aiohttp для асинхронных HTTP-запросов

### Функциональные требования

**1.1. Обработка команд**
- Приём всех webhook-запросов от Telegram
- Парсинг команд и аргументов
- Валидация прав доступа (проверка, что пользователь - администратор)
- Маршрутизация к нужным сервисам

**1.2. Поддерживаемые команды**

- `/start` - приветствие и инструкция
- `/subscribe <user>` → Subscription Service
- `/unsubscribe <user>` → Subscription Service
- `/list` → Subscription Service
- `/history <user>` → Ban Event Service
- `/settings` → User Service
- `/help` - справка
- `/stats` → Analytics Service

**1.3. Обработка событий**

- Обработка `chat_member` updates (события банов)
- Фильтрация событий (только ban/kick)
- Отправка событий в Ban Event Service

**1.4. API эндпоинты для внутренних сервисов**

```
POST /api/send_message - отправка сообщений в Telegram
POST /api/ban_user - бан пользователя
POST /api/unban_user - разбан пользователя
GET /api/chat_member - получение информации о пользователе в чате
GET /api/chat_admins - список администраторов чата
```

### Нефункциональные требования

- Rate limiting: max 30 запросов/мин на пользователя
- Timeout для запросов к сервисам: 5 секунд
- Graceful shutdown с завершением обработки текущих запросов
- Retry mechanism для failed запросов (3 попытки с exponential backoff)

### Структура данных

**Redis cache:**

```python
user_state:{user_id} = {
    "last_command": str,
    "context": dict,
    "timestamp": datetime
}

rate_limit:{user_id} = {
    "count": int,
    "reset_at": datetime
}
```

### Environment переменные

```
TELEGRAM_BOT_TOKEN=<token>
TELEGRAM_WEBHOOK_URL=<url>
REDIS_URL=<url>
SUBSCRIPTION_SERVICE_URL=<url>
BAN_EVENT_SERVICE_URL=<url>
USER_SERVICE_URL=<url>
NOTIFICATION_SERVICE_URL=<url>
MESSAGE_QUEUE_URL=<url>
```

---

## 2. Subscription Service

### Назначение

Управление подписками администраторов на отслеживаемых пользователей.

### Технический стек

- Python 3.10+ / Go
- FastAPI / Gin
- PostgreSQL
- SQLAlchemy / GORM
- Redis для кэширования

### Функциональные требования

**2.1. CRUD операции подписок**

- Создание подписки (админ → отслеживаемый пользователь)
- Удаление подписки
- Получение списка подписок админа
- Получение списка подписчиков на пользователя
- Проверка существования подписки

**2.2. API эндпоинты**

```
POST   /api/v1/subscriptions - создать подписку
DELETE /api/v1/subscriptions/{id} - удалить подписку
GET    /api/v1/subscriptions/admin/{admin_id} - подписки админа
GET    /api/v1/subscriptions/user/{user_id} - кто подписан на пользователя
GET    /api/v1/subscriptions/check - проверить существование
GET    /api/v1/subscriptions/stats - статистика подписок
```

**2.3. Бизнес-логика**

- Валидация: админ не может подписаться на самого себя
- Предотвращение дублирования подписок
- Проверка лимита подписок (макс 100 на админа)
- Автоматическая очистка подписок при удалении чата/админа

**2.4. События для Message Queue**

```
subscription.created - новая подписка создана
subscription.deleted - подписка удалена
subscription.limit_reached - достигнут лимит
```

### Структура базы данных

```sql
CREATE TABLE subscriptions (
    id BIGSERIAL PRIMARY KEY,
    admin_user_id BIGINT NOT NULL,
    admin_chat_id BIGINT NOT NULL,
    tracked_user_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    settings JSONB DEFAULT '{}',
    UNIQUE(admin_user_id, admin_chat_id, tracked_user_id)
);

CREATE INDEX idx_subscriptions_admin ON subscriptions(admin_user_id, admin_chat_id);
CREATE INDEX idx_subscriptions_tracked ON subscriptions(tracked_user_id) WHERE is_active = true;
CREATE INDEX idx_subscriptions_created ON subscriptions(created_at);
```

### Redis кэш

```python
subscription:admin:{admin_id}:{chat_id} = [tracked_user_ids]  # TTL: 1 hour
subscription:user:{user_id} = [subscriber_objects]  # TTL: 30 min
subscription:count:{admin_id} = count  # TTL: 1 hour
```

### Нефункциональные требования

- Время ответа: < 100ms для GET запросов
- Поддержка 1000 req/sec
- Транзакционность операций
- Автоматический failover при падении primary DB

---

## 3. User Service

### Назначение

Управление данными пользователей, администраторов и их настройками.

### Технический стек

- Python 3.10+ / Go
- FastAPI / Gin
- PostgreSQL
- Redis для кэширования профилей

### Функциональные требования

**3.1. Управление пользователями**

- Регистрация нового пользователя/админа
- Обновление профиля пользователя
- Получение информации о пользователе
- Деактивация пользователя

**3.2. Управление настройками**

- Персональные настройки админа
- Настройки чата (правила синхронизации банов)
- Языковые предпочтения
- Уведомления (вкл/выкл)

**3.3. API эндпоинты**

```
POST   /api/v1/users - создать пользователя
GET    /api/v1/users/{user_id} - получить пользователя
PUT    /api/v1/users/{user_id} - обновить пользователя
DELETE /api/v1/users/{user_id} - деактивировать

GET    /api/v1/users/{user_id}/settings - получить настройки
PUT    /api/v1/users/{user_id}/settings - обновить настройки

POST   /api/v1/chats - зарегистрировать чат
GET    /api/v1/chats/{chat_id}/settings - настройки чата
PUT    /api/v1/chats/{chat_id}/settings - обновить настройки чата

GET    /api/v1/admins/verify - проверить права админа
```

**3.4. Бизнес-логика**

- Автоматическое обновление username при изменении в Telegram
- Отслеживание активности пользователя (last_seen)
- Права доступа: owner, admin, moderator
- Валидация настроек синхронизации

### Структура базы данных

```sql
CREATE TABLE users (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(255),
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    language_code VARCHAR(10) DEFAULT 'en',
    is_bot BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP
);

CREATE TABLE admins (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(user_id),
    chat_id BIGINT NOT NULL,
    role VARCHAR(50) DEFAULT 'admin', -- owner, admin, moderator
    can_ban BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, chat_id)
);

CREATE TABLE user_settings (
    user_id BIGINT PRIMARY KEY REFERENCES users(user_id),
    notifications_enabled BOOLEAN DEFAULT TRUE,
    language VARCHAR(10) DEFAULT 'ru',
    timezone VARCHAR(50) DEFAULT 'UTC',
    settings JSONB DEFAULT '{}'
);

CREATE TABLE chat_settings (
    chat_id BIGINT PRIMARY KEY,
    chat_title VARCHAR(255),
    sync_ban_type VARCHAR(50) DEFAULT 'same', -- same, permanent, temporary
    sync_delay_seconds INT DEFAULT 0,
    auto_sync_enabled BOOLEAN DEFAULT TRUE,
    require_confirmation BOOLEAN DEFAULT FALSE,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_admins_chat ON admins(chat_id);
```

### Нефункциональные требования

- Кэширование пользовательских данных (TTL: 5 min)
- Batch операции для обновления пользователей
- Поддержка миграций схемы БД

---

## 4. Ban Event Service

### Назначение

Отслеживание, регистрация и хранение всех событий банов пользователей.

### Технический стек

- Python 3.10+ / Go
- FastAPI / Gin
- PostgreSQL (основная БД)
- TimescaleDB (для time-series данных) или отдельная партиционированная таблица
- Redis для дедупликации событий

### Функциональные требования

**4.1. Регистрация событий**
- Приём события бана от API Gateway
- Валидация события
- Дедупликация (избежать двойной обработки)
- Сохранение в БД
- Публикация события в Message Queue

**4.2. API эндпоинты**

```
POST   /api/v1/events/ban - зарегистрировать бан
GET    /api/v1/events/ban/{event_id} - получить событие
GET    /api/v1/events/user/{user_id} - история банов пользователя
GET    /api/v1/events/chat/{chat_id} - история банов в чате
GET    /api/v1/events/search - поиск по фильтрам
POST   /api/v1/events/bulk - массовая загрузка событий
```

**4.3. Типы событий**

- `ban` - перманентный бан
- `kick` - кик из чата
- `restrict` - ограничение прав
- `unban` - разбан

**4.4. Фильтрация и поиск**

- По пользователю
- По чату
- По периоду времени
- По типу бана
- По причине

**4.5. События для Message Queue**

```
ban.detected - обнаружен новый бан отслеживаемого пользователя
ban.registered - событие сохранено в БД
```

### Структура базы данных

```sql
CREATE TABLE ban_events (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(255) UNIQUE NOT NULL, -- UUID для дедупликации
    user_id BIGINT NOT NULL,
    chat_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- ban, kick, restrict, unban
    ban_duration BIGINT, -- NULL для permanent, секунды для temporary
    reason TEXT,
    initiator_user_id BIGINT,
    event_timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_ban_events_user ON ban_events(user_id, event_timestamp DESC);
CREATE INDEX idx_ban_events_chat ON ban_events(chat_id, event_timestamp DESC);
CREATE INDEX idx_ban_events_timestamp ON ban_events(event_timestamp DESC);
CREATE INDEX idx_ban_events_type ON ban_events(event_type);

-- Партиционирование по времени (опционально)
-- CREATE TABLE ban_events_2024_01 PARTITION OF ban_events
-- FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Redis для дедупликации

```python
event_processed:{event_id} = "1"  # TTL: 1 hour
```

### Нефункциональные требования

- Обработка событий < 500ms
- Поддержка высокой нагрузки (до 10000 событий/сек)
- Retention policy: хранение событий 1 год, потом архивация
- Репликация БД для отказоустойчивости

---

## 5. Sync Service

### Назначение

Синхронизация банов между чатами. Получает события о банах и применяет их во всех чатах подписчиков.

### Технический стек

- Python 3.10+ / Go
- Celery / Go workers
- RabbitMQ / Kafka для очередей задач
- PostgreSQL для логов синхронизации
- Redis для координации

### Функциональные требования

**5.1. Обработка событий банов**

- Подписка на события `ban.detected` из Message Queue
- Получение списка подписчиков на забаненного пользователя
- Применение бана в каждом чате подписчика
- Логирование результатов

**5.2. Логика синхронизации**

- Проверка настроек чата (тип бана для применения)
- Применение задержки, если настроена
- Retry mechanism при неудаче
- Пропуск чатов, где пользователь уже забанен

**5.3. API эндпоинты**

```
POST   /api/v1/sync/trigger - ручной триггер синхронизации
GET    /api/v1/sync/status/{sync_id} - статус синхронизации
GET    /api/v1/sync/logs - логи синхронизаций
POST   /api/v1/sync/retry/{sync_id} - повторить failed синхронизацию
```

**5.4. Обработка ошибок**

- Нет прав у бота → логирование, уведомление админа
- Пользователь не найден → пропуск
- Таймаут API → retry
- Чат не существует → деактивация подписки

**5.5. События для Message Queue**

```
sync.started - начало синхронизации
sync.completed - синхронизация завершена
sync.failed - синхронизация провалена
sync.partial - частичная синхронизация (не все чаты)
```

### Структура базы данных

```sql
CREATE TABLE sync_logs (
    id BIGSERIAL PRIMARY KEY,
    ban_event_id BIGINT NOT NULL,
    source_chat_id BIGINT NOT NULL,
    target_chat_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    status VARCHAR(50) NOT NULL, -- pending, success, failed, skipped
    error_message TEXT,
    retry_count INT DEFAULT 0,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_sync_logs_event ON sync_logs(ban_event_id);
CREATE INDEX idx_sync_logs_status ON sync_logs(status, created_at);
CREATE INDEX idx_sync_logs_target ON sync_logs(target_chat_id, created_at);
```

### Архитектура обработки

**Worker Pool:**

```python
# Celery tasks
@celery.app.task(bind=True, max_retries=3)
def sync_ban_to_chat(self, ban_event_id, target_chat_id, user_id, ban_config):
    """
    Синхронизирует бан в конкретный чат
    """
    pass

@celery.app.task
def process_ban_event(ban_event_id):
    """
    Координирует синхронизацию бана по всем подписчикам
    """
    # 1. Получить подписчиков
    # 2. Для каждого чата создать задачу sync_ban_to_chat
    # 3. Логировать результаты
    pass
```

### Нефункциональные требования

- Обработка события синхронизации < 10 секунд для 100 чатов
- Dead Letter Queue для failed задач
- Мониторинг очереди задач
- Circuit breaker для защиты от перегрузки Telegram API
- Graceful degradation при высокой нагрузке

---

## 6. Notification Service

### Назначение

Централизованная отправка уведомлений администраторам о событиях в системе.

### Технический стек

- Python 3.10+ / Go
- FastAPI / Gin
- RabbitMQ для очереди уведомлений
- Redis для rate limiting
- Template engine (Jinja2 / Go templates)

### Функциональные требования

**6.1. Типы уведомлений**

- Новая подписка создана
- Пользователь забанен (исходное событие)
- Бан синхронизирован в ваш чат
- Ошибка синхронизации (нет прав бота)
- Достигнут лимит подписок
- Системные уведомления

**6.2. Каналы доставки**

- Telegram сообщения (основной)
- Email (опционально)
- Webhook (опционально)

**6.3. API эндпоинты**

```
POST   /api/v1/notifications/send - отправить уведомление
POST   /api/v1/notifications/batch - массовая отправка
GET    /api/v1/notifications/templates - список шаблонов
PUT    /api/v1/notifications/templates/{id} - обновить шаблон
```

**6.4. Шаблоны сообщений**

```python
TEMPLATES = {
    "ban_detected": {
        "ru": "🚫 Пользователь {username} (ID: {user_id}) был забанен в чате {chat_name}\n"
              "Причина: {reason}\nВремя: {timestamp}",
        "en": "🚫 User {username} (ID: {user_id}) was banned in {chat_name}\n"
              "Reason: {reason}\nTime: {timestamp}"
    },
    "sync_success": {
        "ru": "✅ Бан успешно синхронизирован в ваш чат\n"
              "Пользователь: {username}\nЧат: {chat_name}",
        "en": "✅ Ban successfully synced to your chat\n"
              "User: {username}\nChat: {chat_name}"
    },
    "sync_failed": {
        "ru": "❌ Ошибка синхронизации бана\n"
              "Пользователь: {username}\nЧат: {chat_name}\n"
              "Причина: {error}",
        "en": "❌ Failed to sync ban\n"
              "User: {username}\nChat: {chat_name}\n"
              "Error: {error}"
    }
}
```

**6.5. Настройки уведомлений**

- Фильтрация по типу события
- Группировка уведомлений (digest mode)
- Приоритизация (срочные/обычные)
- Quiet hours (не беспокоить ночью)

**6.6. События из Message Queue**

Подписка на:

- `subscription.created`
- `ban.detected`
- `sync.completed`
- `sync.failed`
- и др.

### Структура базы данных

```sql
CREATE TABLE notification_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    notification_type VARCHAR(100) NOT NULL,
    channel VARCHAR(50) NOT NULL, -- telegram, email, webhook
    status VARCHAR(50) NOT NULL, -- sent, failed, pending
    template_id VARCHAR(100),
    payload JSONB,
    error_message TEXT,
    sent_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE notification_preferences (
    user_id BIGINT PRIMARY KEY,
    enabled_types JSONB DEFAULT '[]', -- список типов уведомлений
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    digest_mode BOOLEAN DEFAULT FALSE,
    digest_interval_hours INT DEFAULT 24
);

CREATE INDEX idx_notification_logs_user ON notification_logs(user_id, created_at DESC);
CREATE INDEX idx_notification_logs_status ON notification_logs(status);
```

### Нефункциональные требования

- Rate limiting: max 20 уведомлений/мин на пользователя
- Retry для failed уведомлений (3 попытки)
- Batch отправка для digest mode
- Логирование всех отправленных уведомлений

---

## 7. Analytics Service (опционально)

### Назначение

Сбор, агрегация и предоставление статистики по использованию системы.

### Технический стек

- Python 3.10+ / Go
- FastAPI / Gin
- PostgreSQL / ClickHouse (для аналитики)
- Redis для кэширования метрик

### Функциональные требования

**7.1. Собираемые метрики**

- Количество подписок (по датам)
- Количество банов (по датам, чатам, пользователям)
- Эффективность синхронизации (success rate)
- Топ-10 самых часто баненных пользователей
- Топ-10 самых активных чатов
- Среднее время синхронизации

**7.2. API эндпоинты**

```
GET /api/v1/analytics/overview - общая статистика
GET /api/v1/analytics/subscriptions - статистика подписок
GET /api/v1/analytics/bans - статистика банов
GET /api/v1/analytics/sync - статистика синхронизаций
GET /api/v1/analytics/top/users - топ пользователей
GET /api/v1/analytics/top/chats - топ чатов
GET /api/v1/analytics/timeline - данные для графиков
```

**7.3. Периоды агрегации**

- День, неделя, месяц, год
- Custom range

### Структура данных

```sql
CREATE TABLE analytics_daily (
    date DATE PRIMARY KEY,
    total_subscriptions INT DEFAULT 0,
    new_subscriptions INT DEFAULT 0,
    deleted_subscriptions INT DEFAULT 0,
    total_bans INT DEFAULT 0,
    total_syncs INT DEFAULT 0,
    successful_syncs INT DEFAULT 0,
    failed_syncs INT DEFAULT 0,
    unique_banned_users INT DEFAULT 0,
    active_chats INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE analytics_user_stats (
    user_id BIGINT,
    date DATE,
    ban_count INT DEFAULT 0,
    sync_count INT DEFAULT 0,
    PRIMARY KEY (user_id, date)
);

CREATE TABLE analytics_chat_stats (
    chat_id BIGINT,
    date DATE,
    ban_count INT DEFAULT 0,
    sync_received_count INT DEFAULT 0,
    PRIMARY KEY (chat_id, date)
);
```

---

## Межсервисное взаимодействие

### Message Queue (RabbitMQ/Kafka)

**Топики/Exchanges:**

```yaml
exchanges:
  - name: subscriptions
    type: topic
    queues:
      - subscription.created
      - subscription.deleted
      - subscription.limit_reached
  
  - name: bans
    type: topic
    queues:
      - ban.detected
      - ban.registered
  
  - name: sync
    type: topic
    queues:
      - sync.started
      - sync.completed
      - sync.failed
      - sync.partial
  
  - name: notifications
    type: fanout
    queues:
      - notification.send
```

**Формат сообщений (JSON):**

```json
// ban.detected
{
  "event_id": "uuid",
  "event_type": "ban.detected",
  "timestamp": "2025-01-15T10:30:00Z",
  "payload": {
    "ban_event_id": 12345,
    "user_id": 987654321,
    "chat_id": 123456789,
    "ban_type": "permanent",
    "reason": "spam",
    "initiator_user_id": 111222333
  }
}

// subscription.created
{
  "event_id": "uuid",
  "event_type": "subscription.created",
  "timestamp": "2025-01-15T10:30:00Z",
  "payload": {
    "subscription_id": 567,
    "admin_user_id": 111222333,
    "admin_chat_id": 123456789,
    "tracked_user_id": 987654321
  }
}

// sync.completed
{
  "event_id": "uuid",
  "event_type": "sync.completed",
  "timestamp": "2025-01-15T10:30:05Z",
  "payload": {
    "ban_event_id": 12345,
    "total_chats": 25,
    "successful": 23,
    "failed": 2,
    "sync_logs_ids": [1001, 1002, ...]
  }
}
```

### HTTP API взаимодействие

**Service Discovery:**

- Использование Consul / Eureka для service discovery
- Или статические URL через environment variables

**Authentication между сервисами:**

- JWT токены с коротким TTL
- API keys для внутренних сервисов
- Mutual TLS (опционально)

**Retry и Circuit Breaker:**

```python
# Пример с использованием tenacity и circuitbreaker
from tenacity import retry, stop_after_attempt, wait_exponential
from circuitbreaker import circuit

@circuit(failure_threshold=5, recovery_timeout=60)
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
async def call_subscription_service(endpoint, data):
    async with aiohttp.ClientSession() as session:
        async with session.post(f"{SUBSCRIPTION_SERVICE_URL}{endpoint}", json=data) as resp:
            return await resp.json()
```

---

## Инфраструктура и Deploy

### Docker Compose (для разработки)

```yaml
version: '3.8'

services:
  # Databases
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: ban_sync
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  rabbitmq:
    image: rabbitmq:3-management
    ports:
      - "5672:5672"
      - "15672:15672"

  # Services
  api_gateway:
    build: ./api_gateway
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres
      - redis
      - rabbitmq

  subscription_service:
    build: ./subscription_service
    ports:
      - "8001:8001"
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis

  user_service:
    build: ./user_service
    ports:
      - "8002:8002"
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis

  ban_event_service:
    build: ./ban_event_service
    ports:
      - "8003:8003"
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres
      - redis
      - rabbitmq

  sync_service:
    build: ./sync_service
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres
      - redis
      - rabbitmq

  notification_service:
    build: ./notification_service
    environment:
      - DATABASE_URL=postgresql://user:password@postgres/ban_sync
      - REDIS_URL=redis://redis:6379
      - RABBITMQ_URL=amqp://rabbitmq:5672
    depends_on:
      - postgres
      - redis
      - rabbitmq

volumes:
  postgres_data:
```

### Kubernetes (для production)

**Основные компоненты:**

- Deployments для каждого сервиса (с 2-3 репликами)
- Services для внутренней маршрутизации
- Ingress для внешнего доступа (API Gateway)
- ConfigMaps для конфигурации
- Secrets для чувствительных данных
- HorizontalPodAutoscaler для автомасштабирования
- PersistentVolumeClaims для PostgreSQL

---

## Мониторинг и Observability

### Метрики (Prometheus)

```
- http_requests_total{service, endpoint, status}
- http_request_duration_seconds{service, endpoint}
- message_queue_messages_total{queue, status}
- database_connections{service, state}
- sync_operations_total{status}
- ban_events_processed_total
```

### Логирование (ELK Stack)

- Структурированные JSON логи
- Correlation ID для трейсинга запросов
- Log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL

### Tracing (Jaeger/Zipkin)

- Распределённый трейсинг запросов через все сервисы
- Визуализация времени выполнения каждого шага

### Healthchecks

Каждый сервис предоставляет:
```
GET /health - общий статус
GET /health/live - liveness probe
GET /health/ready - readiness probe
```

---

## Безопасность

1. **Authentication & Authorization**
   - JWT для межсервисного взаимодействия
   - Проверка прав администратора перед выполнением операций
   - Rate limiting на уровне API Gateway

2. **Data Protection**
   - Шифрование чувствительных данных в БД
   - HTTPS для всех внешних соединений
   - Secrets management (Vault/AWS Secrets Manager)

3. **Network Security**
   - Service mesh (Istio) для mTLS между сервисами
   - Network policies в Kubernetes
   - Firewall rules

---

## Миграция данных между сервисами

При необходимости синхронизации данных между БД разных сервисов:

- CDC (Change Data Capture) через Debezium
- Event Sourcing pattern
- Saga pattern для распределённых транзакций

---

## План разработки (поэтапный)

**Фаза 1: Основа (2-3 недели)**

1. Настройка инфраструктуры (Docker, БД, Message Queue)
2. API Gateway + базовые команды
3. User Service
4. Subscription Service

**Фаза 2: Ядро функциональности (3-4 недели)**
5. Ban Event Service
6. Sync Service
7. Интеграция между сервисами

**Фаза 3: Дополнительные функции (2 недели)**
8. Notification Service
9. Analytics Service
10. Улучшение обработки ошибок

**Фаза 4: Production-ready (1-2 недели)**
11. Мониторинг и логирование
12. Тесты (unit, integration, e2e)
13. Documentation
14. Deploy в production

---
