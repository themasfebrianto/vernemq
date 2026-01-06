/**
 * VerneMQ Load Testing Worker - RTU Power Meter Simulator
 * 
 * Simulates multiple RTU devices publishing power meter data to VerneMQ
 * 
 * Usage: node worker.js [options]
 * 
 * Options:
 *   --host       MQTT broker host (default: localhost)
 *   --port       MQTT broker port (default: 1883)
 *   --clients    Number of RTU clients to simulate (default: 10)
 *   --interval   Message interval in ms (default: 1000)
 *   --duration   Test duration in seconds (default: 60)
 *   --qos        QoS level 0, 1, or 2 (default: 1)
 */

const mqtt = require('mqtt');

// Parse command line arguments
const args = process.argv.slice(2);
const getArg = (name, defaultValue) => {
    const index = args.indexOf(`--${name}`);
    if (index !== -1 && args[index + 1]) {
        return args[index + 1];
    }
    return defaultValue;
};

// Configuration
const config = {
    host: getArg('host', 'localhost'),
    port: parseInt(getArg('port', '1883')),
    clients: parseInt(getArg('clients', '10')),
    messageInterval: parseInt(getArg('interval', '1000')),
    duration: parseInt(getArg('duration', '60')),
    qos: parseInt(getArg('qos', '1')),
};

// Generate RTU IDs dynamically based on client count
function generateRtuIds(count) {
    const ids = [];
    const today = new Date();
    const prefix = `${today.getFullYear().toString().slice(-2)}${String(today.getMonth() + 1).padStart(2, '0')}${String(today.getDate()).padStart(2, '0')}`;

    for (let i = 1; i <= count; i++) {
        ids.push(`${prefix}${String(i).padStart(6, '0')}`);
    }
    return ids;
}

const rtuIds = generateRtuIds(config.clients);

// Test user credentials
const credentials = { username: 'testuser', password: 'testpass' };

// Stats tracking
const stats = {
    connected: 0,
    messagesPublished: 0,
    messagesReceived: 0,
    errors: 0,
    startTime: null,
};

// Active clients
const clients = [];

// Helper: random float in range
const rand = (min, max, decimals = 2) => {
    return parseFloat((min + Math.random() * (max - min)).toFixed(decimals));
};

