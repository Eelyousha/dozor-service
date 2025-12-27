# UML диаграммы архитектуры сервиса

## 1. High-Level Architecture (Component Diagram)

```plantuml
@startuml
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Component.puml

LAYOUT_WITH_LEGEND()

title High-Level System Architecture

Person(admin, "Administrator", "Community moderator")
Person(user, "User", "Platform user")

System_Boundary(external, "External Systems") {
    System_Ext(telegram, "Telegram API", "Bot API")
    System_Ext(vk, "VK API", "Callback API")
    System_Ext(discord, "Discord API", "Gateway/REST")
}

System_Boundary(adapters, "Platform Adapters Layer") {
    Component(tg_adapter, "Telegram Adapter", "Go", "Handles Telegram events")
    Component(vk_adapter, "VK Adapter", "Go", "Handles VK events (stub)")
    Component(dc_adapter, "Discord Adapter", "Go", "Handles Discord events (stub)")
}

System_Boundary(gateway, "API Gateway") {
    Component(api_gw, "API Gateway", "Go/Gin", "Routes requests, validates tokens")
    Component(webhook_handler, "Webhook Handler", "Go", "Processes platform webhooks")
}

System_Boundary(core, "Core Services") {
    Component(sub_service, "Subscription Service", "Go", "Manages subscriptions")
    Component(user_service, "User Service", "Go", "Manages users")
    Component(ban_service, "Ban Event Service", "Go", "Tracks ban events")
    Component(sync_service, "Sync Service", "Go", "Syncs bans across platforms")
    Component(notif_service, "Notification Service", "Go", "Sends notifications")
}

System_Boundary(infra, "Infrastructure") {
    ContainerDb(postgres, "PostgreSQL", "Database", "Stores subscriptions, bans, users")
    ContainerDb(redis, "Redis", "Cache", "Caches user data, deduplication")
    Container(rabbitmq, "RabbitMQ", "Message Queue", "Event-driven communication")
}

Rel(admin, api_gw, "Uses", "HTTPS/REST")
Rel(user, telegram, "Banned in", "")

Rel(telegram, tg_adapter, "Sends events", "Webhook")
Rel(vk, vk_adapter, "Sends events", "Callback")
Rel(discord, dc_adapter, "Sends events", "Gateway")

Rel(tg_adapter, webhook_handler, "Normalized events", "")
Rel(vk_adapter, webhook_handler, "Normalized events", "")
Rel(dc_adapter, webhook_handler, "Normalized events", "")

Rel(webhook_handler, rabbitmq, "Publishes", "ban.detected")
Rel(api_gw, sub_service, "API calls", "HTTP")
Rel(api_gw, user_service, "API calls", "HTTP")

Rel(rabbitmq, ban_service, "Consumes", "ban.detected")
Rel(rabbitmq, sync_service, "Consumes", "ban.detected")
Rel(rabbitmq, notif_service, "Consumes", "sync.completed")

Rel(sub_service, postgres, "Reads/Writes", "SQL")
Rel(ban_service, postgres, "Reads/Writes", "SQL")
Rel(user_service, postgres, "Reads/Writes", "SQL")
Rel(sync_service, postgres, "Reads/Writes", "SQL")

Rel(sub_service, redis, "Caches", "")
Rel(user_service, redis, "Caches", "")

Rel(sync_service, tg_adapter, "Bans user", "")
Rel(sync_service, vk_adapter, "Bans user", "")
Rel(sync_service, dc_adapter, "Bans user", "")

Rel(notif_service, tg_adapter, "Sends message", "")

@enduml
```

---

## 2. Domain Model (Class Diagram)

