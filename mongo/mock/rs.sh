# 生成Keyfile，供 MongoDB 副本集使用
mkdir -p ./mongo-keyfile

openssl rand -base64 756 > ./mongo-keyfile/keyfile

chmod 400 ./mongo-keyfile/keyfile
sudo chown 999:999 ./mongo-keyfile/keyfile

# 初始化副本集
docker exec mongo mongosh \
 -u root \
 -p '.netcore' \
 --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "宿主机ip:27017" }
  ]
})
'

docker exec mongo mongosh --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27017" }
  ]
})
'

# 查看状态
docker exec mongo mongosh --quiet --eval 'rs.status()'