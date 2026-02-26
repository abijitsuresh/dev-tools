@echo off
setlocal enabledelayedexpansion

:: --- CONFIGURATION (Location-Aware) ---
:: %~dp0 is the directory where the batch file lives
set SCRIPT_DIR=%~dp0
for %%i in ("%SCRIPT_DIR%..") do set KAFKA_BASE=%%~f1
set KAFKA_HOME=%KAFKA_BASE%\kafka\server
set LOG_DIR=%KAFKA_BASE%\kafka\logs
set CONFIG=%KAFKA_HOME%\config\server.properties
set PID_FILE=%LOG_DIR%\kafka.pid
set BOOTSTRAP=localhost:9092

:: Ensure log directory exists
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: --- COMMAND ROUTING ---
set CMD=%1
set TOPIC=%2
set PAYLOAD=%3

if "%CMD%"=="start" goto :start
if "%CMD%"=="stop" goto :stop
if "%CMD%"=="status" goto :status
if "%CMD%"=="list" goto :list
if "%CMD%"=="create" goto :create
if "%CMD%"=="delete" goto :delete
if "%CMD%"=="consume" goto :consume
if "%CMD%"=="post-json" goto :post_json
if "%CMD%"=="stats" goto :stats
if "%CMD%"=="clean" goto :clean

:usage
echo Usage: kafka-ctl.bat {start^|stop^|status^|list^|create^|delete^|consume^|post-json^|stats^|clean}
goto :eof

:start
:: Check if already running via PID file
if exist "%PID_FILE%" (
    set /p OLD_PID=<"%PID_FILE%"
    tasklist /FI "PID eq !OLD_PID!" | find "java.exe" >nul
    if !errorlevel!==0 (
        echo [X] Kafka is already running (PID: !OLD_PID!).
        goto :eof
    )
)

:: Format KRaft if meta.properties is missing
set DATA_DIR=%LOG_DIR%\data
if not exist "%DATA_DIR%\meta.properties" (
    echo [*] First run: Formatting KRaft storage (Standalone)...
    for /f "tokens=*" %%i in ('call "%KAFKA_HOME%\bin\windows\kafka-storage.bat" random-uuid') do set CLUSTER_ID=%%i
    call "%KAFKA_HOME%\bin\windows\kafka-storage.bat" format --standalone -t !CLUSTER_ID! -c "%CONFIG%"
)

set TIMESTAMP=%date:~10,4%%date:~4,2%%date:~7,2%-%time:~0,2%%time:~3,2%
set CURRENT_LOG=%LOG_DIR%\kafka-%TIMESTAMP: =0%.log

echo [*] Starting Kafka...
:: Start Kafka in a minimized separate window
start /min "Kafka Server" "%KAFKA_HOME%\bin\windows\kafka-server-start.bat" "%CONFIG%" --override log.dirs="%DATA_DIR%" ^> "%CURRENT_LOG%" 2^>^&1

:: Note: Batch cannot easily capture the background PID of a started window, 
:: so we'll look for the most recently started java.exe process
for /f "tokens=2" %%a in ('tasklist /FI "IMAGENAME eq java.exe" /NH /FO TABLE ^| sort /R') do (
    set NEW_PID=%%a
    echo !NEW_PID! > "%PID_FILE%"
    goto :health_check
)

:health_check
echo [*] Waiting for Kafka to bind to 9092...
for /L %%i in (1,1,15) do (
    netstat -ano | find "9092" | find "LISTENING" >nul
    if !errorlevel!==0 (
        echo [OK] Started.
        goto :eof
    )
    set /p dummy="." <nul
    timeout /t 1 >nul
)
echo.
echo [X] Failed to detect Kafka on port 9092. Check logs.
goto :eof

:stop
if exist "%PID_FILE%" (
    set /p TARGET_PID=<"%PID_FILE%"
    taskkill /PID !TARGET_PID! /F >nul 2>&1
    del "%PID_FILE%"
    echo [!] Stopped.
) else (
    echo [X] No PID file found.
)
goto :eof

:status
if exist "%PID_FILE%" (
    echo RUNNING
) else (
    echo STOPPED
)
goto :eof

:list
call "%KAFKA_HOME%\bin\windows\kafka-topics.bat" --list --bootstrap-server %BOOTSTRAP%
goto :eof

:create
call "%KAFKA_HOME%\bin\windows\kafka-topics.bat" --create --topic %TOPIC% --bootstrap-server %BOOTSTRAP% --partitions 1 --replication-factor 1
goto :eof

:delete
call "%KAFKA_HOME%\bin\windows\kafka-topics.bat" --delete --topic %TOPIC% --bootstrap-server %BOOTSTRAP%
goto :eof

:consume
call "%KAFKA_HOME%\bin\windows\kafka-console-consumer.bat" --topic %TOPIC% --bootstrap-server %BOOTSTRAP% --from-beginning
goto :eof

:post_json
echo %PAYLOAD% | call "%KAFKA_HOME%\bin\windows\kafka-console-producer.bat" --topic %TOPIC% --bootstrap-server %BOOTSTRAP%
goto :eof

:stats
call "%KAFKA_HOME%\bin\windows\kafka-topics.bat" --describe --topic %TOPIC% --bootstrap-server %BOOTSTRAP%
call "%KAFKA_HOME%\bin\windows\kafka-get-offsets.bat" --bootstrap-server %BOOTSTRAP% --topic %TOPIC% --time -1
goto :eof

:clean
set /p CONFIRM="⚠️ Wipe all data? (y/n): "
if /i "%CONFIRM%"=="y" (
    rd /s /q "%LOG_DIR%"
    mkdir "%LOG_DIR%"
    echo Cleaned.
)
goto :eof