```plantuml
@startuml
title Domain Model - Core Entities

package "Domain Models" {
    enum PlatformType {
        TELEGRAM
        VK
        DISCORD
        WHATSAPP
    }
    
    enum BanType {
        PERMANENT
        TEMPORARY
        KICK
        RESTRICT
    }
    
    class UnifiedUser {
        +Platform: PlatformType
        +PlatformUserID: string
        +Username: *string
        +DisplayName: *string
        +AvatarURL: *string
        +Email: *string
        +Phone: *string
        +RawData: map[string]interface{}
    }
    
    class UnifiedChat {
        +Platform: PlatformType
        +PlatformChatID: string
        +ChatType: string
        +Title: *string
        +MemberCount: *int
        +RawData: map[string]interface{}
    }
    
    class UnifiedBanEvent {
        +EventID: string
        +Platform: PlatformType
        +User: UnifiedUser
        +Chat: UnifiedChat
        +BanType: BanType
        +BanDuration: *int64
        +Reason: *string
        +Initiator: *UnifiedUser
        +Timestamp: time.Time
        +RawEvent: map[string]interface{}
    }
    
    class Subscription {
        +ID: int64
        +AdminUserID: string
        +AdminPlatform: PlatformType
        +AdminPlatformChatID: string
        +TrackedUserID: string
        +TrackedPlatform: PlatformType
        +CreatedAt: time.Time
        +UpdatedAt: time.Time
        +IsActive: bool
    }
    
    class BanEventRecord {
        +ID: int64
        +EventID: string
        +Platform: PlatformType
        +PlatformUserID: string
        +PlatformChatID: string
        +BanType: BanType
        +BanDuration: *int64
        +Reason: *string
        +InitiatorPlatformID: *string
        +EventTimestamp: time.Time
        +CreatedAt: time.Time
        +Metadata: map[string]interface{}
    }
    
    class SyncLog {
        +ID: int64
        +BanEventID: int64
        +SourcePlatform: PlatformType
        +TargetPlatform: PlatformType
        +TargetChatID: string
        +Status: string
        +ErrorMessage: *string
        +RetryCount: int
        +StartedAt: *time.Time
        +CompletedAt: *time.Time
        +CreatedAt: time.Time
    }
    
    UnifiedBanEvent *-- UnifiedUser : user
    UnifiedBanEvent *-- UnifiedChat : chat
    UnifiedBanEvent *-- UnifiedUser : initiator
    
    Subscription -- PlatformType
    BanEventRecord -- PlatformType
    BanEventRecord -- BanType
    SyncLog -- BanEventRecord
}

@enduml
```

---

## 3. Repository Pattern (Class Diagram)

