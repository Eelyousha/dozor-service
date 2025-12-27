# Реализация Interface First на Golang

## Структура проекта

```
ban-sync-system/
├── cmd/
│   ├── api-gateway/
│   │   └── main.go
│   ├── subscription-service/
│   │   └── main.go
│   ├── ban-event-service/
│   │   └── main.go
│   └── sync-service/
│       └── main.go
│
├── internal/
│   ├── domain/              # Доменные модели и интерфейсы
│   │   ├── models.go
│   │   ├── platform.go      # Интерфейс платформы
│   │   ├── repository.go    # Интерфейсы репозиториев
│   │   └── service.go       # Интерфейсы сервисов
│   │
│   ├── platform/            # Реализации платформ
│   │   ├── telegram/
│   │   │   ├── adapter.go
│   │   │   ├── client.go
│   │   │   └── models.go
│   │   ├── vk/              # Заглушка
│   │   │   └── adapter.go
│   │   ├── discord/         # Заглушка
│   │   │   └── adapter.go
│   │   └── factory.go
│   │
│   ├── repository/          # Реализации репозиториев
│   │   ├── postgres/
│   │   │   ├── user.go
│   │   │   ├── subscription.go
│   │   │   └── ban_event.go
│   │   └── redis/
│   │       └── cache.go
│   │
│   ├── service/             # Бизнес-логика
│   │   ├── user/
│   │   │   └── service.go
│   │   ├── subscription/
│   │   │   └── service.go
│   │   └── sync/
│   │       └── service.go
│   │
│   ├── api/                 # HTTP handlers
│   │   ├── rest/
│   │   │   ├── handler.go
│   │   │   ├── middleware.go
│   │   │   └── router.go
│   │   └── webhook/
│   │       └── telegram.go
│   │
│   └── infrastructure/      # Инфраструктурные компоненты
│       ├── database/
│       │   └── postgres.go
│       ├── cache/
│       │   └── redis.go
│       ├── messaging/
│       │   └── rabbitmq.go
│       └── logger/
│           └── logger.go
│
├── pkg/                     # Публичные библиотеки
│   ├── errors/
│   │   └── errors.go
│   ├── config/
│   │   └── config.go
│   └── httpclient/
│       └── client.go
│
├── migrations/              # SQL миграции
│   ├── 001_init_schema.up.sql
│   └── 001_init_schema.down.sql
│
├── deployments/
│   ├── docker-compose.yml
│   └── kubernetes/
│
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

---

## 1. Domain Layer - Определение интерфейсов

### internal/domain/models.go

```go
package domain

import (
    "time"
)

// PlatformType представляет тип платформы
type PlatformType string

const (
    PlatformTelegram  PlatformType = "telegram"
    PlatformVK        PlatformType = "vk"
    PlatformDiscord   PlatformType = "discord"
    PlatformWhatsApp  PlatformType = "whatsapp"
)

// UnifiedUser - унифицированное представление пользователя
type UnifiedUser struct {
    Platform         PlatformType       `json:"platform"`
    PlatformUserID   string             `json:"platform_user_id"`
    Username         *string            `json:"username,omitempty"`
    DisplayName      *string            `json:"display_name,omitempty"`
    AvatarURL        *string            `json:"avatar_url,omitempty"`
    Email            *string            `json:"email,omitempty"`
    Phone            *string            `json:"phone,omitempty"`
    RawData          map[string]interface{} `json:"raw_data,omitempty"`
}

// UnifiedChat - унифицированное представление чата
type UnifiedChat struct {
    Platform        PlatformType       `json:"platform"`
    PlatformChatID  string             `json:"platform_chat_id"`
    ChatType        string             `json:"chat_type"` // group, supergroup, channel
    Title           *string            `json:"title,omitempty"`
    MemberCount     *int               `json:"member_count,omitempty"`
    RawData         map[string]interface{} `json:"raw_data,omitempty"`
}

// BanType представляет тип бана
type BanType string

const (
    BanTypePermanent BanType = "permanent"
    BanTypeTemporary BanType = "temporary"
    BanTypeKick      BanType = "kick"
    BanTypeRestrict  BanType = "restrict"
)

// UnifiedBanEvent - унифицированное событие бана
type UnifiedBanEvent struct {
    EventID      string        `json:"event_id"`
    Platform     PlatformType  `json:"platform"`
    User         UnifiedUser   `json:"user"`
    Chat         UnifiedChat   `json:"chat"`
    BanType      BanType       `json:"ban_type"`
    BanDuration  *int64        `json:"ban_duration,omitempty"` // секунды
    Reason       *string       `json:"reason,omitempty"`
    Initiator    *UnifiedUser  `json:"initiator,omitempty"`
    Timestamp    time.Time     `json:"timestamp"`
    RawEvent     map[string]interface{} `json:"raw_event,omitempty"`
}

// Subscription - подписка администратора на пользователя
type Subscription struct {
    ID                    int64        `json:"id"`
    AdminUserID           string       `json:"admin_user_id"`
    AdminPlatform         PlatformType `json:"admin_platform"`
    AdminPlatformChatID   string       `json:"admin_platform_chat_id"`
    TrackedUserID         string       `json:"tracked_user_id"`
    TrackedPlatform       PlatformType `json:"tracked_platform"`
    CreatedAt             time.Time    `json:"created_at"`
    UpdatedAt             time.Time    `json:"updated_at"`
    IsActive              bool         `json:"is_active"`
}

