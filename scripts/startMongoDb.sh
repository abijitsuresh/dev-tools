#!/zsh

# --- Configuration ---
MONGOD_PATH=$(which mongod)
BASE_DATA_DIR="$HOME/mongodb_local_data"
PRIMARY_CONF="./mongo.conf" # Should contain: replication.replSetName: "rs0"

# Secondary node paths
NODE2_DIR="$BASE_DATA_DIR/node2"
NODE3_DIR="$BASE_DATA_DIR/node3"
NODE2_PORT=27018
NODE3_PORT=27019

# Function to stop all local mongo instances
stop_mongo() {
    pgrep -x mongod > /dev/null && { 
        echo "Stopping running mongod processes..."
        pkill -x mongod
        sleep 2 
    } || echo "No mongo processes currently running."
}

# Function to show current replica set status
check_status() {
    echo "--- MongoDB Status ---"
    mongosh --port 27017 --quiet --eval '
        try {
            var status = rs.status();
            print("Replica Set: " + status.set);
            status.members.forEach(function(m) {
                print(" - " + m.name + " [" + m.stateStr + "]");
            });
        } catch (e) {
            print("Error: Could not connect to Primary or RS not initialized.");
        }
    '
}

case $1 in
    "single")
        stop_mongo
        echo "Starting Single Node (Primary)..."
        $MONGOD_PATH --config "$PRIMARY_CONF" --fork
        
        echo "Reconfiguring as Standalone Replica Set..."
        sleep 2
        mongosh --port 27017 --quiet --eval '
            var config = rs.conf();
            if (config && config.members.length > 1) {
                var newConfig = config;
                newConfig.members = [config.members[0]]; 
                newConfig.version++;
                rs.reconfig(newConfig, {force: true});
                print("Cluster nodes removed. Running as Single Primary.");
            } else if (!config) {
                rs.initiate();
                print("Replica set initiated.");
            }
        '
        check_status
        ;;

    "cluster")
        stop_mongo
        echo "Starting 3-Node Cluster..."
        
        # 1. Start Nodes
        $MONGOD_PATH --config "$PRIMARY_CONF" --fork
        mkdir -p "$NODE2_DIR" "$NODE3_DIR"
        $MONGOD_PATH --port $NODE2_PORT --dbpath "$NODE2_DIR" --replSet rs0 --fork --logpath "$NODE2_DIR/mongo.log"
        $MONGOD_PATH --port $NODE3_PORT --dbpath "$NODE3_DIR" --replSet rs0 --fork --logpath "$NODE3_DIR/mongo.log"

        echo "Waiting for nodes to sync..."
        sleep 4

        # 2. Add members
        mongosh --port 27017 --quiet --eval '
            var config = rs.conf();
            if (!config) { rs.initiate(); sleep(2000); }
            rs.add("localhost:27018");
            rs.add("localhost:27019");
        '
        check_status
        ;;

    "status")
        check_status
        ;;

    "stop")
        stop_mongo
        ;;

    "clean")
        stop_mongo
        echo "Wiping secondary data: $NODE2_DIR and $NODE3_DIR"
        rm -rf "$NODE2_DIR" "$NODE3_DIR"
        ;;

    *)
        echo "Usage: $0 {single|cluster|status|stop|clean}"
        ;;
esac
