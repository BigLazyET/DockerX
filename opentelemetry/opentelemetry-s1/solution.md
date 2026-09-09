我会按“可直接落地跑起来”的方式给你：一个推荐目录结构、完整 `docker-compose.yml`、两个 Collector 配置、Grafana 数据源配置，并说明什么时候才需要自己构建镜像。可以直接用官方镜像搭，不需要自己准备 `otel collector` 二进制，也不需要自己写 Dockerfile。除非你要做这些事：

- 使用官方 Collector 镜像没有包含的自定义 receiver / processor / exporter
- 自己编译裁剪版 OpenTelemetry Collector
- 内置公司 CA、私有插件、特殊认证逻辑
- 固化 Grafana 插件、Dashboard、ClickHouse schema 到自定义镜像里

普通验证和中小规模部署，用官方镜像即可：

```text
App / SDK
  ↓ OTLP
otel-gateway collector
  ↓ Kafka exporter
Kafka
  ↓ Kafka receiver
otel-clickhouse-sink collector
  ↓ ClickHouse exporter
ClickHouse
  ↑
Grafana 查询展示
```

推荐不要让第一个 Collector 直接写 ClickHouse。既然你要模拟 `OpenTelemetry + Kafka + ClickHouse + Grafana`，建议拆成两个 Collector：

| 角色 | 作用 |
|---|---|
| `otel-gateway` | 接收应用 OTLP 数据，然后写入 Kafka |
| `kafka` | 缓冲、削峰、解耦 traces / metrics / logs |
| `otel-clickhouse-sink` | 从 Kafka 消费 OTLP 数据，然后写入 ClickHouse |
| `clickhouse` | 存储 traces、metrics、logs |
| `grafana` | 通过 ClickHouse datasource 查询和展示 |

---

## 目录结构

建议目录如下：

```text
otel-clickhouse-demo/
  docker-compose.yml
  otel/
    gateway.yaml
    clickhouse-sink.yaml
  grafana/
    provisioning/
      datasources/
        clickhouse.yaml
  clickhouse/
    init/
      001-create-db.sql
```

---

## docker-compose.yml

```yaml
version: "3.9"

services:
  kafka:
    image: bitnami/kafka:3.7
    container_name: kafka
    ports:
      - "9092:9092"
    environment:
      ALLOW_PLAINTEXT_LISTENER: "yes"
      KAFKA_CFG_NODE_ID: "0"
      KAFKA_CFG_PROCESS_ROLES: "controller,broker"
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: "0@kafka:9093"
      KAFKA_CFG_LISTENERS: "PLAINTEXT://:9092,CONTROLLER://:9093"
      KAFKA_CFG_ADVERTISED_LISTENERS: "PLAINTEXT://kafka:9092"
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: "CONTROLLER"
      KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"
    healthcheck:
      test: ["CMD-SHELL", "kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null 2>&1"]
      interval: 10s
      timeout: 5s
      retries: 10

  clickhouse:
    image: clickhouse/clickhouse-server:24.8
    container_name: clickhouse
    ports:
      - "8123:8123"
      - "9000:9000"
    environment:
      CLICKHOUSE_DB: otel
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: "1"
    volumes:
      - clickhouse-data:/var/lib/clickhouse
      - ./clickhouse/init:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "clickhouse-client --query 'SELECT 1'"]
      interval: 10s
      timeout: 5s
      retries: 10

  otel-gateway:
    image: otel/opentelemetry-collector-contrib:0.109.0
    container_name: otel-gateway
    command: ["--config=/etc/otelcol-contrib/gateway.yaml"]
    volumes:
      - ./otel/gateway.yaml:/etc/otelcol-contrib/gateway.yaml:ro
    ports:
      - "4317:4317"
      - "4318:4318"
      - "8888:8888"
    depends_on:
      kafka:
        condition: service_healthy

  otel-clickhouse-sink:
    image: otel/opentelemetry-collector-contrib:0.109.0
    container_name: otel-clickhouse-sink
    command: ["--config=/etc/otelcol-contrib/clickhouse-sink.yaml"]
    volumes:
      - ./otel/clickhouse-sink.yaml:/etc/otelcol-contrib/clickhouse-sink.yaml:ro
    depends_on:
      kafka:
        condition: service_healthy
      clickhouse:
        condition: service_healthy

  grafana:
    image: grafana/grafana:11.2.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_INSTALL_PLUGINS: grafana-clickhouse-datasource
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      clickhouse:
        condition: service_healthy

volumes:
  clickhouse-data:
  grafana-data:
```

启动：

```bash
docker compose up -d
```

访问：

```text
Grafana:    http://localhost:3000
ClickHouse: http://localhost:8123
OTLP gRPC:  localhost:4317
OTLP HTTP:  http://localhost:4318
```

Grafana 默认账号：

```text
admin / admin
```

---

## clickhouse/init/001-create-db.sql

