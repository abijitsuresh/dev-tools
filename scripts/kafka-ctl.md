# 🛠️ Kafka Portable Dev-Kit (MacOS)

Standalone **Apache Kafka 4.2.0** for corporate devices. Zero installation, zero admin rights.

## 📁 Installation
1. Ensure **Java 17+** is in your PATH (`java -version`).
2. Extract Kafka into `kafka/server/`.
3. Give permissions: `chmod +x scripts/kafka-ctl.sh`.

## 🕹️ Essential Commands
- **Start:** `./scripts/kafka-ctl.sh start` (Waits for health check)
- **Stop:** `./scripts/kafka-ctl.sh stop`
- **Tail Logs:** `./scripts/kafka-ctl.sh tail`
- **Search Logs:** `./scripts/kafka-ctl.sh search "ERROR"`

## 📨 Messaging
- **New Topic:** `./scripts/kafka-ctl.sh create my-topic`
- **List Topics:** `./scripts/kafka-ctl.sh list`
- **Send JSON:** `./scripts/kafka-ctl.sh post-json my-topic '{"id": 1}'`
- **Read Data:** `./scripts/kafka-ctl.sh consume my-topic`

## 🧹 Maintenance
- **Stats:** `./scripts/kafka-ctl.sh stats my-topic`
- **Clean:** `./scripts/kafka-ctl.sh clean` (Wipes all topics and data)