// BanEventRecord - запись события бана в БД
type BanEventRecord struct {
    ID                   int64        `json:"id"`
    EventID              string       `json:"event_id"`
    Platform             PlatformType `json:"platform"`
    PlatformUserID       string       `json:"platform_user_id"`
    PlatformChatID       string       `json:"platform_chat_id"`
    BanType              BanType      `json:"ban_type"`
    BanDuration          *int64       `json:"ban_duration,omitempty"`
    Reason               *string      `json:"reason,omitempty"`
    InitiatorPlatformID  *string      `json:"initiator_platform_id,omitempty"`
    EventTimestamp       time.Time    `json:"event_timestamp"`
    CreatedAt            time.Time    `json:"created_at"`
    Metadata             map[string]interface{} `json:"metadata,omitempty"`
}

// SyncLog - лог синхронизации
type SyncLog struct {
    ID              int64        `json:"id"`
    BanEventID      int64        `json:"ban_event_id"`
    SourcePlatform  PlatformType `json:"source_platform"`
    TargetPlatform  PlatformType `json:"target_platform"`
    TargetChatID    string       `json:"target_chat_id"`
    Status          string       `json:"status"` // pending, success, failed
    ErrorMessage    *string      `json:"error_message,omitempty"`
    RetryCount      int          `json:"retry_count"`
    StartedAt       *time.Time   `json:"started_at,omitempty"`
    CompletedAt     *time.Time   `json:"completed_at,omitempty"`
    CreatedAt       time.Time    `json:"created_at"`
}
```

---

### internal/domain/platform.go - Главный интерфейс

```go
package domain

import (
    "context"
)

// PlatformAdapter - интерфейс адаптера платформы
// Это ключевой интерфейс, который должны реализовать все платформы
type PlatformAdapter interface {
    // Метаинформация
    GetPlatformType() PlatformType
    GetName() string
    GetVersion() string
    
    // Lifecycle
    Initialize(ctx context.Context, config map[string]interface{}) error
    Shutdown(ctx context.Context) error
    HealthCheck(ctx context.Context) error
    
    // Обработка событий
    HandleWebhook(ctx context.Context, payload []byte) error
    NormalizeBanEvent(ctx context.Context, rawEvent map[string]interface{}) (*UnifiedBanEvent, error)
    
    // Операции с пользователями
    BanUser(ctx context.Context, req BanUserRequest) error
    UnbanUser(ctx context.Context, chatID, userID string) error
    GetUserInfo(ctx context.Context, userID string) (*UnifiedUser, error)
    
    // Операции с чатами
    GetChatInfo(ctx context.Context, chatID string) (*UnifiedChat, error)
    GetChatAdmins(ctx context.Context, chatID string) ([]*UnifiedUser, error)
    CheckUserPermissions(ctx context.Context, chatID, userID string) (*UserPermissions, error)
    
    // Сообщения
    SendMessage(ctx context.Context, req SendMessageRequest) error
}

// BanUserRequest - запрос на бан пользователя
type BanUserRequest struct {
    ChatID      string
    UserID      string
    Duration    *int64  // секунды, nil = permanent
    Reason      *string
}

// SendMessageRequest - запрос на отправку сообщения
type SendMessageRequest struct {
    ChatID  string
    Text    string
    Options map[string]interface{} // platform-specific options
}

// UserPermissions - права пользователя в чате
type UserPermissions struct {
    CanBanUsers     bool
    CanDeleteMessages bool
    IsAdmin         bool
    IsOwner         bool
}

// WebhookHandler - интерфейс для обработки webhook
type WebhookHandler interface {
    HandleWebhook(ctx context.Context, platform PlatformType, payload []byte) error
}
```

---

### internal/domain/repository.go - Интерфейсы репозиториев

```go
package domain

import (
    "context"
)

// UserRepository - репозиторий пользователей
type UserRepository interface {
    Create(ctx context.Context, user *UnifiedUser) error
    GetByID(ctx context.Context, platform PlatformType, platformUserID string) (*UnifiedUser, error)
    Update(ctx context.Context, user *UnifiedUser) error
    Delete(ctx context.Context, platform PlatformType, platformUserID string) error
    List(ctx context.Context, filter UserFilter) ([]*UnifiedUser, error)
}

// UserFilter - фильтр для поиска пользователей
type UserFilter struct {
    Platform   *PlatformType
    Username   *string
    Limit      int
    Offset     int
}

// SubscriptionRepository - репозиторий подписок
type SubscriptionRepository interface {
    Create(ctx context.Context, sub *Subscription) error
    GetByID(ctx context.Context, id int64) (*Subscription, error)
    Delete(ctx context.Context, id int64) error
    
    // Получить подписки администратора
    GetByAdmin(ctx context.Context, adminUserID string, platform PlatformType) ([]*Subscription, error)
    
    // Получить подписчиков на пользователя
    GetSubscribers(ctx context.Context, trackedUserID string, platform PlatformType) ([]*Subscription, error)
    
    // Проверить существование подписки
    Exists(ctx context.Context, adminUserID, trackedUserID string, platform PlatformType) (bool, error)
    
    // Получить количество подписок админа
    CountByAdmin(ctx context.Context, adminUserID string, platform PlatformType) (int64, error)
}