```plantuml
@startuml
title Repository Pattern Architecture

package "Domain Layer" <<Rectangle>> {
    interface SubscriptionRepository {
        +Create(ctx, sub): error
        +GetByID(ctx, id): *Subscription, error
        +Delete(ctx, id): error
        +GetByAdmin(ctx, adminID): []*Subscription, error
        +GetSubscribers(ctx, userID): []*Subscription, error
        +Exists(ctx, adminID, userID): bool, error
        +CountByAdmin(ctx, adminID): int64, error
    }
    
    interface BanEventRepository {
        +Create(ctx, event): error
        +GetByID(ctx, id): *BanEventRecord, error
        +GetByEventID(ctx, eventID): *BanEventRecord, error
        +GetUserHistory(ctx, platform, userID): []*BanEventRecord, error
        +GetChatHistory(ctx, platform, chatID): []*BanEventRecord, error
        +Search(ctx, filter): []*BanEventRecord, error
    }
    
    interface UserRepository {
        +Create(ctx, user): error
        +GetByID(ctx, platform, userID): *UnifiedUser, error
        +Update(ctx, user): error
        +Delete(ctx, platform, userID): error
        +List(ctx, filter): []*UnifiedUser, error
    }
    
    interface SyncLogRepository {
        +Create(ctx, log): error
        +Update(ctx, log): error
        +GetByID(ctx, id): *SyncLog, error
        +GetByBanEventID(ctx, eventID): []*SyncLog, error
        +GetFailedSyncs(ctx, maxRetry, limit): []*SyncLog, error
    }
    
    interface CacheRepository {
        +Set(ctx, key, value, ttl): error
        +Get(ctx, key, dest): error
        +Delete(ctx, key): error
        +Exists(ctx, key): bool, error
    }
}

package "Repository Implementation (PostgreSQL)" <<Database>> {
    class PostgresSubscriptionRepository {
        -db: *sql.DB
        +Create(ctx, sub): error
        +GetByID(ctx, id): *Subscription, error
        +Delete(ctx, id): error
        +GetByAdmin(ctx, adminID): []*Subscription, error
        +GetSubscribers(ctx, userID): []*Subscription, error
        +Exists(ctx, adminID, userID): bool, error
        +CountByAdmin(ctx, adminID): int64, error
    }
    
    class PostgresBanEventRepository {
        -db: *sql.DB
        +Create(ctx, event): error
        +GetByID(ctx, id): *BanEventRecord, error
        +GetByEventID(ctx, eventID): *BanEventRecord, error
        +GetUserHistory(ctx, platform, userID): []*BanEventRecord, error
        +GetChatHistory(ctx, platform, chatID): []*BanEventRecord, error
        +Search(ctx, filter): []*BanEventRecord, error
    }
    
    class PostgresUserRepository {
        -db: *sql.DB
        +Create(ctx, user): error
        +GetByID(ctx, platform, userID): *UnifiedUser, error
        +Update(ctx, user): error
        +Delete(ctx, platform, userID): error
        +List(ctx, filter): []*UnifiedUser, error
    }
    
    class PostgresSyncLogRepository {
        -db: *sql.DB
        +Create(ctx, log): error
        +Update(ctx, log): error
        +GetByID(ctx, id): *SyncLog, error
        +GetByBanEventID(ctx, eventID): []*SyncLog, error
        +GetFailedSyncs(ctx, maxRetry, limit): []*SyncLog, error
    }
}

package "Repository Implementation (Redis)" <<Database>> {
    class RedisCacheRepository {
        -client: *redis.Client
        +Set(ctx, key, value, ttl): error
        +Get(ctx, key, dest): error
        +Delete(ctx, key): error
        +Exists(ctx, key): bool, error
    }
}

SubscriptionRepository <|.. PostgresSubscriptionRepository
BanEventRepository <|.. PostgresBanEventRepository
UserRepository <|.. PostgresUserRepository
SyncLogRepository <|.. PostgresSyncLogRepository
CacheRepository <|.. RedisCacheRepository

@enduml
```

---

## 4. Service Layer (Class Diagram)

