下面只讨论 **这些组件处于 OTel Collector 下游时** 的数据接收方式。

先给结论：

```text
绝大多数下游系统是由 OTel Collector 主动 push 数据过去。
Prometheus 是一个特例：它通常主动 scrape，也就是 pull OTel Collector 暴露的 /metrics。
Kafka、Vector 不是必须的，只是在大规模、缓冲、削峰、解耦场景下才引入。
```

---

## 1. OTel Collector 下游组件如何接收数据

| 下游组件 | 主要接收数据类型 | Collector 到下游的典型方式 | 是 Collector 主动推吗 | 是下游主动拉吗 | 是否必须经过 Kafka / Vector | 常见协议 / Exporter | 说明 |
|---|---|---|---:|---:|---:|---|---|
| **Prometheus** | Metrics | Collector 暴露 `/metrics`，Prometheus 来 scrape | 否，默认不是 | 是，典型模式 | 否 | `prometheus exporter` | Collector 把 metrics 转成 Prometheus 格式并暴露 HTTP endpoint，Prometheus 定期抓取 |
| **Prometheus Remote Write 后端** | Metrics | Collector 主动 remote write 到目标 | 是 | 否 | 否 | `prometheusremotewrite exporter` | 适用于 VictoriaMetrics、Mimir、Cortex、Thanos Receive、部分 Prometheus remote-write receiver |
| **VictoriaMetrics** | Metrics | Collector 主动 remote write 到 VictoriaMetrics | 是 | 否 | 否 | `prometheusremotewrite exporter` | VictoriaMetrics 通常接收 Prometheus remote write，是 OTel metrics 的常见下游 |
| **Loki** | Logs | Collector 主动推 logs 到 Loki | 是 | 否 | 否 | `loki exporter` 或 OTLP 相关接入 | Loki 通常作为日志后端，由 Collector、Alloy、Promtail、Fluent Bit 等推送日志 |
| **Tempo** | Traces | Collector 主动通过 OTLP 推 traces 到 Tempo | 是 | 否 | 否 | `otlp exporter` | Tempo 原生适合接收 OTLP trace，常见路径是 OTel Collector → Tempo |
| **Jaeger** | Traces | Collector 主动推 traces 到 Jaeger | 是 | 否 | 否 | `jaeger exporter` 或 `otlp exporter` | 新架构里通常推荐 OTLP；Jaeger 也可接收 Jaeger 协议 |
| **Zipkin** | Traces | Collector 主动推 traces 到 Zipkin | 是 | 否 | 否 | `zipkin exporter` | Collector 把 OTel trace 转成 Zipkin 格式发送 |
| **Elasticsearch / Elastic** | Logs、Traces、Metrics | Collector 主动推到 Elastic / APM endpoint | 是 | 否 | 否 | `elasticsearchexporter`、`otlp exporter`、Elastic APM 接入 | Elastic 可以接 OTel logs/traces/metrics，具体取决于 Elastic 版本和接入方式 |
| **ClickHouse** | Logs、Traces、Metrics、Events | Collector 主动写入，或经 Kafka/Vector 再写入 | 通常是 | 否 | 否，但大规模场景常用 | ClickHouse exporter、Kafka exporter、HTTP/native 写入链路 | 直接写适合简单架构；大规模建议经 Kafka/Vector 做缓冲、转换、削峰 |
| **Grafana** | 展示 Metrics、Logs、Traces | Grafana 查询各数据源，不直接作为 Collector 下游存储 | 否 | Grafana 拉数据源 | 不适用 | Grafana data source plugin | Grafana 通常不是 OTel Collector 的接收端，它查询 Prometheus、Loki、Tempo、Elastic、ClickHouse 等 |
| **Kafka** | Metrics、Logs、Traces | Collector 主动推到 Kafka topic | 是 | 否 | 它本身就是中间层 | `kafka exporter` | 用于缓冲、削峰、解耦、多消费者分发 |
| **Vector** | Metrics、Logs、Traces | Collector 推给 Vector，或 Vector 拉/收集后再发下游 | 视配置而定 | 视配置而定 | 它本身是中间层 | OTLP、HTTP、Kafka、Loki、ClickHouse 等 | Vector 是数据管道/转换器，不是必须组件 |

---

## 更清晰的推拉分类

