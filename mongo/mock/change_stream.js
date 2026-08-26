use change_stream_demo

// 新增
db.orders.insertOne({
  orderNo: "ORDER-003",
  customer: "Charlie",
  amount: 300,
  status: "Created",
  createdAt: new Date()
})

// 修改
db.orders.updateOne(
  { orderNo: "ORDER-001" },
  {
    $set: {
      status: "Paid",
      paidAt: new Date()
    }
  }
)

// 替换整个文档
db.orders.replaceOne(
  { orderNo: "ORDER-002" },
  {
    orderNo: "ORDER-002",
    customer: "Bob",
    amount: 220,
    status: "Updated",
    updatedAt: new Date()
  }
)

// 删除
db.orders.deleteOne({
  orderNo: "ORDER-003"
})