```plantuml
@startuml
title Service Layer Architecture

package "Service Interfaces" {
    interface SubscriptionService {
        +CreateSubscription(ctx, req): *Subscription, error
        +DeleteSubscription(ctx, id): error
        +GetAdminSubscriptions(ctx, adminID, platform): []*Subscription, error
        +GetUserSubscribers(ctx, userID, platform): []*Subscription, error
        +CheckSubscriptionLimit(ctx, adminID, platform): error
    }
    
    interface BanEventService {
        +RegisterBanEvent(ctx, event): *BanEventRecord, error
        +GetBanEvent(ctx, eventID): *BanEventRecord, error
        +GetUserBanHistory(ctx, platform, userID): []*BanEventRecord, error
        +SearchBanEvents(ctx, filter): []*BanEventRecord, error
    }
    
    interface SyncService {
        +SyncBan(ctx, banEventID): error
        +SyncToChat(ctx, req): error
        +RetryFailedSyncs(ctx): error
    }
    
    interface NotificationService {
        +NotifyBanDetected(ctx, event, subs): error
        +NotifySyncCompleted(ctx, eventID, logs): error
        +NotifySyncFailed(ctx, eventID, err): error
    }
}

package "Service Implementations" {
    class SubscriptionServiceImpl {
        -repo: SubscriptionRepository
        -userRepo: UserRepository
        -cache: CacheRepository
        +CreateSubscription(ctx, req): *Subscription, error
        +DeleteSubscription(ctx, id): error
        +GetAdminSubscriptions(ctx, adminID, platform): []*Subscription, error
        +GetUserSubscribers(ctx, userID, platform): []*Subscription, error
        +CheckSubscriptionLimit(ctx, adminID, platform): error
    }
    
    class BanEventServiceImpl {
        -repo: BanEventRepository
        -eventPublisher: EventPublisher
        -cache: CacheRepository
        +RegisterBanEvent(ctx, event): *BanEventRecord, error
        +GetBanEvent(ctx, eventID): *BanEventRecord, error
        +GetUserBanHistory(ctx, platform, userID): []*BanEventRecord, error
        +SearchBanEvents(ctx, filter): []*BanEventRecord, error
    }
    
    class SyncServiceImpl {
        -banEventRepo: BanEventRepository
        -subscriptionRepo: SubscriptionRepository
        -syncLogRepo: SyncLogRepository
        -platformFactory: *PlatformFactory
        +SyncBan(ctx, banEventID): error
        +SyncToChat(ctx, req): error
        +RetryFailedSyncs(ctx): error
    }
    
    class NotificationServiceImpl {
        -platformFactory: *PlatformFactory
        -templateEngine: TemplateEngine
        +NotifyBanDetected(ctx, event, subs): error
        +NotifySyncCompleted(ctx, eventID, logs): error
        +NotifySyncFailed(ctx, eventID, err): error
    }
}

SubscriptionService <|.. SubscriptionServiceImpl
BanEventService <|.. BanEventServiceImpl
SyncService <|.. SyncServiceImpl
NotificationService <|.. NotificationServiceImpl

SubscriptionServiceImpl --> SubscriptionRepository : uses
SubscriptionServiceImpl --> UserRepository : uses
SubscriptionServiceImpl --> CacheRepository : uses

BanEventServiceImpl --> BanEventRepository : uses
BanEventServiceImpl --> CacheRepository : uses

SyncServiceImpl --> BanEventRepository : uses
SyncServiceImpl --> SubscriptionRepository : uses
SyncServiceImpl --> SyncLogRepository : uses

@enduml
```

---

## 5. Platform Adapter Pattern (Class Diagram)