| 模式 | 谁主动 | 典型组件 | 数据类型 | 典型链路 |
|---|---|---|---|---|
| **Push 模式** | OTel Collector 主动发给下游 | Tempo、Loki、Jaeger、Zipkin、VictoriaMetrics、Elastic、ClickHouse、Kafka | Logs、Traces、Metrics | `App → Collector → Tempo/Loki/Elastic/ClickHouse` |
| **Pull / Scrape 模式** | 下游主动到 Collector 抓取 | Prometheus | Metrics | `App → Collector 暴露 /metrics → Prometheus scrape` |
| **Remote Write Push 模式** | OTel Collector 主动写入 remote write endpoint | VictoriaMetrics、Mimir、Cortex、Thanos Receive、Prometheus remote-write receiver | Metrics | `App → Collector → remote_write → VictoriaMetrics` |
| **消息队列中转模式** | Collector 先推 Kafka，再由消费者写下游 | Kafka + ClickHouse / Elastic / 自研消费端 | Logs、Traces、Metrics | `App → Collector → Kafka → ClickHouse` |
| **管道中转模式** | Collector 推给 Vector，或 Vector 接收后再转发 | Vector + Loki / ClickHouse / Elastic | Logs、Metrics、Traces | `App → Collector → Vector → Loki/ClickHouse` |

---

## 是否必须经过 Kafka / Vector？

不必须。

Kafka、Vector、Fluent Bit、Grafana Alloy 这类组件的作用是 **增强数据管道能力**，不是 OpenTelemetry 架构的硬性要求。

| 中间层 | 是否必须 | 主要价值 | 适合场景 |
|---|---:|---|---|
| **Kafka** | 否 | 缓冲、削峰、解耦、重放、多消费者分发 | 数据量大、下游不稳定、需要多套系统消费同一份 telemetry |
| **Vector** | 否 | 日志/指标/trace 转换、过滤、路由、采样、协议适配 | 需要复杂数据加工，或者想把日志管道独立出来 |
| **Fluent Bit** | 否 | 轻量日志采集与转发 | Kubernetes 日志、节点日志、容器 stdout |
| **Grafana Alloy** | 否 | Grafana 生态采集器，支持 OTel、Prometheus、Loki 等 | 使用 Grafana 生态，希望统一 agent |
| **OTel Collector 自己** | 通常足够 | 接收、处理、批量、重试、导出 | 标准 OTel 架构，大多数场景直接用它就可以 |

简单判断：

```text
中小规模：App → OTel Collector → 后端
大规模/强解耦：App → OTel Collector → Kafka/Vector → 后端
```

---

# 2. Prometheus endpoint 和 remote write 是什么意思

你问的这句：

> OTel Collector 可暴露 Prometheus endpoint 或 remote write

这里其实是两个完全不同的接入模式。

---

## Prometheus endpoint 是什么

**Prometheus endpoint** 指的是一个可以被 Prometheus 抓取的 HTTP 地址，通常是：

```text
http://otel-collector:8889/metrics
```

这个 endpoint 会返回 Prometheus 文本格式的指标，例如：

```text
http_server_duration_seconds_count{service_name="order-service",http_method="GET"} 1234
http_server_duration_seconds_sum{service_name="order-service",http_method="GET"} 56.7
process_cpu_seconds_total{service_name="order-service"} 88.2
```

Prometheus 会定期访问这个地址，把指标抓取回来并存进自己的 TSDB。

链路是：

```text
Application
  ↓ OTLP push
OpenTelemetry Collector
  ↓ 暴露 /metrics endpoint
Prometheus
  ↓ query
Grafana
```

注意这里的方向：

```text
Collector 不主动发给 Prometheus
Prometheus 主动来 Collector 拉
```

也就是：

```text
Prometheus scrape OTel Collector
```

---

## Prometheus endpoint 的作用

| 作用 | 说明 |
|---|---|
| **协议适配** | 把 OTel metrics 转成 Prometheus 能理解的格式 |
| **兼容 Prometheus pull 模型** | Prometheus 原生设计就是 scrape，不是被动接收 |
| **保留 Prometheus 生态** | 可以继续使用 PromQL、Alertmanager、Grafana dashboard |
| **集中暴露指标** | 应用不一定都暴露 Prometheus `/metrics`，可以统一由 Collector 暴露 |

示意：

```text
App 通过 OTLP 把 metrics 推给 Collector
Collector 把这些 metrics 临时转换并暴露成 Prometheus /metrics
Prometheus 定期 scrape Collector
```

---

## OTel Collector 中 Prometheus exporter 示例

大概配置长这样：

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

含义是：

```text
Collector 接收 OTLP metrics
然后在 0.0.0.0:8889 暴露 Prometheus 格式的 /metrics
Prometheus 再去 scrape 这个地址
```

Prometheus 侧配置类似：

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]
```

---

## Remote write 是什么

**Prometheus remote write** 是 Prometheus 生态里的一个远程写入协议。

它的作用是：

```text
把指标数据主动写入一个远程存储后端
```

也就是说，remote write 是 **push 模式**。

链路可以是 Prometheus 自己 remote write：

```text
Prometheus
  ↓ remote_write
VictoriaMetrics / Mimir / Cortex / Thanos Receive
```

也可以是 OTel Collector 直接 remote write：

```text
Application
  ↓ OTLP
OpenTelemetry Collector
  ↓ prometheus remote write
