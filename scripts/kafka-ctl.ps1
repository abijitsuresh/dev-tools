# --- CONFIGURATION (Location-Aware) ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KafkaBase = Split-Path -Parent $ScriptDir
$KafkaHome = Join-Path $KafkaBase "kafka\server"
$LogDir = Join-Path $KafkaBase "kafka\logs"
$Config = Join-Path $KafkaHome "config\server.properties"
$PidFile = Join-Path $LogDir "kafka.pid"
$Bootstrap = "localhost:9092"

# Ensure log directory exists
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

function Start-Kafka {
    if (Test-Path $PidFile) {
        $oldPid = Get-Content $PidFile
        if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
            Write-Host "❌ Kafka is already running (PID: $oldPid)." -ForegroundColor Red
            return
        }
    }

    $DataDir = Join-Path $LogDir "data"
    if (!(Test-Path "$DataDir\meta.properties")) {
        Write-Host "🐣 First run: Formatting KRaft storage (Standalone)..." -ForegroundColor Cyan
        $ClusterId = & "$KafkaHome\bin\windows\kafka-storage.bat" random-uuid
        & "$KafkaHome\bin\windows\kafka-storage.bat" format --standalone -t $ClusterId -c $Config
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
    $CurrentLog = Join-Path $LogDir "kafka-$Timestamp.log"
    
    Write-Host "🚀 Starting Kafka..." -ForegroundColor Cyan
    # Start process in background
    $Proc = Start-Process -FilePath "$KafkaHome\bin\windows\kafka-server-start.bat" `
                         -ArgumentList @($Config, "--override", "log.dirs=$DataDir") `
                         -RedirectStandardOutput $CurrentLog `
                         -NoNewWindow -PassThru
    
    $Proc.Id | Out-File $PidFile
    
    # Health Check
    Write-Host "⏳ Waiting for Kafka to bind to 9092..." -NoNewline
    for ($i=0; $i -lt 15; $i++) {
        if (Get-NetTCPConnection -LocalPort 9092 -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "`n✅ Started (PID: $($Proc.Id))." -ForegroundColor Green
            return
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host "`n❌ Failed to start. Check $CurrentLog" -ForegroundColor Red
}

function Stop-Kafka {
    if (Test-Path $PidFile) {
        $Pid = Get-Content $PidFile
        Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue
        Remove-Item $PidFile
        Write-Host "🛑 Stopped." -ForegroundColor Yellow
    }
}

# --- COMMAND ROUTING ---
$Command = $args[0]
$Topic = $args[1]
$Payload = $args[2]

switch ($Command) {
    "start"  { Start-Kafka }
    "stop"   { Stop-Kafka }
    "status" { 
        if (Test-Path $PidFile) { Write-Host "🟢 RUNNING" -ForegroundColor Green }
        else { Write-Host "🔴 STOPPED" -ForegroundColor Red }
    }
    "list"   { & "$KafkaHome\bin\windows\kafka-topics.bat" --list --bootstrap-server $Bootstrap }
    "create" { & "$KafkaHome\bin\windows\kafka-topics.bat" --create --topic $Topic --bootstrap-server $Bootstrap --partitions 1 --replication-factor 1 }
    "delete" { & "$KafkaHome\bin\windows\kafka-topics.bat" --delete --topic $Topic --bootstrap-server $Bootstrap }
    "consume" { & "$KafkaHome\bin\windows\kafka-console-consumer.bat" --topic $Topic --bootstrap-server $Bootstrap --from-beginning }
    "post-json" { $Payload | & "$KafkaHome\bin\windows\kafka-console-producer.bat" --topic $Topic --bootstrap-server $Bootstrap }
    "stats" {
        & "$KafkaHome\bin\windows\kafka-topics.bat" --describe --topic $Topic --bootstrap-server $Bootstrap
        & "$KafkaHome\bin\windows\kafka-get-offsets.bat" --bootstrap-server $Bootstrap --topic $Topic --time -1
    }
    "clean"  {
        $Confirm = Read-Host "⚠️ Wipe all data? (y/n)"
        if ($Confirm -eq 'y') { Remove-Item "$LogDir\*" -Recurse -Force; Write-Host "✨ Cleaned." }
    }
    default  { Write-Host "Usage: .\kafka-ctl.ps1 {start|stop|status|list|create|delete|consume|post-json|stats|clean}" }
}