```plantuml
@startuml
title Platform Adapter Architecture

package "Domain Layer" {
    interface PlatformAdapter {
        +GetPlatformType(): PlatformType
        +GetName(): string
        +GetVersion(): string
        +Initialize(ctx, config): error
        +Shutdown(ctx): error
        +HealthCheck(ctx): error
        +HandleWebhook(ctx, payload): error
        +NormalizeBanEvent(ctx, rawEvent): *UnifiedBanEvent, error
        +BanUser(ctx, req): error
        +UnbanUser(ctx, chatID, userID): error
        +GetUserInfo(ctx, userID): *UnifiedUser, error
        +GetChatInfo(ctx, chatID): *UnifiedChat, error
        +GetChatAdmins(ctx, chatID): []*UnifiedUser, error
        +CheckUserPermissions(ctx, chatID, userID): *UserPermissions, error
        +SendMessage(ctx, req): error
    }
    
    class BanUserRequest {
        +ChatID: string
        +UserID: string
        +Duration: *int64
        +Reason: *string
    }
    
    class SendMessageRequest {
        +ChatID: string
        +Text: string
        +Options: map[string]interface{}
    }
    
    class UserPermissions {
        +CanBanUsers: bool
        +CanDeleteMessages: bool
        +IsAdmin: bool
        +IsOwner: bool
    }
}

package "Platform Implementations" {
    class TelegramAdapter {
        -bot: *tgbotapi.BotAPI
        -config: TelegramConfig
        -eventPublisher: EventPublisher
        +GetPlatformType(): PlatformType
        +Initialize(ctx, config): error
        +HandleWebhook(ctx, payload): error
        +NormalizeBanEvent(ctx, rawEvent): *UnifiedBanEvent, error
        +BanUser(ctx, req): error
        +UnbanUser(ctx, chatID, userID): error
        +SendMessage(ctx, req): error
        -handleChatMemberUpdate(ctx, event): error
        -convertToUnifiedBanEvent(event): *UnifiedBanEvent, error
    }
    
    class VKAdapter {
        -vk: *VkAPI
        -config: VKConfig
        -eventPublisher: EventPublisher
        +GetPlatformType(): PlatformType
        +Initialize(ctx, config): error
        +HandleWebhook(ctx, payload): error
        +NormalizeBanEvent(ctx, rawEvent): *UnifiedBanEvent, error
        +BanUser(ctx, req): error
        {note: Stub implementation}
    }
    
    class DiscordAdapter {
        -bot: *discordgo.Session
        -config: DiscordConfig
        -eventPublisher: EventPublisher
        +GetPlatformType(): PlatformType
        +Initialize(ctx, config): error
        +HandleWebhook(ctx, payload): error
        +NormalizeBanEvent(ctx, rawEvent): *UnifiedBanEvent, error
        +BanUser(ctx, req): error
        {note: Stub implementation}
    }
    
    class PlatformFactory {
        -eventPublisher: EventPublisher
        +CreateAdapter(platformType): PlatformAdapter, error
        +GetAvailablePlatforms(): []PlatformType
        +InitializeAdapter(ctx, platformType, config): PlatformAdapter, error
    }
}

PlatformAdapter <|.. TelegramAdapter
PlatformAdapter <|.. VKAdapter
PlatformAdapter <|.. DiscordAdapter

PlatformFactory ..> TelegramAdapter : creates
PlatformFactory ..> VKAdapter : creates
PlatformFactory ..> DiscordAdapter : creates

PlatformAdapter ..> BanUserRequest : uses
PlatformAdapter ..> SendMessageRequest : uses
PlatformAdapter ..> UserPermissions : returns

@enduml
```

---

## 6. Sequence Diagram - Ban Event Flow

```plantuml
@startuml
title Ban Event Processing Flow

actor Admin as admin
participant "Telegram" as telegram
participant "Telegram\nAdapter" as tg_adapter
participant "Webhook\nHandler" as webhook
participant "RabbitMQ" as mq
participant "Ban Event\nService" as ban_svc
participant "Sync\nService" as sync_svc
participant "Subscription\nRepository" as sub_repo
participant "Platform\nFactory" as factory
participant "Target Platform\nAdapter" as target_adapter
participant "Notification\nService" as notif_svc

admin -> telegram: Ban @user123 in Chat A
activate telegram

telegram -> tg_adapter: ChatMemberUpdated event
activate tg_adapter

tg_adapter -> tg_adapter: convertToUnifiedBanEvent()
tg_adapter -> webhook: UnifiedBanEvent
activate webhook

webhook -> webhook: Validate & deduplicate
webhook -> mq: Publish "ban.detected"
activate mq
deactivate webhook

mq -> ban_svc: Consume "ban.detected"
activate ban_svc

ban_svc -> ban_svc: Save BanEventRecord to DB
ban_svc -> mq: Publish "ban.registered"
deactivate ban_svc

mq -> sync_svc: Consume "ban.registered"
activate sync_svc

sync_svc -> sub_repo: GetSubscribers(@user123)
activate sub_repo
sub_repo --> sync_svc: [Subscription1, Subscription2, ...]
deactivate sub_repo

loop For each subscription
    sync_svc -> factory: GetAdapter(platform)
    activate factory
    factory --> sync_svc: PlatformAdapter
    deactivate factory
    
    sync_svc -> target_adapter: BanUser(chatID, userID)
    activate target_adapter
    target_adapter -> target_adapter: Execute platform-specific ban
    target_adapter --> sync_svc: Success/Error
    deactivate target_adapter
    
    sync_svc -> sync_svc: Create SyncLog record
end

sync_svc -> mq: Publish "sync.completed"
deactivate sync_svc

mq -> notif_svc: Consume "sync.completed"
activate notif_svc

notif_svc -> notif_svc: Format notification message
notif_svc -> tg_adapter: SendMessage(admin, "Ban synced")
activate tg_adapter
tg_adapter -> telegram: Send notification
telegram -> admin: "User @user123 banned in 3 chats"
deactivate tg_adapter
deactivate notif_svc
deactivate telegram

@enduml
```

