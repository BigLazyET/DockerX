### 访问
```
Prometheus UI: http://localhost:9090
Targets:       http://localhost:9090/targets
```
在Target页里应该能看到：

```
rabbitmq    UP
```

### 后续其他应用加入Prometheus

以后其他应用只要暴露 metrics，例如：
```
http://some-app:8080/metrics
```
并且加入 observability 网络，就可以在 prometheus.yml 里继续追加：
```yaml
scrape_configs:
  - job_name: rabbitmq
    static_configs:
      - targets:
          - rabbitmq:15692

  - job_name: some-app
    metrics_path: /metrics
    static_configs:
      - targets:
          - some-app:8080
```
修改后让 Prometheus 热加载配置：
```shell
curl -X POST http://localhost:9090/-/reload
```
前提是 Compose 里已经开启了：
```yaml
--web.enable-lifecycle
```