```sql
CREATE DATABASE IF NOT EXISTS otel;
```

ClickHouse exporter 可以自动建表，所以这里只建数据库即可。

---

## otel/gateway.yaml

这个 Collector 负责接收应用侧的 OTLP 数据，然后写入 Kafka。

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

  batch:
    timeout: 5s
    send_batch_size: 2048

exporters:
  kafka/traces:
    brokers:
      - kafka:9092
    topic: otel-traces
    encoding: otlp_proto

  kafka/metrics:
    brokers:
      - kafka:9092
    topic: otel-metrics
    encoding: otlp_proto

  kafka/logs:
    brokers:
      - kafka:9092
    topic: otel-logs
    encoding: otlp_proto

  debug:
    verbosity: basic

service:
  telemetry:
    logs:
      level: info
    metrics:
      address: 0.0.0.0:8888

  pipelines:
    traces:
      receivers:
        - otlp
      processors:
        - memory_limiter
        - batch
      exporters:
        - kafka/traces
        - debug

    metrics:
      receivers:
        - otlp
      processors:
        - memory_limiter
        - batch
      exporters:
        - kafka/metrics
        - debug

    logs:
      receivers:
        - otlp
      processors:
        - memory_limiter
        - batch
      exporters:
        - kafka/logs
        - debug
```

这里的数据方向是：

```text
应用主动 push OTLP 到 otel-gateway
otel-gateway 主动 push 到 Kafka
```

---

## otel/clickhouse-sink.yaml

这个 Collector 负责从 Kafka 消费数据，然后写入 ClickHouse。

```yaml
receivers:
  kafka/traces:
    brokers:
      - kafka:9092
    topic: otel-traces
    group_id: otel-clickhouse-traces
    encoding: otlp_proto

  kafka/metrics:
    brokers:
      - kafka:9092
    topic: otel-metrics
    group_id: otel-clickhouse-metrics
    encoding: otlp_proto

  kafka/logs:
    brokers:
      - kafka:9092
    topic: otel-logs
    group_id: otel-clickhouse-logs
    encoding: otlp_proto

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

  batch:
    timeout: 5s
    send_batch_size: 2048

exporters:
  clickhouse:
    endpoint: tcp://clickhouse:9000?dial_timeout=10s&compress=lz4
    database: otel
    username: default
    password: ""
    create_schema: true
    ttl: 168h

  debug:
    verbosity: basic

service:
  telemetry:
    logs:
      level: info

  pipelines:
    traces:
      receivers:
        - kafka/traces
      processors:
        - memory_limiter
        - batch
      exporters:
        - clickhouse
        - debug

    metrics:
      receivers:
        - kafka/metrics
      processors:
        - memory_limiter
        - batch
      exporters:
        - clickhouse
        - debug

    logs:
      receivers:
        - kafka/logs
      processors:
        - memory_limiter
        - batch
      exporters:
        - clickhouse
        - debug
```

这里的数据方向是：

```text
otel-clickhouse-sink 主动从 Kafka 消费
otel-clickhouse-sink 主动写入 ClickHouse
```

Kafka 在这里不是必须的，但它让架构更接近生产环境。

---

## grafana/provisioning/datasources/clickhouse.yaml

Grafana 通过 ClickHouse datasource 查询数据。

```yaml
apiVersion: 1

datasources:
  - name: ClickHouse
    type: grafana-clickhouse-datasource
    access: proxy
    isDefault: true
    editable: true
    jsonData:
      server: clickhouse
      port: 9000
      protocol: native
      username: default
      defaultDatabase: otel
      tlsSkipVerify: true
    secureJsonData:
      password: ""
```

如果你的 Grafana ClickHouse 插件版本使用 `host` 而不是 `server`，可以改成：

```yaml
jsonData:
  host: clickhouse
  port: 9000
  protocol: native
  username: default
  defaultDatabase: otel
```

不同版本插件的 provisioning 字段略有差异。如果 Grafana 启动后数据源没有自动可用，可以在 UI 里手动创建：

```text
Connections → Data sources → ClickHouse
Host: clickhouse
Port: 9000
Protocol: Native
Database: otel
User: default
Password: 空
```

---

## 验证 ClickHouse 是否写入数据

启动后可以看 Collector 日志：

```bash
docker logs -f otel-gateway
docker logs -f otel-clickhouse-sink
```

查看 ClickHouse 表：

```bash
docker exec -it clickhouse clickhouse-client --database otel --query "SHOW TABLES"
```

常见会出现类似表，具体表名取决于 Collector ClickHouse exporter 版本：

```text
otel_logs
otel_metrics_sum
otel_metrics_gauge
otel_metrics_histogram
otel_traces
```

查询 traces：

```bash
docker exec -it clickhouse clickhouse-client --database otel --query "SELECT * FROM otel_traces LIMIT 5 FORMAT Vertical"
```

查询 logs：

```bash
docker exec -it clickhouse clickhouse-client --database otel --query "SELECT * FROM otel_logs LIMIT 5 FORMAT Vertical"
```

查询 metrics 表：

```bash
docker exec -it clickhouse clickhouse-client --database otel --query "SHOW TABLES LIKE '%metrics%'"
```

---

## 可选：加一个 telemetry generator 造数据

如果你只是验证链路，可以临时跑 OpenTelemetry 官方的 telemetrygen。

生成 traces：

```bash
docker run --rm --network otel-clickhouse-demo_default \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces \
  --otlp-endpoint otel-gateway:4317 \
  --otlp-insecure \
  --duration 30s
