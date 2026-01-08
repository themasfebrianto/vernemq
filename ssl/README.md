# SSL Certificates Directory

This directory is used to store SSL/TLS certificates for VerneMQ MQTT over TLS (port 8883).

## Generating Self-Signed Certificates (Development)

### Linux/macOS:
```bash
chmod +x generate-certs.sh
./generate-certs.sh
```

### Windows:
```batch
generate-certs.bat
```

## Files Generated

| File | Description |
|------|-------------|
| `ca.crt` | CA certificate - share with MQTT clients for verification |
| `ca.key` | CA private key - **KEEP SECURE**, do not share |
| `server.crt` | Server certificate - used by VerneMQ |
| `server.key` | Server private key - **KEEP SECURE** |

## Enabling TLS in docker-compose.yml

After generating certificates, uncomment the following lines in `docker-compose.yml`:

```yaml
# In vernemq service environment:
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT=0.0.0.0:8883
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__CAFILE=/opt/vernemq/etc/ssl/ca.crt
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__CERTFILE=/opt/vernemq/etc/ssl/server.crt
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__KEYFILE=/opt/vernemq/etc/ssl/server.key
- DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT__REQUIRE_CERTIFICATE=off

# In vernemq service volumes:
- ./ssl/ca.crt:/opt/vernemq/etc/ssl/ca.crt:ro
- ./ssl/server.crt:/opt/vernemq/etc/ssl/server.crt:ro
- ./ssl/server.key:/opt/vernemq/etc/ssl/server.key:ro
```

Then restart the containers:
```bash
docker-compose up -d
```

## Testing TLS Connection

Using `mosquitto_pub`:
```bash
mosquitto_pub -h localhost -p 8883 \
    --cafile ssl/ca.crt \
    -t test/topic \
    -m "Hello TLS" \
    -u testuser -P testpass \
    --tls-version tlsv1.2
```

Using `mosquitto_sub`:
```bash
mosquitto_sub -h localhost -p 8883 \
    --cafile ssl/ca.crt \
    -t test/# \
    -u testuser -P testpass \
    --tls-version tlsv1.2
```

## Production Recommendations

For production deployments:

1. **Use a trusted CA** - Obtain certificates from Let's Encrypt, DigiCert, or another trusted CA
2. **Enable client certificate verification** - Set `REQUIRE_CERTIFICATE=on`
3. **Set minimum TLS version** - Use TLSv1.2 or higher
4. **Regularly rotate certificates** - Automate certificate renewal

### Let's Encrypt Example

```bash
# Install certbot
sudo apt-get install certbot

# Obtain certificate
sudo certbot certonly --standalone -d mqtt.yourdomain.com

# Copy certificates
sudo cp /etc/letsencrypt/live/mqtt.yourdomain.com/fullchain.pem ssl/server.crt
sudo cp /etc/letsencrypt/live/mqtt.yourdomain.com/privkey.pem ssl/server.key
sudo cp /etc/letsencrypt/live/mqtt.yourdomain.com/chain.pem ssl/ca.crt
```

## Security Notes

- ⚠️ **Never commit private keys to version control**
- The `.gitignore` should exclude `*.key` files
- Store production keys in a secrets manager
- Set proper file permissions: `chmod 600 *.key`
