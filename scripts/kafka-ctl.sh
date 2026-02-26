#!/bin/bash

# --- CONFIGURATION (Relative Paths) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAFKA_HOME="$(cd "$SCRIPT_DIR/../kafka/server" && pwd)"
LOG_DIR="$(cd "$SCRIPT_DIR/../kafka/logs" && pwd)"
CONFIG="$KAFKA_HOME/config/server.properties"
PID_FILE="$LOG_DIR/kafka.pid"
BOOTSTRAP="localhost:9092"

mkdir -p "$LOG_DIR"

case "$1" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "❌ Kafka is already running (PID: $(cat "$PID_FILE"))."
            exit 1
        fi
        
        # 1. Resolve Data Directory from Config
        LOG_DIR_PROP=$(grep "^log.dirs=" "$CONFIG" | cut -d'=' -f2)
        EVAL_DATA_DIR=$(eval echo "$LOG_DIR_PROP")
        
        # 2. KRaft Format (Standalone for 4.x)
        if [ ! -f "$EVAL_DATA_DIR/meta.properties" ]; then
            echo "🐣 First run: Formatting KRaft storage (Standalone)..."
            CLUSTER_ID=$("$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)
            "$KAFKA_HOME/bin/kafka-storage.sh" format --standalone -t "$CLUSTER_ID" -c "$CONFIG"
            if [ $? -ne 0 ]; then
                echo "❌ Storage format failed. Please check $CONFIG."
                exit 1
            fi
        fi

        # 3. Launch Kafka
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        CURRENT_LOG="$LOG_DIR/kafka-$TIMESTAMP.log"
        nohup "$KAFKA_HOME/bin/kafka-server-start.sh" "$CONFIG" > "$CURRENT_LOG" 2>&1 &
        NEW_PID=$!
        echo $NEW_PID > "$PID_FILE"
        ln -sf "$CURRENT_LOG" "$LOG_DIR/latest.log"
        
        # 4. Health Check (Wait for Port 9092)
        echo -n "⏳ Initializing Kafka..."
        for i in {1..15}; do
            if lsof -Pi :9092 -sTCP:LISTEN -t >/dev/null; then
                echo -e "\n✅ Started Kafka (PID: $NEW_PID)."
                exit 0
            fi
            echo -n "."
            sleep 1
        done

        # 5. Error Reporting if it didn't start
        echo -e "\n❌ Kafka failed to initialize within 15s. Check logs:"
        tail -n 15 "$CURRENT_LOG"
        rm -f "$PID_FILE"
        exit 1
        ;;

    stop)
        if [ ! -f "$PID_FILE" ]; then
            echo "⚠️ No PID file found."
        else
            "$KAFKA_HOME/bin/kafka-server-stop.sh"
            rm -f "$PID_FILE"
            echo "🛑 Stopped."
        fi
        ;;

    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "🟢 RUNNING (PID: $(cat "$PID_FILE"))"
            echo "📂 Log: $(readlink "$LOG_DIR/latest.log")"
        else
            echo "🔴 STOPPED"
        fi
        ;;

    tail)
        tail -f "$LOG_DIR/latest.log"
        ;;

    search)
        [ -z "$2" ] && echo "Usage: $0 search <term>" && exit 1
        grep -rnE "$2" "$LOG_DIR" --exclude="latest.log" | less
        ;;

    create)
        [ -z "$2" ] && echo "Usage: $0 create <topic>" && exit 1
        "$KAFKA_HOME/bin/kafka-topics.sh" --create --topic "$2" --bootstrap-server $BOOTSTRAP --partitions 1 --replication-factor 1
        ;;

    list)
        "$KAFKA_HOME/bin/kafka-topics.sh" --list --bootstrap-server $BOOTSTRAP
        ;;

    delete)
        [ -z "$2" ] && echo "Usage: $0 delete <topic>" && exit 1
        "$KAFKA_HOME/bin/kafka-topics.sh" --delete --topic "$2" --bootstrap-server $BOOTSTRAP
        ;;

    post-json)
        [ -z "$2" ] && echo "Usage: $0 post-json <topic> '<json>'" && exit 1
        JSON_DATA="${3:-$(cat)}"
        echo "$JSON_DATA" | "$KAFKA_HOME/bin/kafka-console-producer.sh" --topic "$2" --bootstrap-server $BOOTSTRAP
        ;;

    consume)
        [ -z "$2" ] && echo "Usage: $0 consume <topic>" && exit 1
        "$KAFKA_HOME/bin/kafka-console-consumer.sh" --topic "$2" --bootstrap-server $BOOTSTRAP --from-beginning
        ;;

    stats)
        [ -z "$2" ] && "$KAFKA_HOME/bin/kafka-consumer-groups.sh" --bootstrap-server $BOOTSTRAP --list && exit 0
        "$KAFKA_HOME/bin/kafka-topics.sh" --describe --topic "$2" --bootstrap-server $BOOTSTRAP
        ;;

    clean)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "❌ Stop Kafka first."
            exit 1
        fi
        read -p "⚠️ Wipe all data? (y/n): " CONFIRM
        if [ "$CONFIRM" == "y" ]; then
            DATA_DIR=$(grep "^log.dirs=" "$CONFIG" | cut -d'=' -f2)
            EVAL_DATA_DIR=$(eval echo "$DATA_DIR")
            rm -rf "$EVAL_DATA_DIR"/* "$LOG_DIR"/*.log "$LOG_DIR"/*.pid
            echo "✨ Cleaned."
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|status|tail|search|create|list|delete|post-json|consume|stats|clean}"
        exit 1
esac
