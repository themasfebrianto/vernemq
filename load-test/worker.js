/**
 * VerneMQ Load Testing Worker - RTU Power Meter Simulator
 * 
 * Simulates 5 RTU devices publishing power meter data to VerneMQ
 * 
 * Usage: node worker.js [options]
 * 
 * Options:
 *   --host       MQTT broker host (default: localhost)
 *   --port       MQTT broker port (default: 1883)
 *   --interval   Message interval in ms (default: 5000)
 *   --duration   Test duration in seconds (default: 300)
 */

const mqtt = require('mqtt');

// Parse command line arguments
const args = process.argv.slice(2);
const getArg = (name, defaultValue) => {
    const index = args.indexOf(`--${name}`);
    return index !== -1 ? args[index + 1] : defaultValue;
};

// Configuration
const config = {
    host: getArg('host', 'localhost'),
    port: parseInt(getArg('port', '1883')),
    messageInterval: parseInt(getArg('interval', '5000')),
    duration: parseInt(getArg('duration', '300')),
};

// RTU IDs
const rtuIds = [
    '250901000001',
    '250901000002',
    '250901000003',
    '250901000004',
    '250901000005',
];

// Test user credentials
const credentials = { username: 'testuser', password: 'testpass' };

// Stats tracking
const stats = {
    connected: 0,
    messagesPublished: 0,
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

    // Active Power (kW) = V * I * PF / 1000
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

    // Harmonic currents F1 (fundamental)
    const currentL1F1 = rand(8, 45);
    const currentL2F1 = rand(8, 45);
    const currentL3F1 = rand(8, 45);
    const currentNF1 = rand(0, 3);

    // Harmonic currents F2 (2nd harmonic, usually smaller)
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
        console.log(`✅ RTU ${rtuId} connected`);

        // Publish data at interval
        publishInterval = setInterval(() => {
            const data = generateRtuData(rtuId);
            const topic = `rtu/${rtuId}/data`;

            client.publish(topic, JSON.stringify(data), { qos: 1 }, (err) => {
                if (err) {
                    stats.errors++;
                } else {
                    stats.messagesPublished++;
                }
            });
        }, config.messageInterval);
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

    console.clear();
    console.log('');
    console.log('╔══════════════════════════════════════════════════════════════╗');
    console.log('║        RTU Power Meter Simulator - VerneMQ Load Test         ║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log(`║  Broker:      ${config.host}:${config.port}`.padEnd(65) + '║');
    console.log(`║  RTU Count:   ${rtuIds.length}`.padEnd(65) + '║');
    console.log(`║  Interval:    ${config.messageInterval}ms`.padEnd(65) + '║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log(`║  ⏱️  Elapsed:     ${elapsed}s / ${config.duration}s`.padEnd(63) + '║');
    console.log(`║  ⏳ Remaining:   ${remaining}s`.padEnd(63) + '║');
    console.log(`║  🔗 Connected:   ${stats.connected} / ${rtuIds.length}`.padEnd(63) + '║');
    console.log(`║  📤 Published:   ${stats.messagesPublished} messages`.padEnd(63) + '║');
    console.log(`║  ❌ Errors:      ${stats.errors}`.padEnd(63) + '║');
    console.log('╠══════════════════════════════════════════════════════════════╣');
    console.log('║  RTU IDs:                                                    ║');
    rtuIds.forEach(id => {
        console.log(`║    • ${id}`.padEnd(65) + '║');
    });
    console.log('╚══════════════════════════════════════════════════════════════╝');
    console.log('');
    console.log('Press Ctrl+C to stop');
}

// Show sample data
function showSampleData() {
    const sample = generateRtuData(rtuIds[0]);
    console.log('');
    console.log('📊 Sample RTU Data:');
    console.log(JSON.stringify(sample, null, 2));
    console.log('');
}

// Main function
async function main() {
    console.log('');
    console.log('🚀 Starting RTU Power Meter Simulator...');
    console.log(`   Simulating ${rtuIds.length} RTU devices...`);

    showSampleData();

    stats.startTime = Date.now();

    // Create clients for each RTU
    for (let i = 0; i < rtuIds.length; i++) {
        clients.push(createRtuClient(rtuIds[i], i));
        await new Promise(resolve => setTimeout(resolve, 200));
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
            console.log('');
            console.log('════════════════════════════════════════════════════════════════');
            console.log('                        FINAL RESULTS                           ');
            console.log('════════════════════════════════════════════════════════════════');
            console.log(`  Duration:          ${config.duration} seconds`);
            console.log(`  RTU Devices:       ${rtuIds.length}`);
            console.log(`  Total Published:   ${stats.messagesPublished} messages`);
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
