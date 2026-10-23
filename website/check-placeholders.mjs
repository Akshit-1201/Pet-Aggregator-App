// Refuses a hosting deploy while any [[PLACEHOLDER]] is left in the site.
// Runs automatically before `firebase deploy --only hosting` (firebase.json
// predeploy), so a half-filled site can never reach Razorpay's reviewers or
// the app stores. Fill the values listed in website/README.md first.
import {readdirSync, readFileSync, statSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "public");
const token = /\[\[[A-Z_]+\]\]/g;
const found = new Map();

function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.(html|css|js|json|txt|xml)$/.test(name)) {
      for (const t of readFileSync(p, "utf8").match(token) ?? []) {
        const rel = path.relative(root, p);
        found.set(t, new Set([...(found.get(t) ?? []), rel]));
      }
    }
  }
}

walk(root);
if (found.size) {
  console.error("✗ The website still has placeholders — fill them before deploying:");
  for (const [t, files] of found) console.error(`  ${t}  in ${[...files].join(", ")}`);
  console.error("See website/README.md.");
  process.exit(1);
}
console.log("✓ No placeholders left in website/public.");
