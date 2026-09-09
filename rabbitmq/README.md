### 访问
```
# 账号密码：admin / .netcore
RabbitMQ UI: http://localhost:15672
Metrics:     http://localhost:15692/metrics
```

### 插件功能

通过**enabled_plugins**来开启插件功能，当前开启prometheus功能来监控其metrics

### 最终访问地址
| 服务 | 地址 |
| --- | --- |
| RabbitMQ AMQP | `amqp://admin:admin123@localhost:5672/` |
| RabbitMQ UI | `http://localhost:15672` |
| RabbitMQ Metrics | `http://localhost:15692/metrics` |