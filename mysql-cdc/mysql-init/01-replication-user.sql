-- 创建一个专门用于读取 binlog/replication 的用户。
-- '%' 表示允许从任意主机连接。因为 .NET 程序可能运行在宿主机、其他容器或其他网络位置。

CREATE USER IF NOT EXISTS 'debezium'@'%' IDENTIFIED BY 'debezium_password';

GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT, LOCK TABLES
ON *.* TO 'debezium'@'%';

FLUSH PRIVILEGES;