#!/bin/bash

curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  --data @mysql-connector.json

curl http://localhost:8083/connectors/demo-mysql-connector/status