// BanEventRepository - репозиторий событий банов
type BanEventRepository interface {
    Create(ctx context.Context, event *BanEventRecord) error
    GetByID(ctx context.Context, id int64) (*BanEventRecord, error)
    GetByEventID(ctx context.Context, eventID string) (*BanEventRecord, error)
    
    // История банов пользователя
    GetUserHistory(ctx context.Context, platform PlatformType, userID string, limit int) ([]*BanEventRecord, error)
    
    // История банов в чате
    GetChatHistory(ctx context.Context, platform PlatformType, chatID string, limit int) ([]*BanEventRecord, error)
    
    // Поиск событий
    Search(ctx context.Context, filter BanEventFilter) ([]*BanEventRecord, error)
}

// BanEventFilter - фильтр для поиска событий банов
type BanEventFilter struct {
    Platform    *PlatformType
    UserID      *string
    ChatID      *string
    BanType     *BanType
    FromDate    *time.Time
    ToDate      *time.Time
    Limit       int
    Offset      int
}

// SyncLogRepository - репозиторий логов синхронизации
type SyncLogRepository interface {
    Create(ctx context.Context, log *SyncLog) error
    Update(ctx context.Context, log *SyncLog) error
    GetByID(ctx context.Context, id int64) (*SyncLog, error)
    GetByBanEventID(ctx context.Context, banEventID int64) ([]*SyncLog, error)
    
    // Получить failed синхронизации для retry
    GetFailedSyncs(ctx context.Context, maxRetryCount int, limit int) ([]*SyncLog, error)
}

// CacheRepository - репозиторий для кэширования
type CacheRepository interface {
    Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error
    Get(ctx context.Context, key string, dest interface{}) error
    Delete(ctx context.Context, key string) error
    Exists(ctx context.Context, key string) (bool, error)
}
```

---

### internal/domain/service.go - Интерфейсы сервисов

```go
package domain

import (
    "context"
)

// SubscriptionService - сервис управления подписками
type SubscriptionService interface {
    // Создать подписку
    CreateSubscription(ctx context.Context, req CreateSubscriptionRequest) (*Subscription, error)
    
    // Удалить подписку
    DeleteSubscription(ctx context.Context, id int64) error
    
    // Получить подписки админа
    GetAdminSubscriptions(ctx context.Context, adminUserID string, platform PlatformType) ([]*Subscription, error)
    
    // Получить подписчиков пользователя
    GetUserSubscribers(ctx context.Context, userID string, platform PlatformType) ([]*Subscription, error)
    
    // Проверить лимит подписок
    CheckSubscriptionLimit(ctx context.Context, adminUserID string, platform PlatformType) error
}

// CreateSubscriptionRequest - запрос на создание подписки
type CreateSubscriptionRequest struct {
    AdminUserID         string
    AdminPlatform       PlatformType
    AdminPlatformChatID string
    TrackedUserID       string
    TrackedPlatform     PlatformType
}

// BanEventService - сервис управления событиями банов
type BanEventService interface {
    // Зарегистрировать событие бана
    RegisterBanEvent(ctx context.Context, event *UnifiedBanEvent) (*BanEventRecord, error)
    
    // Получить событие
    GetBanEvent(ctx context.Context, eventID string) (*BanEventRecord, error)
    
    // Получить историю банов пользователя
    GetUserBanHistory(ctx context.Context, platform PlatformType, userID string) ([]*BanEventRecord, error)
    
    // Поиск событий
    SearchBanEvents(ctx context.Context, filter BanEventFilter) ([]*BanEventRecord, error)
}

// SyncService - сервис синхронизации банов
type SyncService interface {
    // Синхронизировать бан
    SyncBan(ctx context.Context, banEventID int64) error
    
    // Синхронизировать в конкретный чат
    SyncToChat(ctx context.Context, req SyncToChatRequest) error
    
    // Повторить failed синхронизации
    RetryFailedSyncs(ctx context.Context) error
}

// SyncToChatRequest - запрос на синхронизацию в чат
type SyncToChatRequest struct {
    BanEventID     int64
    TargetPlatform PlatformType
    TargetChatID   string
    UserID         string
}

// NotificationService - сервис уведомлений
type NotificationService interface {
    // Уведомить о бане
    NotifyBanDetected(ctx context.Context, event *UnifiedBanEvent, subscriptions []*Subscription) error
    
    // Уведомить о синхронизации
    NotifySyncCompleted(ctx context.Context, banEventID int64, logs []*SyncLog) error
    
    // Уведомить об ошибке
    NotifySyncFailed(ctx context.Context, banEventID int64, err error) error
}

