@echo off
echo Testing MQTT with VerneMQ container
echo ===================================

echo.
echo 1. Testing connection...
curl -s http://localhost:1883 || echo "MQTT port check (this is expected to fail for HTTP)"

echo.
echo 2. Testing with mosquitto clients (if installed)...
echo Publishing test message...
mosquitto_pub -h localhost -p 1883 -t "test/explorer" -m "Hello from command line!" || echo "mosquitto_pub not installed"

echo.
echo 3. Subscribing to test topic...
mosquitto_sub -h localhost -p 1883 -t "test/explorer" -C 1 || echo "mosquitto_sub not installed"

echo.
echo 4. Container logs (last 10 lines)...
docker logs vernemq-compose-test --tail=10

echo.
echo 5. Container status...
docker ps | findstr vernemq

echo.
echo Test complete! Use MQTT Explorer with:
echo - Host: localhost
echo - Port: 1883
echo - No authentication required
pause