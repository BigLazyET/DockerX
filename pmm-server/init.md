## MongoDB添加PMM监控用户
```shell
# 进入mongo容器
docker exec -it mongo mongosh

# 创建pmm用户
use admin

db.createUser({
  user: "pmm",
  pwd: "pmm_password",
  roles: [
    { role: "clusterMonitor", db: "admin" },
    { role: "readAnyDatabase", db: "admin" },
    { role: "read", db: "local" }
  ]
})

# 修改pmm用户的密码
db.changeUserPassword("pmm", "新的Mongo监控用户密码")
```

## 连接
```shell
# pmm-client 连接到MongoDB
docker exec -it pmm-client pmm-admin add mongodb \
  --service-name=mongo \
  --host=host.docker.internal \
  --port=27017

# 如果mongo开启认证
docker exec -it pmm-client pmm-admin add mongodb \
  --service-name=mongo \
  --host=host.docker.internal \
  --port=27017 \
  --username=pmm \
  --password=pmm_password \
  --authentication-database=admin

# 执行后检查
docker exec -it pmm-client pmm-admin list
docker exec -it pmm-client pmm-admin status
```

## mongo开启慢查询
```shell
# 开启慢查询 profiling，比如记录超过 50ms 的查询：
db.setProfilingLevel(1, { slowms: 50 })

# 确认是否开启
db.getProfilingStatus()

# 创建slow_items表，供后续模拟慢查询
db.slow_items.drop()

let bulk = []
for (let i = 0; i < 300000; i++) {
  bulk.push({
    userId: i,
    category: "cat_" + (i % 1000),
    status: i % 3 === 0 ? "active" : "inactive",
    payload: "x".repeat(500),
    createdAt: new Date(Date.now() - i * 1000)
  })

  if (bulk.length === 1000) {
    db.slow_items.insertMany(bulk)
    bulk = []
  }
}

if (bulk.length) {
  db.slow_items.insertMany(bulk)
}

# 慢查询，关键是：不要给 category、payload、createdAt 建索引
for (let i = 0; i < 20; i++) {
  db.slow_items.find({
    category: "cat_777",
    payload: /xxxxxxxxxxxxxxxxxxxxxxxx/
  }).sort({ createdAt: -1 }).limit(20).toArray()
}
```

## 重建连接
```shell
# 先删除连接
docker exec -it pmm-client pmm-admin remove mongodb mongo

# 再创建连接
docker exec -it pmm-client pmm-admin add mongodb \
  --service-name=mongo \
  --host=host.docker.internal \
  --port=27017 \
  --username=pmm \
  --password=pmm_password \
  --authentication-database=admin \
  --query-source=profiler
```
