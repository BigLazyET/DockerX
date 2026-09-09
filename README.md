## 说明

### 1. 共享网络

```ps
# 这个网络后续可以给 RabbitMQ、Prometheus、Grafana、其他应用涉及到observability的共用。
docker network create observability
```