// EventPublisher - интерфейс для публикации событий в message queue
type EventPublisher interface {
    PublishBanDetected(ctx context.Context, event *UnifiedBanEvent) error
    PublishSyncCompleted(ctx context.Context, log *SyncLog) error
    PublishSyncFailed(ctx context.Context, log *SyncLog) error
}

// EventSubscriber - интерфейс для подписки на события
type EventSubscriber interface {
    SubscribeBanDetected(ctx context.Context, handler func(*UnifiedBanEvent) error) error
    SubscribeSyncCompleted(ctx context.Context, handler func(*SyncLog) error) error
    SubscribeSyncFailed(ctx context.Context, handler func(*SyncLog) error) error
}
```

---

## 2. Platform Adapters - Реализация для Telegram

### internal/platform/telegram/adapter.go

```go
package telegram

import (
    "context"
    "encoding/json"
    "fmt"
    "time"
    
    tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
    "ban-sync-system/internal/domain"
)

// Adapter реализует domain.PlatformAdapter для Telegram
type Adapter struct {
    bot           *tgbotapi.BotAPI
    config        Config
    webhookURL    string
    eventPublisher domain.EventPublisher
}

// Config - конфигурация Telegram адаптера
type Config struct {
    BotToken   string
    WebhookURL string
    Debug      bool
}

// NewAdapter создаёт новый Telegram адаптер
func NewAdapter(eventPublisher domain.EventPublisher) *Adapter {
    return &Adapter{
        eventPublisher: eventPublisher,
    }
}

// GetPlatformType возвращает тип платформы
func (a *Adapter) GetPlatformType() domain.PlatformType {
    return domain.PlatformTelegram
}

// GetName возвращает имя адаптера
func (a *Adapter) GetName() string {
    return "Telegram Adapter"
}

// GetVersion возвращает версию адаптера
func (a *Adapter) GetVersion() string {
    return "1.0.0"
}

// Initialize инициализирует адаптер
func (a *Adapter) Initialize(ctx context.Context, config map[string]interface{}) error {
    // Парсим конфигурацию
    botToken, ok := config["bot_token"].(string)
    if !ok || botToken == "" {
        return fmt.Errorf("bot_token is required")
    }
    
    webhookURL, _ := config["webhook_url"].(string)
    debug, _ := config["debug"].(bool)
    
    a.config = Config{
        BotToken:   botToken,
        WebhookURL: webhookURL,
        Debug:      debug,
    }
    
    // Создаём бота
    bot, err := tgbotapi.NewBotAPI(botToken)
    if err != nil {
        return fmt.Errorf("failed to create bot: %w", err)
    }
    
    bot.Debug = debug
    a.bot = bot
    
    // Устанавливаем webhook если указан
    if webhookURL != "" {
        webhook, err := tgbotapi.NewWebhook(webhookURL)
        if err != nil {
            return fmt.Errorf("failed to create webhook: %w", err)
        }
        
        _, err = bot.Request(webhook)
        if err != nil {
            return fmt.Errorf("failed to set webhook: %w", err)
        }
    }
    
    return nil
}

// Shutdown останавливает адаптер
func (a *Adapter) Shutdown(ctx context.Context) error {
    if a.bot != nil {
        a.bot.StopReceivingUpdates()
    }
    return nil
}

// HealthCheck проверяет здоровье адаптера
func (a *Adapter) HealthCheck(ctx context.Context) error {
    if a.bot == nil {
        return fmt.Errorf("bot not initialized")
    }
    
    // Пробуем получить информацию о боте
    _, err := a.bot.GetMe()
    return err
}

// HandleWebhook обрабатывает webhook от Telegram
func (a *Adapter) HandleWebhook(ctx context.Context, payload []byte) error {
    var update tgbotapi.Update
    if err := json.Unmarshal(payload, &update); err != nil {
        return fmt.Errorf("failed to unmarshal update: %w", err)
    }
    
    // Обрабатываем ChatMember события (баны)
    if update.ChatMember != nil {
        return a.handleChatMemberUpdate(ctx, update.ChatMember)
    }
    
    // Обрабатываем команды
    if update.Message != nil && update.Message.IsCommand() {
        return a.handleCommand(ctx, update.Message)
    }
    
    return nil
}

// handleChatMemberUpdate обрабатывает изменение статуса участника
func (a *Adapter) handleChatMemberUpdate(ctx context.Context, chatMember *tgbotapi.ChatMemberUpdated) error {
    // Проверяем, является ли это баном
    newStatus := chatMember.NewChatMember.Status
    
    if newStatus != "kicked" && newStatus != "banned" && newStatus != "restricted" {
        return nil // Не бан, пропускаем
    }
    
    // Конвертируем в UnifiedBanEvent
    event, err := a.convertToUnifiedBanEvent(chatMember)
    if err != nil {
        return fmt.Errorf("failed to convert event: %w", err)
    }
    
    // Публикуем событие
    if err := a.eventPublisher.PublishBanDetected(ctx, event); err != nil {
        return fmt.Errorf("failed to publish event: %w", err)
    }
    
    return nil
}