// Generate RTU power meter data
function generateRtuData(rtuId) {
    // Base voltage ~220V with small variation
    const voltageBase = 220;
    const voltageL1 = rand(voltageBase - 5, voltageBase + 5);
    const voltageL2 = rand(voltageBase - 5, voltageBase + 5);
    const voltageL3 = rand(voltageBase - 5, voltageBase + 5);

    // Current ~10-50A
    const currentL1 = rand(10, 50);
    const currentL2 = rand(10, 50);
    const currentL3 = rand(10, 50);
    const currentN = rand(0, 5);
    const currentTotal = parseFloat((currentL1 + currentL2 + currentL3).toFixed(2));

    // Power Factor ~0.85-0.99
    const powerFactorL1 = rand(0.85, 0.99);
    const powerFactorL2 = rand(0.85, 0.99);
    const powerFactorL3 = rand(0.85, 0.99);

    // Active Power (kW)
    const activePowerL1 = rand(1, 10);
    const activePowerL2 = rand(1, 10);
    const activePowerL3 = rand(1, 10);

    // Reactive Power (kVAR)
    const reactivePowerL1 = rand(0.5, 3);
    const reactivePowerL2 = rand(0.5, 3);
    const reactivePowerL3 = rand(0.5, 3);

    // Apparent Power (kVA)
    const apparentPowerL1 = rand(1, 12);
    const apparentPowerL2 = rand(1, 12);
    const apparentPowerL3 = rand(1, 12);
    const apparentPowerTotal = parseFloat((apparentPowerL1 + apparentPowerL2 + apparentPowerL3).toFixed(2));

    // Harmonic currents
    const currentL1F1 = rand(8, 45);
    const currentL2F1 = rand(8, 45);
    const currentL3F1 = rand(8, 45);
    const currentNF1 = rand(0, 3);
    const currentL1F2 = rand(0.1, 2);
    const currentL2F2 = rand(0.1, 2);
    const currentL3F2 = rand(0.1, 2);
    const currentNF2 = rand(0, 0.5);

    // Temperature (Celsius)
    const temperature1 = rand(25, 45);
    const temperature2 = rand(25, 45);

    return {
        DateTime: new Date().toISOString(),
        RtuId: rtuId,
        VoltageL1: voltageL1,
        VoltageL2: voltageL2,
        VoltageL3: voltageL3,
        CurrentL1: currentL1,
        CurrentL2: currentL2,
        CurrentL3: currentL3,
        CurrentN: currentN,
        CurrentTotal: currentTotal,
        PowerFactorL1: powerFactorL1,
        PowerFactorL2: powerFactorL2,
        PowerFactorL3: powerFactorL3,
        ActivePowerL1: activePowerL1,
        ActivePowerL2: activePowerL2,
        ActivePowerL3: activePowerL3,
        ReactivePowerL1: reactivePowerL1,
        ReactivePowerL2: reactivePowerL2,
        ReactivePowerL3: reactivePowerL3,
        ApparentPowerL1: apparentPowerL1,
        ApparentPowerL2: apparentPowerL2,
        ApparentPowerL3: apparentPowerL3,
        ApparentPowerTotal: apparentPowerTotal,
        CurrentL1F1: currentL1F1,
        CurrentL2F1: currentL2F1,
        CurrentL3F1: currentL3F1,
        CurrentNF1: currentNF1,
        CurrentL1F2: currentL1F2,
        CurrentL2F2: currentL2F2,
        CurrentL3F2: currentL3F2,
        CurrentNF2: currentNF2,
        Temperature1: temperature1,
        Temperature2: temperature2,
    };
}

// Create a client for each RTU
function createRtuClient(rtuId, index) {
    const clientId = `rtu-${rtuId}`;

    const client = mqtt.connect(`mqtt://${config.host}:${config.port}`, {
        clientId,
        username: credentials.username,
        password: credentials.password,
        clean: true,
        reconnectPeriod: 5000,
    });

    let publishInterval = null;

    client.on('connect', () => {
        stats.connected++;

        // Subscribe to a topic to also receive messages
        client.subscribe(`rtu/+/data`, { qos: config.qos });

        // Publish data at interval
        publishInterval = setInterval(() => {
            const data = generateRtuData(rtuId);
            const topic = `rtu/${rtuId}/data`;

            client.publish(topic, JSON.stringify(data), { qos: config.qos }, (err) => {
                if (err) {
                    stats.errors++;
                } else {
                    stats.messagesPublished++;
                }
            });
        }, config.messageInterval);
    });

    client.on('message', () => {
        stats.messagesReceived++;
    });

    client.on('error', (error) => {
        stats.errors++;
        console.error(`❌ RTU ${rtuId} error:`, error.message);
    });

    client.on('close', () => {
        if (publishInterval) clearInterval(publishInterval);
    });

    return { client, publishInterval, rtuId };
}