---

## 7. Sequence Diagram - Create Subscription Flow

```plantuml
@startuml
title Create Subscription Flow

actor Admin as admin
participant "API Gateway" as api_gw
participant "Subscription\nService" as sub_svc
participant "User\nRepository" as user_repo
participant "Subscription\nRepository" as sub_repo
participant "Cache\n(Redis)" as cache
participant "PostgreSQL" as db

admin -> api_gw: POST /api/v1/subscriptions\n{adminID, trackedUserID}
activate api_gw

api_gw -> api_gw: Validate JWT token
api_gw -> api_gw: Validate admin permissions

api_gw -> sub_svc: CreateSubscription(ctx, req)
activate sub_svc

sub_svc -> sub_svc: Validate business rules\n(can't subscribe to self)

sub_svc -> sub_repo: CountByAdmin(adminID)
activate sub_repo
sub_repo -> db: SELECT COUNT(*) WHERE admin_id=?
activate db
db --> sub_repo: count=45
deactivate db
sub_repo --> sub_svc: 45
deactivate sub_repo

sub_svc -> sub_svc: Check limit (45 < 100) ✓

sub_svc -> user_repo: GetByID(trackedUserID)
activate user_repo
user_repo -> cache: GET user:{platform}:{userID}
activate cache
cache --> user_repo: Cache miss
deactivate cache

user_repo -> db: SELECT * FROM users WHERE...
activate db
db --> user_repo: user data
deactivate db

user_repo -> cache: SET user:{platform}:{userID}
activate cache
deactivate cache
user_repo --> sub_svc: *UnifiedUser
deactivate user_repo

sub_svc -> sub_svc: User exists ✓

sub_svc -> sub_repo: Create(subscription)
activate sub_repo
sub_repo -> db: INSERT INTO subscriptions...
activate db
db --> sub_repo: id=123
deactivate db
sub_repo --> sub_svc: *Subscription{ID: 123}
deactivate sub_repo

sub_svc -> cache: DELETE subscription:admin:{adminID}
activate cache
note right: Invalidate cache
deactivate cache

sub_svc --> api_gw: *Subscription, nil
deactivate sub_svc

api_gw --> admin: 201 Created\n{"id": 123, "admin_id": "...", ...}
deactivate api_gw

@enduml
```

---

## 8. Package Dependency Diagram

```plantuml
@startuml
title Package Dependencies (Layered Architecture)

package "Presentation Layer" {
    [API Handlers]
    [Webhook Handlers]
}

package "Application Layer" {
    [Subscription Service]
    [Ban Event Service]
    [Sync Service]
    [Notification Service]
}

package "Domain Layer" {
    [Domain Models]
    [Repository Interfaces]
    [Service Interfaces]
    [Platform Adapter Interface]
}

package "Infrastructure Layer" {
    [PostgreSQL Repository]
    [Redis Repository]
    [RabbitMQ Publisher]
    [RabbitMQ Consumer]
}

package "Platform Layer" {
    [Telegram Adapter]
    [VK Adapter]
    [Discord Adapter]
    [Platform Factory]
}

package "External" {
    [PostgreSQL Database]
    [Redis Cache]
    [RabbitMQ]
    [Telegram API]
    [VK API]
    [Discord API]
}

[API Handlers] --> [Subscription Service]
[API Handlers] --> [Ban Event Service]
[Webhook Handlers] --> [Platform Factory]

[Subscription Service] --> [Repository Interfaces]
[Ban Event Service] --> [Repository Interfaces]
[Sync Service] --> [Repository Interfaces]
[Sync Service] --> [Platform Adapter Interface]
[Notification Service] --> [Platform Adapter Interface]

[Repository Interfaces] <|.. [PostgreSQL Repository]
[Repository Interfaces] <|.. [Redis Repository]

[Platform Adapter Interface] <|.. [Telegram Adapter]
[Platform Adapter Interface] <|.. [VK Adapter]
[Platform Adapter Interface] <|.. [Discord Adapter]

[PostgreSQL Repository] --> [PostgreSQL Database]
[Redis Repository] --> [Redis Cache]
[RabbitMQ Publisher] --> [RabbitMQ]
[RabbitMQ Consumer] --> [RabbitMQ]

[Telegram Adapter] --> [Telegram API]
[VK Adapter] --> [VK API]
[Discord Adapter] --> [Discord API]

note right of [Domain Layer]
  Domain Layer is pure business logic.
  Has NO dependencies on infrastructure.
  Defines interfaces that infrastructure implements.
end note

note right of [Infrastructure Layer]
  Infrastructure implements
  domain interfaces.
  Depends on external systems.
end note

@enduml
```