// convertToUnifiedBanEvent конвертирует Telegram событие в унифицированный формат
func (a *Adapter) convertToUnifiedBanEvent(chatMember *tgbotapi.ChatMemberUpdated) (*domain.UnifiedBanEvent, error) {
    user := chatMember.NewChatMember.User
    chat := chatMember.Chat
    
    // Определяем тип бана
    var banType domain.BanType
    var banDuration *int64
    
    switch chatMember.NewChatMember.Status {
    case "kicked", "banned":
        banType = domain.BanTypePermanent
    case "restricted":
        banType = domain.BanTypeRestrict
        if chatMember.NewChatMember.UntilDate != 0 {
            duration := int64(chatMember.NewChatMember.UntilDate - int(chatMember.Date))
            banDuration = &duration
        }
    default:
        banType = domain.BanTypeKick
    }
    
    // Создаём UnifiedUser
    username := user.UserName
    displayName := user.FirstName
    if user.LastName != "" {
        displayName += " " + user.LastName
    }
    
    unifiedUser := domain.UnifiedUser{
        Platform:       domain.PlatformTelegram,
        PlatformUserID: fmt.Sprintf("%d", user.ID),
        Username:       &username,
        DisplayName:    &displayName,
    }
    
    // Создаём UnifiedChat
    chatTitle := chat.Title
    memberCount := 0
    unifiedChat := domain.UnifiedChat{
        Platform:       domain.PlatformTelegram,
        PlatformChatID: fmt.Sprintf("%d", chat.ID),
        ChatType:       chat.Type,
        Title:          &chatTitle,
        MemberCount:    &memberCount,
    }
    
    // Инициатор (если есть)
    var initiator *domain.UnifiedUser
    if chatMember.From != nil {
        fromUsername := chatMember.From.UserName
        fromDisplayName := chatMember.From.FirstName
        if chatMember.From.LastName != "" {
            fromDisplayName += " " + chatMember.From.LastName
        }
        
        initiator = &domain.UnifiedUser{
            Platform:       domain.PlatformTelegram,
            PlatformUserID: fmt.Sprintf("%d", chatMember.From.ID),
            Username:       &fromUsername,
            DisplayName:    &fromDisplayName,
        }
    }
    
    // Создаём событие
    eventID := fmt.Sprintf("tg_%d_%d_%d", chat.ID, user.ID, chatMember.Date)
    timestamp := time.Unix(int64(chatMember.Date), 0)
    
    return &domain.UnifiedBanEvent{
        EventID:     eventID,
        Platform:    domain.PlatformTelegram,
        User:        unifiedUser,
        Chat:        unifiedChat,
        BanType:     banType,
        BanDuration: banDuration,
        Initiator:   initiator,
        Timestamp:   timestamp,
    }, nil
}

// NormalizeBanEvent нормализует событие бана
func (a *Adapter) NormalizeBanEvent(ctx context.Context, rawEvent map[string]interface{}) (*domain.UnifiedBanEvent, error) {
    // Конвертируем map в JSON, затем в ChatMemberUpdated
    jsonData, err := json.Marshal(rawEvent)
    if err != nil {
        return nil, err
    }
    
    var chatMember tgbotapi.ChatMemberUpdated
    if err := json.Unmarshal(jsonData, &chatMember); err != nil {
        return nil, err
    }
    
    return a.convertToUnifiedBanEvent(&chatMember)
}

// BanUser банит пользователя в Telegram
func (a *Adapter) BanUser(ctx context.Context, req domain.BanUserRequest) error {
    chatID, err := parseChatID(req.ChatID)
    if err != nil {
        return err
    }
    
    userID, err := parseUserID(req.UserID)
    if err != nil {
        return err
    }
    
    banConfig := tgbotapi.BanChatMemberConfig{
        ChatMemberConfig: tgbotapi.ChatMemberConfig{
            ChatID: chatID,
            UserID: userID,
        },
    }
    
    // Если указана длительность, устанавливаем временный бан
    if req.Duration != nil {
        until := time.Now().Add(time.Duration(*req.Duration) * time.Second)
        banConfig.UntilDate = until.Unix()
    }
    
    _, err = a.bot.Request(banConfig)
    if err != nil {
        return fmt.Errorf("failed to ban user: %w", err)
    }
    
    return nil
}

// UnbanUser разбанивает пользователя
func (a *Adapter) UnbanUser(ctx context.Context, chatID, userID string) error {
    chatIDInt, err := parseChatID(chatID)
    if err != nil {
        return err
    }
    
    userIDInt, err := parseUserID(userID)
    if err != nil {
        return err
    }
    
    unbanConfig := tgbotapi.UnbanChatMemberConfig{
        ChatMemberConfig: tgbotapi.ChatMemberConfig{
            ChatID: chatIDInt,
            UserID: userIDInt,
        },
    }
    
    _, err = a.bot.Request(unbanConfig)
    return err
}

// GetUserInfo получает информацию о пользователе
func (a *Adapter) GetUserInfo(ctx context.Context, userID string) (*domain.UnifiedUser, error) {
    // Telegram API не предоставляет метод для получения пользователя по ID
    // без взаимодействия с ним. Возвращаем базовую информацию
    return &domain.UnifiedUser{
        Platform:       domain.PlatformTelegram,
        PlatformUserID: userID,
    }, nil
}