```

生成 metrics：

```bash
docker run --rm --network otel-clickhouse-demo_default \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  metrics \
  --otlp-endpoint otel-gateway:4317 \
  --otlp-insecure \
  --duration 30s
```

生成 logs：

```bash
docker run --rm --network otel-clickhouse-demo_default \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  logs \
  --otlp-endpoint otel-gateway:4317 \
  --otlp-insecure \
  --duration 30s
```

如果你的 compose 项目名不是 `otel-clickhouse-demo`，Docker network 名会不同，可以用下面命令查看：

```bash
docker network ls
```

---

## Grafana 中怎么查

Grafana 里添加 ClickHouse datasource 后，可以直接写 SQL。

查询 trace 数量：

```sql
SELECT
  ServiceName,
  count() AS spans
FROM otel.otel_traces
GROUP BY ServiceName
ORDER BY spans DESC
LIMIT 20
```

按服务看错误 span：

```sql
SELECT
  ServiceName,
  SpanName,
  StatusCode,
  count() AS count
FROM otel.otel_traces
WHERE StatusCode != 'STATUS_CODE_OK'
GROUP BY
  ServiceName,
  SpanName,
  StatusCode
ORDER BY count DESC
LIMIT 50
```

按时间统计 span 数：

```sql
SELECT
  toStartOfMinute(Timestamp) AS time,
  count() AS spans
FROM otel.otel_traces
WHERE $__timeFilter(Timestamp)
GROUP BY time
ORDER BY time
```

查询日志：

```sql
SELECT
  Timestamp,
  SeverityText,
  ServiceName,
  Body
FROM otel.otel_logs
WHERE $__timeFilter(Timestamp)
ORDER BY Timestamp DESC
LIMIT 100
```

具体字段名可能因 ClickHouse exporter 版本不同略有差异，先执行：

```sql
DESCRIBE TABLE otel.otel_traces;
DESCRIBE TABLE otel.otel_logs;
```

确认字段名后再建 Grafana 面板。

---

## 是否需要自己构建 Dockerfile？

一般不需要。

| 场景 | 是否需要自建 Dockerfile | 说明 |
|---|---:|---|
| 本地验证架构 | 否 | 官方镜像足够 |
| 普通生产部署 | 通常否 | 使用官方 `otel/opentelemetry-collector-contrib` 即可 |
| 需要 Kafka exporter | 否 | contrib 镜像包含 Kafka exporter |
| 需要 ClickHouse exporter | 否 | contrib 镜像通常包含 ClickHouse exporter |
| 需要 Grafana ClickHouse 插件 | 否 | 用 `GF_INSTALL_PLUGINS` 安装即可 |
| 需要内置 Dashboard / 插件 / 公司证书 | 可以 | 自定义 Grafana 镜像更稳定 |
| 需要自定义 Collector 组件 | 是 | 要用 OpenTelemetry Collector Builder 自己编译 |
| 需要极小镜像体积 | 可以 | 自己裁剪 Collector distribution |

如果要生产化，我建议：

```text
第一阶段：直接用官方镜像验证链路
第二阶段：固定版本、补齐认证、持久化、资源限制
第三阶段：需要自定义组件时，再构建自定义 Collector 镜像
```

---

## 最终结论

你要的架构可以用 Docker Compose 直接搭出来，不需要手工准备二进制：

```text
OpenTelemetry Collector Gateway
  ↓
Kafka
  ↓
OpenTelemetry Collector Sink
  ↓
ClickHouse
  ↓
Grafana
```

其中：

| 组件 | 数据流角色 |
|---|---|
| `otel-gateway` | 接收应用 OTLP 数据，写 Kafka |
| `kafka` | 存放 `otel-traces`、`otel-metrics`、`otel-logs` 三类 topic |
| `otel-clickhouse-sink` | 从 Kafka 消费三类数据，写 ClickHouse |
| `clickhouse` | 统一存储 traces、metrics、logs |
| `grafana` | 连接 ClickHouse，通过 SQL 查询和展示 |

这套方案适合做链路追踪可视化的 PoC，也能作为生产架构雏形。生产环境里重点补：ClickHouse schema/TTL/分区、副本、Kafka 持久化、Collector 队列和重试、Grafana dashboard provisioning、认证和 TLS。