// Print stats
function printStats() {
    const elapsed = ((Date.now() - stats.startTime) / 1000).toFixed(0);
    const remaining = Math.max(0, config.duration - elapsed);
    const pubRate = stats.messagesPublished / Math.max(1, elapsed);
    const recvRate = stats.messagesReceived / Math.max(1, elapsed);

    console.clear();
    console.log('');
    console.log('╔══════════════════════════════════════════════════════════════╗');
    console.log('║         VerneMQ Load Testing Worker                          ║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log(`║  Host:        ${config.host}:${config.port}`.padEnd(65) + '║');
    console.log(`║  Clients:     ${config.clients}`.padEnd(65) + '║');
    console.log(`║  Interval:    ${config.messageInterval}ms`.padEnd(65) + '║');
    console.log(`║  Duration:    ${config.duration}s`.padEnd(65) + '║');
    console.log(`║  QoS:         ${config.qos}`.padEnd(65) + '║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log(`║  ⏱️  Elapsed:     ${elapsed}s / ${config.duration}s`.padEnd(63) + '║');
    console.log(`║  ⏳ Remaining:   ${remaining}s`.padEnd(63) + '║');
    console.log(`║  🔗 Connected:   ${stats.connected} / ${config.clients}`.padEnd(63) + '║');
    console.log(`║  📤 Published:   ${stats.messagesPublished}`.padEnd(63) + '║');
    console.log(`║  📥 Received:    ${stats.messagesReceived}`.padEnd(63) + '║');
    console.log(`║  ⚡ Pub Rate:    ${pubRate.toFixed(1)} msg/sec`.padEnd(63) + '║');
    console.log(`║  📊 Recv Rate:   ${recvRate.toFixed(1)} msg/sec`.padEnd(63) + '║');
    console.log(`║  ❌ Errors:      ${stats.errors}`.padEnd(63) + '║');
    console.log('╚══════════════════════════════════════════════════════════════╝');
    console.log('');
    console.log('Press Ctrl+C to stop');
}

// Main function
async function main() {
    console.log('');
    console.log('╔══════════════════════════════════════════════════════════════╗');
    console.log('║         VerneMQ Load Testing Worker                          ║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log(`║  Starting ${config.clients} clients...`.padEnd(65) + '║');
    console.log(`║  Interval: ${config.messageInterval}ms, Duration: ${config.duration}s, QoS: ${config.qos}`.padEnd(65) + '║');
    console.log('╚══════════════════════════════════════════════════════════════╝');
    console.log('');

    stats.startTime = Date.now();

    // Create clients with staggered connection (slower stagger to avoid auth timeouts)
    const connectionDelay = Math.max(200, 10000 / config.clients); // At least 200ms between connections

    for (let i = 0; i < rtuIds.length; i++) {
        clients.push(createRtuClient(rtuIds[i], i));
        if (i < rtuIds.length - 1) {
            await new Promise(resolve => setTimeout(resolve, connectionDelay));
        }
    }

    // Print stats every second
    const statsInterval = setInterval(printStats, 1000);

    // Stop after duration
    setTimeout(() => {
        console.log('');
        console.log('⏹️  Test duration reached. Stopping...');

        clearInterval(statsInterval);

        clients.forEach(({ client, publishInterval }) => {
            if (publishInterval) clearInterval(publishInterval);
            client.end(true);
        });

        setTimeout(() => {
            const finalPubRate = stats.messagesPublished / config.duration;
            const finalRecvRate = stats.messagesReceived / config.duration;

            console.log('');
            console.log('════════════════════════════════════════════════════════════════');
            console.log('                        FINAL RESULTS                           ');
            console.log('════════════════════════════════════════════════════════════════');
            console.log(`  Duration:          ${config.duration} seconds`);
            console.log(`  Clients:           ${config.clients}`);
            console.log(`  Total Published:   ${stats.messagesPublished} messages`);
            console.log(`  Total Received:    ${stats.messagesReceived} messages`);
            console.log(`  Avg Pub Rate:      ${finalPubRate.toFixed(1)} msg/sec`);
            console.log(`  Avg Recv Rate:     ${finalRecvRate.toFixed(1)} msg/sec`);
            console.log(`  Errors:            ${stats.errors}`);
            console.log('════════════════════════════════════════════════════════════════');
            process.exit(0);
        }, 1000);
    }, config.duration * 1000);

    // Handle Ctrl+C
    process.on('SIGINT', () => {
        console.log('');
        console.log('🛑 Interrupted! Cleaning up...');
        clearInterval(statsInterval);
        clients.forEach(({ client, publishInterval }) => {
            if (publishInterval) clearInterval(publishInterval);
            client.end(true);
        });
        process.exit(0);
    });
}

main().catch(console.error);