// GetChatInfo получает информацию о чате
func (a *Adapter) GetChatInfo(ctx context.Context, chatID string) (*domain.UnifiedChat, error) {
    chatIDInt, err := parseChatID(chatID)
    if err != nil {
        return nil, err
    }
    
    chat, err := a.bot.GetChat(tgbotapi.ChatInfoConfig{
        ChatConfig: tgbotapi.ChatConfig{
            ChatID: chatIDInt,
        },
    })
    if err != nil {
        return nil, fmt.Errorf("failed to get chat: %w", err)
    }
    
    title := chat.Title
    memberCount := chat.MemberCount
    
    return &domain.UnifiedChat{
        Platform:       domain.PlatformTelegram,
        PlatformChatID: chatID,
        ChatType:       chat.Type,
        Title:          &title,
        MemberCount:    &memberCount,
    }, nil
}

// GetChatAdmins получает список администраторов чата
func (a *Adapter) GetChatAdmins(ctx context.Context, chatID string) ([]*domain.UnifiedUser, error) {
    chatIDInt, err := parseChatID(chatID)
    if err != nil {
        return nil, err
    }
    
    admins, err := a.bot.GetChatAdministrators(tgbotapi.ChatAdministratorsConfig{
        ChatConfig: tgbotapi.ChatConfig{
            ChatID: chatIDInt,
        },
    })
    if err != nil {
        return nil, fmt.Errorf("failed to get admins: %w", err)
    }
    
    result := make([]*domain.UnifiedUser, 0, len(admins))
    for _, admin := range admins {
        username := admin.User.UserName
        displayName := admin.User.FirstName
        if admin.User.LastName != "" {
            displayName += " " + admin.User.LastName
        }
        
        result = append(result, &domain.UnifiedUser{
            Platform:       domain.PlatformTelegram,
            PlatformUserID: fmt.Sprintf("%d", admin.User.ID),
            Username:       &username,
            DisplayName:    &displayName,
        })
    }
    
    return result, nil
}

// CheckUserPermissions проверяет права пользователя
func (a *Adapter) CheckUserPermissions(ctx context.Context, chatID, userID string) (*domain.UserPermissions, error) {
    chatIDInt, err := parseChatID(chatID)
    if err != nil {
        return nil, err
    }
    
    userIDInt, err := parseUserID(userID)
    if err != nil {
        return nil, err
    }
    
    member, err := a.bot.GetChatMember(tgbotapi.GetChatMemberConfig{
        ChatConfigWithUser: tgbotapi.ChatConfigWithUser{
            ChatID: chatIDInt,
            UserID: userIDInt,
        },
    })
    if err != nil {
        return nil, fmt.Errorf("failed to get member: %w", err)
    }
    
    isAdmin := member.Status == "administrator" || member.Status == "creator"
    isOwner := member.Status == "creator"
    
    canBan := isAdmin
    canDelete := isAdmin
    
    // Для администраторов проверяем конкретные права
    if member.Status == "administrator" {
        canBan = member.CanRestrictMembers
        canDelete = member.CanDeleteMessages
    }
    
    return &domain.UserPermissions{
        CanBanUsers:       canBan,
        CanDeleteMessages: canDelete,
        IsAdmin:           isAdmin,
        IsOwner:           isOwner,
    }, nil
}

// SendMessage отправляет сообщение
func (a *Adapter) SendMessage(ctx context.Context, req domain.SendMessageRequest) error {
    chatIDInt, err := parseChatID(req.ChatID)
    if err != nil {
        return err
    }
    
    msg := tgbotapi.NewMessage(chatIDInt, req.Text)
    
    // Применяем опции если есть
    if req.Options != nil {
        if parseMode, ok := req.Options["parse_mode"].(string); ok {
            msg.ParseMode = parseMode
        }
        if disablePreview, ok := req.Options["disable_web_page_preview"].(bool); ok {
            msg.DisableWebPagePreview = disablePreview
        }
    }
    
    _, err = a.bot.Send(msg)
    return err
}

// handleCommand обрабатывает команды бота
func (a *Adapter) handleCommand(ctx context.Context, message *tgbotapi.Message) error {
    // Здесь будет логика обработки команд типа /subscribe, /list и т.д.
    // Пока оставляем заглушку
    return nil
}

// Helper functions
func parseChatID(chatID string) (int64, error) {
    var id int64
    _, err := fmt.Sscanf(chatID, "%d", &id)
    return id, err
}

func parseUserID(userID string) (int64, error) {
    var id int64
    _, err := fmt.Sscanf(userID, "%d", &id)
    return id, err
}
```

---

### internal/platform/vk/adapter.go - Заглушка

```go
package vk

import (
    "context"
    "fmt"
    
    "ban-sync-system/internal/domain"
)

// Adapter - заглушка для VK (пока не реализовано)
type Adapter struct {
    eventPublisher domain.EventPublisher
}

func NewAdapter(eventPublisher domain.EventPublisher) *Adapter {
    return &Adapter{
        eventPublisher: eventPublisher,
    }
}

func (a *Adapter) GetPlatformType() domain.PlatformType {
    return domain.PlatformVK
}