VictoriaMetrics / Mimir / Cortex / Thanos Receive
```

这里方向是：

```text
Collector 主动把 metrics 写到下游
```

---

## Remote write 的作用

| 作用 | 说明 |
|---|---|
| **远程长期存储** | Prometheus 本地存储有限，remote write 可写入长期存储 |
| **大规模指标汇聚** | 多个 Collector / Prometheus 写到同一个后端 |
| **兼容 Prometheus 生态** | 很多 TSDB 都支持 Prometheus remote write |
| **Push 到后端** | 不需要后端 scrape Collector |
| **适合云服务/集中存储** | 例如 VictoriaMetrics、Grafana Mimir、Cortex、Thanos Receive |

---

## OTel Collector 中 remote write 示例

```yaml
receivers:
  otlp:
    protocols:
      grpc:
      http:

exporters:
  prometheusremotewrite:
    endpoint: "http://victoriametrics:8428/api/v1/write"

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheusremotewrite]
```

含义是：

```text
Collector 接收 OTLP metrics
Collector 主动把 metrics 用 Prometheus remote write 协议写入 VictoriaMetrics
```

---

## Prometheus endpoint vs remote write

| 对比项 | Prometheus endpoint | Remote write |
|---|---|---|
| 数据方向 | Prometheus → Collector | Collector → 下游存储 |
| 主动方 | Prometheus 主动拉 | Collector 主动推 |
| 模式 | Pull / scrape | Push / write |
| 典型下游 | Prometheus | VictoriaMetrics、Mimir、Cortex、Thanos Receive |
| Collector 使用的 exporter | `prometheus exporter` | `prometheusremotewrite exporter` |
| 是否需要 Prometheus 服务器 | 需要 | 不一定需要 |
| 是否适合 Prometheus 原生架构 | 是 | 是，但更偏远程存储 |
| 是否适合长期存储 | 取决于 Prometheus 本地存储 | 更适合 |
| 是否适合多集群汇聚 | 一般 | 更适合 |

---

## 两种模式的图

### 模式一：Prometheus scrape Collector

```text
Application
  ↓ OTLP push
OpenTelemetry Collector
  ↓ exposes /metrics
Prometheus
  ↓ query
Grafana
```

真实数据方向更准确地说是：

```text
Application → Collector
Prometheus → Collector scrape /metrics
Grafana → Prometheus query
```

适合：

- 你已经有 Prometheus
- 希望继续让 Prometheus 负责 scrape、存储、告警
- 指标规模不算特别大
- 保持 Prometheus 原生 pull 模式

---

### 模式二：Collector remote write 到远程 TSDB

```text
Application
  ↓ OTLP push
OpenTelemetry Collector
  ↓ remote_write push
VictoriaMetrics / Mimir / Cortex / Thanos Receive
  ↓ query
Grafana
```

适合：

- 不想让 Prometheus scrape Collector
- 希望 Collector 直接写入长期存储
- 多集群、多 Collector 汇聚
- 指标规模较大
- 使用 VictoriaMetrics 这类 remote write 后端

---

## 一个容易混淆的点

Prometheus 通常有两种角色：

| 角色 | 说明 |
|---|---|
| **Prometheus Server** | 主动 scrape `/metrics`，存本地 TSDB，提供 PromQL 查询 |
| **Prometheus Remote Write 协议** | 一种写入协议，很多后端都支持，不等于一定要有 Prometheus Server |

所以：

```text
Prometheus endpoint
```

指的是：

```text
给 Prometheus Server 抓取的 /metrics 地址
```

而：

```text
Prometheus remote write
```

指的是：

```text
把指标写入支持 remote write 协议的远程后端
```

二者都是 Prometheus 生态，但方向完全相反。

---

## 最终总结

| 问题 | 结论 |
|---|---|
| OTel Collector 下游通常是 push 还是 pull？ | 大多数是 Collector push，下游接收 |
| 哪个最典型是 pull？ | Prometheus scrape Collector 暴露的 Prometheus endpoint |
| Kafka / Vector 是否必须？ | 不必须，只在需要缓冲、削峰、解耦、复杂转换时引入 |
| Prometheus endpoint 是什么？ | Collector 暴露一个 `/metrics` HTTP 地址，让 Prometheus 来抓 |
| Remote write 是什么？ | Collector 或 Prometheus 主动把 metrics 写入远程指标存储 |
| Prometheus endpoint 和 remote write 最大区别？ | endpoint 是 Prometheus 拉；remote write 是 Collector/Prometheus 推 |
| VictoriaMetrics 常用哪种方式接 OTel metrics？ | Prometheus remote write |
| Grafana 是否接收 OTel Collector 数据？ | 通常不接收，它查询后端数据源做展示 |

一句话概括：

```text
Prometheus endpoint = OTel Collector 把指标摆出来，等 Prometheus 来拉；
remote write = OTel Collector 把指标主动写到远程 TSDB。
```