---

## 9. Deployment Diagram

```plantuml
@startuml
title Deployment Architecture (Docker Compose / Kubernetes)

node "Load Balancer" {
    [Nginx/Traefik]
}

node "Application Servers" {
    node "API Gateway Pod" {
        [API Gateway Service]
        [Webhook Handler]
    }
    
    node "Subscription Service Pod" {
        [Subscription Service]
    }
    
    node "Ban Event Service Pod" {
        [Ban Event Service]
    }
    
    node "Sync Service Pod" {
        [Sync Worker 1]
        [Sync Worker 2]
        [Sync Worker N]
    }
    
    node "Notification Service Pod" {
        [Notification Worker]
    }
}

node "Platform Adapters" {
    node "Telegram Adapter Pod" {
        [Telegram Bot]
    }
    
    node "VK Adapter Pod" {
        [VK Bot]
    }
    
    node "Discord Adapter Pod" {
        [Discord Bot]
    }
}

database "PostgreSQL Cluster" {
    [Primary DB]
    [Replica 1]
    [Replica 2]
}

database "Redis Cluster" {
    [Redis Master]
    [Redis Slave 1]
    [Redis Slave 2]
}

node "Message Queue" {
    [RabbitMQ Cluster]
}

cloud "External Services" {
    [Telegram API]
    [VK API]
    [Discord API]
}

[Nginx/Traefik] --> [API Gateway Service] : HTTPS
[Nginx/Traefik] --> [Webhook Handler] : HTTPS

[API Gateway Service] --> [Subscription Service] : HTTP
[API Gateway Service] --> [Ban Event Service] : HTTP

[Webhook Handler] --> [RabbitMQ Cluster] : AMQP

[Subscription Service] --> [Primary DB] : PostgreSQL
[Ban Event Service] --> [Primary DB] : PostgreSQL
[Sync Worker 1] --> [Primary DB] : PostgreSQL

[Subscription Service] --> [Redis Master] : Redis Protocol
[Ban Event Service] --> [Redis Master] : Redis Protocol

[Sync Worker 1] --> [RabbitMQ Cluster] : Consume
[Sync Worker 2] --> [RabbitMQ Cluster] : Consume
[Notification Worker] --> [RabbitMQ Cluster] : Consume

[Sync Worker 1] --> [Telegram Bot] : gRPC/HTTP
[Sync Worker 1] --> [VK Bot] : gRPC/HTTP
[Sync Worker 1] --> [Discord Bot] : gRPC/HTTP

[Telegram Bot] --> [Telegram API] : HTTPS
[VK Bot] --> [VK API] : HTTPS
[Discord Bot] --> [Discord API] : WebSocket/HTTPS

[Telegram API] --> [Telegram Bot] : Webhook
[VK API] --> [VK Bot] : Callback
[Discord API] --> [Discord Bot] : Gateway Events

@enduml
```

