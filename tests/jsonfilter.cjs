// Local-only stand-in for OpenWrt jsonfilter; production never invokes Node.
const fs = require('node:fs');
try {
    const args = process.argv.slice(2);
    const index = args.indexOf('-e');
    const path = args[index + 1];
    let object = JSON.parse(fs.readFileSync(0, 'utf8'));
    const keys = path.slice(1).replace(/\["([^"\]]+)"\]/g, '.$1')
        .replace(/\[(\d+)\]/g, '.$1').split('.').filter(Boolean);
    for (const key of keys) object = object?.[key];
    if (object == null || typeof object === 'object') process.exit(1);
    process.stdout.write(String(object) + '\n');
} catch { process.exit(1); }
