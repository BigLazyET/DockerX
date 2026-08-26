用 Debezium 时，架构会从“.NET 直接订阅 MySQL binlog”变成：
```plaintext
MySQL binlog
  -> Debezium MySQL Connector
  -> Kafka / Redpanda Topic
  -> .NET Consumer 消费变更事件
```
.NET 不直接碰 MySQL replication protocol，而是消费 Debezium 输出的 CDC 事件。这是更稳的生产方式。