---

## 10. Database Schema (ER Diagram)

```plantuml
@startuml
title Database Schema (Entity-Relationship Diagram)

entity "subscriptions" {
    * id : BIGSERIAL <<PK>>
    --
    * admin_user_id : VARCHAR(255)
    * admin_platform : VARCHAR(50)
    * admin_platform_chat_id : VARCHAR(255)
    * tracked_user_id : VARCHAR(255)
    * tracked_platform : VARCHAR(50)
    * created_at : TIMESTAMP
    * updated_at : TIMESTAMP
    * is_active : BOOLEAN
    --
    UNIQUE(admin_user_id, admin_platform_chat_id, tracked_user_id)
    INDEX(admin_user_id, admin_platform)
    INDEX(tracked_user_id, tracked_platform)
}

entity "ban_events" {
    * id : BIGSERIAL <<PK>>
    --
    * event_id : VARCHAR(255) <<UNIQUE>>
    * platform : VARCHAR(50)
    * platform_user_id : VARCHAR(255)
    * platform_chat_id : VARCHAR(255)
    * ban_type : VARCHAR(50)
    ban_duration : BIGINT
    reason : TEXT
    initiator_platform_id : VARCHAR(255)
    * event_timestamp : TIMESTAMP
    * created_at : TIMESTAMP
    metadata : JSONB
    --
    INDEX(platform, platform_user_id, event_timestamp)
    INDEX(platform, platform_chat_id, event_timestamp)
    INDEX(event_timestamp DESC)
}

entity "sync_logs" {
    * id : BIGSERIAL <<PK>>
    --
    * ban_event_id : BIGINT <<FK>>
    * source_platform : VARCHAR(50)
    * target_platform : VARCHAR(50)
    * target_chat_id : VARCHAR(255)
    * status : VARCHAR(50)
    error_message : TEXT
    * retry_count : INT
    started_at : TIMESTAMP
    completed_at : TIMESTAMP
    * created_at : TIMESTAMP
    --
    INDEX(ban_event_id)
    INDEX(status, created_at)
    INDEX(target_platform, target_chat_id)
}

entity "users" {
    * platform : VARCHAR(50) <<PK>>
    * platform_user_id : VARCHAR(255) <<PK>>
    --
    username : VARCHAR(255)
    display_name : VARCHAR(255)
    avatar_url : TEXT
    email : VARCHAR(255)
    phone : VARCHAR(50)
    * is_active : BOOLEAN
    * created_at : TIMESTAMP
    * updated_at : TIMESTAMP
    last_seen : TIMESTAMP
    raw_data : JSONB
    --
    INDEX(username)
    INDEX(email)
    INDEX(phone)
}

entity "chat_settings" {
    * platform : VARCHAR(50) <<PK>>
    * platform_chat_id : VARCHAR(255) <<PK>>
    --
    chat_title : VARCHAR(255)
    sync_ban_type : VARCHAR(50)
    sync_delay_seconds : INT
    * auto_sync_enabled : BOOLEAN
    require_confirmation : BOOLEAN
    settings : JSONB
    * created_at : TIMESTAMP
    * updated_at : TIMESTAMP
}

subscriptions }o--|| users : admin_user
subscriptions }o--|| users : tracked_user
ban_events }o--|| users : banned_user
ban_events }o--|| users : initiator
sync_logs }o--|| ban_events : relates_to
sync_logs }o--|| chat_settings : target_chat

@enduml
```

---

## Как использовать эти диаграммы

### Для рендеринга PlantUML:

**Online:**
- http://www.plantuml.com/plantuml/uml/
- https://plantuml-editor.kkeisuke.com/

**VS Code:**
```bash
# Установите расширение
ext install jebbs.plantuml

# Или используйте CLI
brew install plantuml  # macOS
apt-get install plantuml  # Ubuntu

# Рендер


Нужны ли дополнительные диаграммы для каких-то специфических сценариев?