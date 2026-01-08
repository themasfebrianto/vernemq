@echo off
REM SSL Certificate Generator for VerneMQ MQTT TLS (Windows)
REM This script generates self-signed certificates for development/testing
REM For production, use certificates from a trusted CA (e.g., Let's Encrypt)
REM Requires OpenSSL to be installed and available in PATH

setlocal EnableDelayedExpansion

cd /d "%~dp0"

REM Configuration
set DAYS=365
set COUNTRY=ID
set STATE=DKI Jakarta
set LOCALITY=Jakarta
set ORGANIZATION=VerneMQ Development
set COMMON_NAME=vernemq.local

echo =========================================
echo VerneMQ SSL Certificate Generator
echo =========================================
echo.

REM Check if OpenSSL is available
where openssl >nul 2>&1
if errorlevel 1 (
    echo ERROR: OpenSSL is not installed or not in PATH.
    echo Please install OpenSSL and try again.
    echo Download from: https://slproweb.com/products/Win32OpenSSL.html
    pause
    exit /b 1
)

REM Create CA (Certificate Authority)
echo 1. Creating CA private key...
openssl genrsa -out ca.key 4096

echo 2. Creating CA certificate...
openssl req -new -x509 -days %DAYS% -key ca.key -out ca.crt -subj "/C=%COUNTRY%/ST=%STATE%/L=%LOCALITY%/O=%ORGANIZATION%/CN=VerneMQ CA"

REM Create Server Certificate
echo 3. Creating server private key...
openssl genrsa -out server.key 4096

echo 4. Creating server certificate signing request...
openssl req -new -key server.key -out server.csr -subj "/C=%COUNTRY%/ST=%STATE%/L=%LOCALITY%/O=%ORGANIZATION%/CN=%COMMON_NAME%"

REM Create extensions file for SAN (Subject Alternative Names)
echo authorityKeyIdentifier=keyid,issuer > server_ext.cnf
echo basicConstraints=CA:FALSE >> server_ext.cnf
echo keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment >> server_ext.cnf
echo subjectAltName = @alt_names >> server_ext.cnf
echo. >> server_ext.cnf
echo [alt_names] >> server_ext.cnf
echo DNS.1 = vernemq.local >> server_ext.cnf
echo DNS.2 = vernemq >> server_ext.cnf
echo DNS.3 = localhost >> server_ext.cnf
echo IP.1 = 127.0.0.1 >> server_ext.cnf
echo IP.2 = ::1 >> server_ext.cnf

echo 5. Creating server certificate...
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days %DAYS% -extfile server_ext.cnf

REM Clean up temporary files
del /q server.csr server_ext.cnf ca.srl 2>nul

echo.
echo =========================================
echo SSL Certificates Generated Successfully!
echo =========================================
echo.
echo Files created:
echo   - ca.crt      : CA certificate (share with clients)
echo   - ca.key      : CA private key (keep secure)
echo   - server.crt  : Server certificate
echo   - server.key  : Server private key
echo.
echo Next steps:
echo 1. In docker-compose.yml, uncomment the SSL configuration lines
echo 2. Restart the containers: docker-compose up -d
echo 3. Test TLS connection with mosquitto_pub using --cafile ssl/ca.crt
echo.
echo For production, use certificates from a trusted CA!
echo.

pause
