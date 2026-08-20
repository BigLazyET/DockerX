docker exec -i mongo mongosh \
  -u root \
  -p 'password' \
  --authenticationDatabase admin \
  app_db \
  --eval '
db.users.createIndex({ email: 1 }, { unique: true });
db.orders.createIndex({ orderNo: 1 }, { unique: true });
db.orders.createIndex({ status: 1, createdAt: -1 });

db.users.deleteMany({ mock: true });
db.orders.deleteMany({ mock: true });

const users = [
  {
    name: "Alice Zhang",
    email: "alice@example.com",
    age: 28,
    role: "admin",
    status: "active",
    mock: true,
    createdAt: new Date()
  },
  {
    name: "Bob Li",
    email: "bob@example.com",
    age: 34,
    role: "developer",
    status: "active",
    mock: true,
    createdAt: new Date()
  },
  {
    name: "Cindy Wang",
    email: "cindy@example.com",
    age: 25,
    role: "tester",
    status: "inactive",
    mock: true,
    createdAt: new Date()
  }
];

db.users.insertMany(users);

const insertedUsers = db.users.find({ mock: true }).toArray();

db.orders.insertMany([
  {
    orderNo: "MOCK-20260819-001",
    userId: insertedUsers[0]._id,
    amount: 497,
    status: "paid",
    mock: true,
    items: [
      { sku: "SKU-001", name: "Keyboard", quantity: 1, price: 299 },
      { sku: "SKU-002", name: "Mouse", quantity: 2, price: 99 }
    ],
    createdAt: new Date()
  },
  {
    orderNo: "MOCK-20260819-002",
    userId: insertedUsers[1]._id,
    amount: 1299,
    status: "pending",
    mock: true,
    items: [
      { sku: "SKU-003", name: "Monitor", quantity: 1, price: 1299 }
    ],
    createdAt: new Date()
  },
  {
    orderNo: "MOCK-20260819-003",
    userId: insertedUsers[2]._id,
    amount: 117,
    status: "cancelled",
    mock: true,
    items: [
      { sku: "SKU-004", name: "USB-C Cable", quantity: 3, price: 39 }
    ],
    createdAt: new Date()
  }
]);

print("users:", db.users.countDocuments({ mock: true }));
print("orders:", db.orders.countDocuments({ mock: true }));
'