func (a *Adapter) GetName() string {
    return "VK Adapter (Not Implemented)"
}

func (a *Adapter) GetVersion() string {
    return "0.0.0"
}

func (a *Adapter) Initialize(ctx context.Context, config map[string]interface{}) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) Shutdown(ctx context.Context) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) HealthCheck(ctx context.Context) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) HandleWebhook(ctx context.Context, payload []byte) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) NormalizeBanEvent(ctx context.Context, rawEvent map[string]interface{}) (*domain.UnifiedBanEvent, error) {
    return nil, fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) BanUser(ctx context.Context, req domain.BanUserRequest) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) UnbanUser(ctx context.Context, chatID, userID string) error {
    return fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) GetUserInfo(ctx context.Context, userID string) (*domain.UnifiedUser, error) {
    return nil, fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) GetChatInfo(ctx context.Context, chatID string) (*domain.UnifiedChat, error) {
    return nil, fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) GetChatAdmins(ctx context.Context, chatID string) ([]*domain.UnifiedUser, error) {
    return nil, fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) CheckUserPermissions(ctx context.Context, chatID, userID string) (*domain.UserPermissions, error) {
    return nil, fmt.Errorf("VK adapter not implemented yet")
}

func (a *Adapter) SendMessage(ctx context.Context, req domain.SendMessageRequest) error {
    return fmt.Errorf("VK adapter not implemented yet")
}
```

---

### internal/platform/factory.go - Фабрика адаптеров

```go
package platform

import (
    "context"
    "fmt"
    
    "ban-sync-system/internal/domain"
    "ban-sync-system/internal/platform/telegram"
    "ban-sync-system/internal/platform/vk"
    "ban-sync-system/internal/platform/discord"
)

// Factory создаёт адаптеры платформ
type Factory struct {
    eventPublisher domain.EventPublisher
}

// NewFactory создаёт новую фабрику
func NewFactory(eventPublisher domain.EventPublisher) *Factory {
    return &Factory{
        eventPublisher: eventPublisher,
    }
}

// CreateAdapter создаёт адаптер для указанной платформы
func (f *Factory) CreateAdapter(platformType domain.PlatformType) (domain.PlatformAdapter, error) {
    switch platformType {
    case domain.PlatformTelegram:
        return telegram.NewAdapter(f.eventPublisher), nil
    case domain.PlatformVK:
        return vk.NewAdapter(f.eventPublisher), nil
    case domain.PlatformDiscord:
        return discord.NewAdapter(f.eventPublisher), nil
    default:
        return nil, fmt.Errorf("unsupported platform: %s", platformType)
    }
}

// GetAvailablePlatforms возвращает список доступных платформ
func (f *Factory) GetAvailablePlatforms() []domain.PlatformType {
    return []domain.PlatformType{
        domain.PlatformTelegram,
        // domain.PlatformVK,      // Раскомментировать когда будет реализовано
        // domain.PlatformDiscord, // Раскомментировать когда будет реализовано
    }
}

// InitializeAdapter создаёт и инициализирует адаптер
func (f *Factory) InitializeAdapter(
    ctx context.Context,
    platformType domain.PlatformType,
    config map[string]interface{},
) (domain.PlatformAdapter, error) {
    adapter, err := f.CreateAdapter(platformType)
    if err != nil {
        return nil, err
    }
    
    if err := adapter.Initialize(ctx, config); err != nil {
        return nil, fmt.Errorf("failed to initialize adapter: %w", err)
    }
    
    return adapter, nil
}
```

---

## 3. Repository Layer - Реализация PostgreSQL

### internal/repository/postgres/subscription.go

```go
package postgres

import (
    "context"
    "database/sql"
    "fmt"
    "time"
    
    "ban-sync-system/internal/domain"
)

type SubscriptionRepository struct {
    db *sql.DB
}

func NewSubscriptionRepository(db *sql.DB) *SubscriptionRepository {
    return &SubscriptionRepository{db: db}
}

func (r *SubscriptionRepository) Create(ctx context.Context, sub *domain.Subscription) error {
    query := `
        INSERT INTO subscriptions (
            admin_user_id,
            admin_platform,
            admin_platform_chat_id,
            tracked_user_id,
            tracked_platform,
            created_at,
            updated_at,
            is_active
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
    `
    
    now := time.Now()
    sub.CreatedAt = now
    sub.UpdatedAt = now
    sub.IsActive = true
    
    err := r.db.QueryRowContext(
        ctx,
        query,
        sub.AdminUserID,
        sub.AdminPlatform,
        sub.AdminPlatformChatID,
        sub.TrackedUserID,
        sub.TrackedPlatform,
        sub.CreatedAt,
        sub.UpdatedAt,
        sub.IsActive,
    ).Scan(&sub.ID)
    
    if err != nil {
        return fmt.Errorf("failed to create subscription: %w", err)
    }
    
    return nil
}

