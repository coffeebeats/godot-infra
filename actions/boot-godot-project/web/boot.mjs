// Boots a Godot project exported for the Web and reports as the game would.
//
//   node boot.mjs <index.html> [engine argument...]
//
// The export's directory is served over loopback with the cross-origin
// isolation headers a threaded build needs, and the shell opens in the
// runner's Chrome. Every console message is written to stdout, so the output
// reads like the game's own log, and the process exits with the engine's exit
// code. Extra arguments are appended to the engine arguments baked into the
// shell, which is how '--quit-after' reaches the game.

import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { basename, dirname, extname, join, normalize, resolve, sep } from 'node:path';

import { chromium } from 'playwright-core';

const [, , shellPath, ...engineArgs] = process.argv;

if (!shellPath) {
	console.error('Usage: boot.mjs <index.html> [engine argument...]');
	process.exit(2);
}

// DEADLINE_MS bounds a game that never exits, which a shell that could not
// start the engine never does either.
const DEADLINE_MS = 5 * 60 * 1000;

// EXIT_BINDING names the page function the patched shell calls on exit.
const EXIT_BINDING = '__godotBootExit';

// HEADERS are what the editor's own run server sends: a threaded build needs
// cross-origin isolation before the browser grants it a SharedArrayBuffer.
const HEADERS = {
	'Cross-Origin-Opener-Policy': 'same-origin',
	'Cross-Origin-Embedder-Policy': 'require-corp',
	'Cache-Control': 'no-store',
};

// TYPES covers the files an export contains; 'application/wasm' lets the
// browser compile the module as it streams in.
const TYPES = {
	'.html': 'text/html',
	'.js': 'text/javascript',
	'.json': 'application/json',
	'.png': 'image/png',
	'.wasm': 'application/wasm',
};

// CONFIG matches the engine configuration the export writes into its shell,
// which is one compact JSON object, so '};' cannot occur before its end.
const CONFIG = /GODOT_CONFIG\s*=\s*(\{.*?\});/s;

const shell = resolve(shellPath);
const root = dirname(shell);

// patchShell appends the harness' arguments to the configuration's and adds
// the exit callback the shell leaves unset, which is the only way out of the
// page once the engine has quit.
function patchShell(html) {
	const match = CONFIG.exec(html);

	if (!match) {
		throw new Error(`Cannot find the engine configuration in '${basename(shell)}'.`);
	}

	const config = JSON.parse(match[1]);
	config.args = [...(config.args ?? []), ...engineArgs];

	const patched = `GODOT_CONFIG = Object.assign(${JSON.stringify(config)}, { onExit: (code) => window.${EXIT_BINDING}(code) });`;

	return html.replace(CONFIG, () => patched);
}

const server = createServer(async (request, response) => {
	const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
	const file = join(root, normalize(pathname));

	if (!file.startsWith(root + sep)) {
		response.writeHead(403, HEADERS).end();
		return;
	}

	let body;

	try {
		body = await readFile(file);
	} catch {
		response.writeHead(404, HEADERS).end();
		return;
	}

	if (file === shell) {
		body = patchShell(body.toString());
	}

	response.writeHead(200, { ...HEADERS, 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' });
	response.end(body);
});

await new Promise((listening) => server.listen(0, '127.0.0.1', listening));

const { port } = server.address();

const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage();

let finish;
const finished = new Promise((resolve) => {
	finish = resolve;
});

page.on('console', (message) => console.log(message.text()));

// An uncaught exception or a dead tab is reported in the engine's own words,
// so the same failure patterns apply.
//
// NOTE: The engine's loader never rejects a '.wasm' it cannot fetch or
// instantiate, so the exception is the only sign and nothing calls 'onExit'.
page.on('pageerror', (error) => {
	console.log(`ERROR: Uncaught exception: ${error.message}`);
	finish(1);
});
page.on('crash', () => {
	console.log('ERROR: The browser tab crashed.');
	finish(1);
});

// A browser that dies outright closes the page without crashing it. The
// harness closes the page itself once the game has exited, so this handler
// comes off before then.
const closed = () => {
	console.log('ERROR: The browser closed before the game exited.');
	finish(1);
};
page.on('close', closed);

await page.exposeFunction(EXIT_BINDING, finish);

const deadline = setTimeout(() => {
	console.log(`ERROR: The game did not exit within ${DEADLINE_MS / 1000} seconds.`);
	finish(124);
}, DEADLINE_MS);

page.goto(`http://127.0.0.1:${port}/${basename(shell)}`).catch((error) => {
	console.log(`ERROR: ${error.message}`);
	finish(1);
});

// A missing feature raises no exception; the shell logs the reason, shows its
// notice and never calls 'onExit'. The wait polls the page a few times a
// second and is dropped when the page closes; a custom shell without the
// notice falls back to the deadline.
page.waitForSelector('#status-notice', { state: 'visible', timeout: 0 })
	.then(() => {
		console.log('ERROR: The shell reported a failure before the game started.');
		finish(1);
	})
	.catch(() => {});

const code = await finished;

clearTimeout(deadline);
page.off('close', closed);
await browser.close();
server.close();

process.exit(code);
