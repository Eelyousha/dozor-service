# Dozor - Trust-Based Cross-Platform Ban Synchronization

**Trust moderators, not just ban lists. Synchronize moderation actions across platforms automatically.**

## How It Works

### 🤝 Trust System

Admin A trusts Admin B's moderation decisions. When Admin B bans a user, that user is automatically banned in Admin A's chats.

### 🔄 Self-Sync

Admin manages multiple chats. Ban someone in Chat 1? They're instantly banned in Chat 2, Chat 3, and all other chats you moderate.

### 🌐 Cross-Platform

Works across Telegram, VK, Discord, WhatsApp. Trust relationships work even between different platforms.

## Example Scenarios

**Scenario 1: Trust Network**

```
Admin A → trusts Admin B
Admin A → trusts Admin C

Admin B bans User123 → User123 banned in all Admin A's chats
Admin C bans User456 → User456 banned in all Admin A's chats
```

**Scenario 2: Self-Sync**

```
Admin manages: Chat1, Chat2, Chat3

Admin bans User in Chat1 → Auto-banned in Chat2 and Chat3
```

**Scenario 3: Selective Sync**

```
Admin A → trusts Admin B (only for Chat X and Chat Y)

Admin B bans User → User banned only in Chat X and Chat Y
```

## Features

- 🤝 Trust-based moderation network
- 🔄 Auto-sync across your own chats
- 🎯 Selective chat targeting
- 🌐 Multi-platform support
- ⚡ Real-time synchronization
- 📊 Detailed sync logs
- 🔐 Permission-based access

Built with Go, PostgreSQL, RabbitMQ, Redis.
