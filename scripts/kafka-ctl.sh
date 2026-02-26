#!/bin/bash

# --- ROBUST PATH RESOLUTION ---
# Get the absolute path of the script itself
# Using 'perl' here because macOS 'readlink' doesn't have the -f flag by default
SCRIPT_PATH=$(perl -MCwd -e 'print Cwd::abs_path shift' "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Derive absolute paths for everything else
# This ensures that even if you are in /Users/name/Desktop, the script 
# looks inside /Users/name/development-tools/...
KAFKA_BASE=$(dirname "$SCRIPT_DIR")
KAFKA_HOME="$KAFKA_BASE/kafka/server"
LOG_DIR="$KAFKA_BASE/kafka/logs"
CONFIG="$KAFKA_HOME/config/server.properties"
PID_FILE="$LOG_DIR/kafka.pid"
BOOTSTRAP="localhost:9092"

# Safety check: ensure paths were resolved
if [ ! -d "$KAFKA_HOME" ]; then
    echo "❌ Error: Kafka home not found at $KAFKA_HOME"
    exit 1
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

case "$1" in
    # --- SERVER CONTROL ---
    start)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "❌ Kafka is already running (PID: $(cat "$PID_FILE"))."
            exit 1
        fi
        
        # Auto-format KRaft storage if metadata is missing
        LOG_DIR_PROP=$(grep "^log.dirs=" "$CONFIG" | cut -d'=' -f2)
        # Handle tilde or relative paths in config if necessary
        EVAL_LOG_DIR=$(eval echo "$LOG_DIR_PROP")
        
        if [ ! -f "$EVAL_LOG_DIR/meta.properties" ]; then
            echo "🐣 First run: Formatting KRaft storage..."
            CLUSTER_ID=$("$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)
            "$KAFKA_HOME/bin/kafka-storage.sh" format --standalone -t "$CLUSTER_ID" -c "$CONFIG"
            if [ $? -ne 0 ]; then
                echo "❌ Storage format failed. Check your config path."
                exit 1
            fi
        fi

        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        CURRENT_LOG="$LOG_DIR/kafka-$TIMESTAMP.log"
        
        nohup "$KAFKA_HOME/bin/kafka-server-start.sh" "$CONFIG" > "$CURRENT_LOG" 2>&1 &
        echo $! > "$PID_FILE"
        ln -sf "$CURRENT_LOG" "$LOG_DIR/latest.log"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        CURRENT_LOG="$LOG_DIR/kafka-$TIMESTAMP.log"
        nohup "$KAFKA_HOME/bin/kafka-server-start.sh" "$CONFIG" > "$CURRENT_LOG" 2>&1 &
        NEW_PID=$!
        echo $NEW_PID > "$PID_FILE"
        ln -sf "$CURRENT_LOG" "$LOG_DIR/latest.log"
        
        # 4. Health Check: Wait up to 10 seconds for port 9092
        echo -n "⏳ Waiting for Kafka to initialize..."
        for i in {1..10}; do
            if lsof -Pi :9092 -sTCP:LISTEN -t >/dev/null; then
                echo -e "\n✅ Started Kafka (PID: $(cat "$PID_FILE"))."
                echo "📜 Logging to: kafka-$TIMESTAMP.log"
                exit 0
            fi
            echo -n "."
            sleep 1
        done
        
        echo -e "\n❌ Kafka failed to start. Last few lines of log:"
        tail -n 10 "$CURRENT_LOG"
        rm -f "$PID_FILE"
        exit 1
        ;;

    stop)
        if [ ! -f "$PID_FILE" ]; then
            echo "⚠️ No PID file found. Kafka might not be running."
        else
            "$KAFKA_HOME/bin/kafka-server-stop.sh"
            rm -f "$PID_FILE"
            echo "🛑 Stopped."
        fi
        ;;

    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "🟢 Status: RUNNING (PID: $(cat "$PID_FILE"))"
            echo "📂 Active Log: $(readlink "$LOG_DIR/latest.log")"
        else
            echo "🔴 Status: STOPPED"
        fi
        ;;

    tail)
        echo "📋 Tailing latest log (Ctrl+C to stop)..."
        tail -f "$LOG_DIR/latest.log"
        ;;

    search)
        [ -z "$2" ] && echo "Usage: $0 search <term>" && exit 1
        echo "🔍 Searching all logs for '$2'..."
        grep -rnE "$2" "$LOG_DIR" --exclude="latest.log" | less
        ;;

    # --- TOPIC MANAGEMENT ---
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

    # --- DATA OPERATIONS ---
    post-json)
        [ -z "$2" ] && echo "Usage: $0 post-json <topic> '<json>'" && exit 1
        JSON_DATA="${3:-$(cat)}"
        echo "$JSON_DATA" | "$KAFKA_HOME/bin/kafka-console-producer.sh" --topic "$2" --bootstrap-server $BOOTSTRAP
        echo "📥 Message sent to $2"
        ;;

    consume)
        [ -z "$2" ] && echo "Usage: $0 consume <topic>" && exit 1
        echo "📻 Reading messages from '$2' (Ctrl+C to stop)..."
        "$KAFKA_HOME/bin/kafka-console-consumer.sh" --topic "$2" --bootstrap-server $BOOTSTRAP --from-beginning
        ;;

    stats)
        if [ -z "$2" ]; then
            echo "👥 Active Consumer Groups:"
            "$KAFKA_HOME/bin/kafka-consumer-groups.sh" --bootstrap-server $BOOTSTRAP --list
        else
            echo "📊 Stats for Topic: $2"
            "$KAFKA_HOME/bin/kafka-topics.sh" --describe --topic "$2" --bootstrap-server $BOOTSTRAP
            echo -e "\n📉 Offset Information:"
            "$KAFKA_HOME/bin/kafka-run-class.sh" kafka.tools.GetOffsetShell --broker-list $BOOTSTRAP --topic "$2" --time -1
        fi
        ;;

    # --- CLEANUP ---
    clean)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "❌ Error: Kafka is still running. Please run stop first."
            exit 1
        fi
        echo "⚠️  DANGER: This will delete ALL topics, data, and logs."
        read -p "Are you sure? (y/n): " CONFIRM
        if [ "$CONFIRM" == "y" ]; then
            DATA_DIR=$(grep "^log.dirs=" "$CONFIG" | cut -d'=' -f2)
            EVAL_DATA_DIR=$(eval echo "$DATA_DIR")
            rm -rf "$EVAL_DATA_DIR"/*
            rm -rf "$LOG_DIR"/*.log
            rm -rf "$LOG_DIR"/*.pid
            echo "✨ Environment wiped clean. Run 'start' to re-initialize."
        else
            echo "Aborted."
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|status|tail|search|create|list|delete|post-json|consume|stats|clean}"
        exit 1
esac