func (r *SubscriptionRepository) GetByID(ctx context.Context, id int64) (*domain.Subscription, error) {
    query := `
        SELECT
            id,
            admin_user_id,
            admin_platform,
            admin_platform_chat_id,
            tracked_user_id,
            tracked_platform,
            created_at,
            updated_at,
            is_active
        FROM subscriptions
        WHERE id = $1
    `
    
    sub := &domain.Subscription{}
    err := r.db.QueryRowContext(ctx, query, id).Scan(
        &sub.ID,
        &sub.AdminUserID,
        &sub.AdminPlatform,
        &sub.AdminPlatformChatID,
        &sub.TrackedUserID,
        &sub.TrackedPlatform,
        &sub.CreatedAt,
        &sub.UpdatedAt,
        &sub.IsActive,
    )
    
    if err == sql.ErrNoRows {
        return nil, nil
    }
    if err != nil {
        return nil, fmt.Errorf("failed to get subscription: %w", err)
    }
    
    return sub, nil
}

func (r *SubscriptionRepository) Delete(ctx context.Context, id int64) error {
    query := `
        UPDATE subscriptions
        SET is_active = false, updated_at = $1
        WHERE id = $2
    `
    
    _, err := r.db.ExecContext(ctx, query, time.Now(), id)
    if err != nil {
        return fmt.Errorf("failed to delete subscription: %w", err)
    }
    
    return nil
}

func (r *SubscriptionRepository) GetByAdmin(
    ctx context.Context,
    adminUserID string,
    platform domain.PlatformType,
) ([]*domain.Subscription, error) {
    query := `
        SELECT
            id,
            admin_user_id,
            admin_platform,
            admin_platform_chat_id,
            tracked_user_id,
            tracked_platform,
            created_at,
            updated_at,
            is_active
        FROM subscriptions
        WHERE admin_user_id = $1
          AND admin_platform = $2
          AND is_active = true
        ORDER BY created_at DESC
    `
    
    rows, err := r.db.QueryContext(ctx, query, adminUserID, platform)
    if err != nil {
        return nil, fmt.Errorf("failed to get subscriptions: %w", err)
    }
    defer rows.Close()
    
    var subscriptions []*domain.Subscription
    for rows.Next() {
        sub := &domain.Subscription{}
        err := rows.Scan(
            &sub.ID,
            &sub.AdminUserID,
            &sub.AdminPlatform,
            &sub.AdminPlatformChatID,
            &sub.TrackedUserID,
            &sub.TrackedPlatform,
            &sub.CreatedAt,
            &sub.UpdatedAt,
            &sub.IsActive,
        )
        if err != nil {
            return nil, fmt.Errorf("failed to scan subscription: %w", err)
        }
        subscriptions = append(subscriptions, sub)
    }
    
    return subscriptions, nil
}

func (r *SubscriptionRepository) GetSubscribers(
    ctx context.Context,
    trackedUserID string,
    platform domain.PlatformType,
) ([]*domain.Subscription, error) {
    query := `
        SELECT
            id,
            admin_user_id,
            admin_platform,
            admin_platform_chat_id,
            tracked_user_id,
            tracked_platform,
            created_at,
            updated_at,
            is_active
        FROM subscriptions
        WHERE tracked_user_id = $1
          AND tracked_platform = $2
          AND is_active = true
    `
    
    rows, err := r.db.QueryContext(ctx, query, trackedUserID, platform)
    if err != nil {
        return nil, fmt.Errorf("failed to get subscribers: %w", err)
    }
    defer rows.Close()
    
    var subscriptions []*domain.Subscription
    for rows.Next() {
        sub := &domain.Subscription{}
        err := rows.Scan(
            &sub.ID,
            &sub.AdminUserID,
            &sub.AdminPlatform,
            &sub.AdminPlatformChatID,
            &sub.TrackedUserID,
            &sub.TrackedPlatform,
            &sub.CreatedAt,
            &sub.UpdatedAt,
            &sub.IsActive,
        )
        if err != nil {
            return nil, fmt.Errorf("failed to scan subscription: %w", err)
        }
        subscriptions = append(subscriptions, sub)
    }
    
    return subscriptions, nil
}

func (r *SubscriptionRepository) Exists(
    ctx context.Context,
    adminUserID, trackedUserID string,
    platform domain.PlatformType,
) (bool, error) {
    query := `
        SELECT EXISTS(
            SELECT 1 FROM subscriptions
            WHERE admin_user_id = $1
              AND tracked_user_id = $2
              AND admin_platform = $3
              AND is_active = true
        )
    `
    
    var exists bool
    err := r.db.QueryRowContext(ctx, query, adminUserID, trackedUserID, platform).Scan(&exists)
    if err != nil {
        return false, fmt.Errorf("failed to check subscription existence: %w", err)
    }
    
    return exists, nil
}

func (r *SubscriptionRepository) CountByAdmin(
    ctx context.Context,
    adminUserID string,
    platform domain.PlatformType,
) (int64, error) {
    query := `
        SELECT COUNT(*)
        FROM subscriptions
        WHERE admin_user_id = $1
          AND admin_platform = $2
          AND is_active = true
    `
    
    var count int64
    err := r.db.QueryRowContext(ctx, query, adminUserID, platform).Scan(&count)
    if err != nil {
        return 0, fmt.Errorf("failed to count subscriptions: %w", err)
    }
    
    return count, nil
}
```