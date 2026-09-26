// Hermes TTS provider — synthesise voice replies with Kokoro-82M on OpenRouter.
//
//   hermes-openrouter-tts <text-file> <output-path> [voice]
//
// The shebang is added by the Nix module (pkgs.writeTextFile), so this source
// file must NOT carry one: a second hashbang line is a SyntaxError for node.
//
// Contract of tts.providers.<name> {type: command}: the templated command is run
// through shlex.split (no shell — this script IS the shell), placeholders are
// shell-quoted for their position, and the audio must land at <output-path>.
// Kokoro answers with raw PCM (24 kHz, mono, 16-bit LE); the ffmpeg already on
// the gateway unit's PATH encodes that into Ogg/Opus at <output-path> — the
// modern codec voice-bubble platforms need anyway, at a fraction of the WAV
// size. output_format = ogg + voice_compatible = true makes Hermes deliver that
// file as a native voice bubble without re-encoding (it only transcodes when a
// command provider's output is not already .ogg).
//
// Why this route and not the chat models: OpenRouter's audio-*output* chat
// models (openai/gpt-audio*, google/lyria-3-*) are not ZDR-eligible and the
// account-level ZDR guardrail rejects them ("0 endpoints … ZDR violation"), and
// a per-request provider.zdr cannot loosen that. The dedicated speech endpoint
// (POST /api/v1/audio/speech) serves hexgrad/kokoro-82m from DeepInfra and
// Together, which both pass that guardrail: ~18 s of speech in ~1.4 s.
//
// Env overrides: OR_TTS_MODEL (default hexgrad/kokoro-82m), OR_TTS_VOICE
// (default af_heart; af_bella / am_michael / alloy also accepted),
// OR_TTS_PROVIDER (default DeepInfra), OR_TTS_MAX_CHARS (default 600 per
// request), OR_TTS_TIMEOUT (seconds), OR_TTS_BITRATE (default 32k),
// OR_TTS_FFMPEG (default ffmpeg, resolved from PATH), OR_TTS_ENV_FILE.
//
// Deliberately NO local fallback: if OpenRouter or the encode fails, the script
// exits non-zero and Hermes reports the error. The VPS runs other services and
// must not spend CPU synthesising speech offline.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const MODEL = process.env.OR_TTS_MODEL || 'hexgrad/kokoro-82m';
const VOICE = process.argv[4] || process.env.OR_TTS_VOICE || 'af_heart';
const PROVIDER = process.env.OR_TTS_PROVIDER || 'DeepInfra';
const ENV_FILE = process.env.OR_TTS_ENV_FILE || '/var/lib/hermes/.hermes/.env';
const TIMEOUT_MS = Number(process.env.OR_TTS_TIMEOUT || 120) * 1000;
const MAX_CHARS = Number(process.env.OR_TTS_MAX_CHARS || 600);
const FFMPEG = process.env.OR_TTS_FFMPEG || 'ffmpeg';
const BITRATE = process.env.OR_TTS_BITRATE || '32k';
const SAMPLE_RATE = 24000;
const CHANNELS = 1;

const log = (m) => process.stderr.write(`openrouter-tts: ${m}\n`);

const [textFile, outputPath] = process.argv.slice(2);
if (!textFile || !outputPath) {
  log('usage: hermes-openrouter-tts <text-file> <output-path> [voice]');
  process.exit(2);
}

function apiKey() {
  if (process.env.OPENROUTER_API_KEY) return process.env.OPENROUTER_API_KEY;
  try {
    const line = fs
      .readFileSync(ENV_FILE, 'utf8')
      .split('\n')
      .find((l) => l.startsWith('OPENROUTER_API_KEY='));
    return line ? line.slice('OPENROUTER_API_KEY='.length).trim() : '';
  } catch {
    return '';
  }
}

// Split on sentence boundaries: Kokoro's context is small, so a long reply is
// synthesised in ordered chunks instead of being truncated.
function chunk(text) {
  const clean = text.replace(/\s+/g, ' ').trim();
  if (!clean) return [];
  if (clean.length <= MAX_CHARS) return [clean];
  const sentences = clean.match(/[^.!?]+[.!?]*\s*/g) || [clean];
  const out = [];
  let cur = '';
  for (const s of sentences) {
    if ((cur + s).length > MAX_CHARS && cur) {
      out.push(cur.trim());
      cur = '';
    }
    if (s.length > MAX_CHARS) {
      for (let i = 0; i < s.length; i += MAX_CHARS) out.push(s.slice(i, i + MAX_CHARS).trim());
      continue;
    }
    cur += s;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

async function synth(text) {
  const key = apiKey();
  if (!key) throw new Error(`no OPENROUTER_API_KEY (env or ${ENV_FILE})`);
  const res = await fetch('https://openrouter.ai/api/v1/audio/speech', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://hermes.lab.alper-celik.dev',
      'X-Title': 'hermes-gateway-tts',
    },
    body: JSON.stringify({
      model: MODEL,
      input: text,
      voice: VOICE,
      response_format: 'pcm',
      provider: { order: [PROVIDER], zdr: true, data_collection: 'deny' },
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return Buffer.from(await res.arrayBuffer());
}

// Kokoro's concatenated raw PCM -> Ogg/Opus in one ffmpeg pass, written
// straight to the output file. libopus VBR at speech bitrates is what Telegram
// voice notes use anyway, so the result needs no further processing.
function encodeOpus(pcm) {
  const r = spawnSync(
    FFMPEG,
    [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 's16le', '-ar', String(SAMPLE_RATE), '-ac', String(CHANNELS),
      '-i', 'pipe:0',
      '-c:a', 'libopus', '-b:a', BITRATE, '-vbr', 'on', '-compression_level', '10',
      '-f', 'ogg', outputPath,
    ],
    { input: pcm, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 },
  );
  if (r.error) throw new Error(`cannot run ${FFMPEG}: ${r.error.message}`);
  if (r.status !== 0) {
    throw new Error(`${FFMPEG} exited ${r.status}: ${String(r.stderr || '').trim().slice(0, 300)}`);
  }
}

async function main() {
  let text;
  try {
    text = fs.readFileSync(textFile, 'utf8');
  } catch (e) {
    log(`cannot read text file ${textFile}: ${e.message}`);
    process.exit(1);
  }
  const parts = chunk(text);
  if (!parts.length) {
    log('refusing to synthesise empty text');
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });

  const started = Date.now();
  const pcmParts = [];
  for (const [i, part] of parts.entries()) {
    try {
      pcmParts.push(await synth(part));
    } catch (e) {
      log(`chunk ${i + 1}/${parts.length} failed: ${e.message}`);
      process.exit(1); // no local fallback, on purpose — see the file header
    }
  }
  const pcm = Buffer.concat(pcmParts);
  try {
    encodeOpus(pcm);
  } catch (e) {
    log(`opus encode failed: ${e.message}`);
    process.exit(1);
  }
  const written = fs.statSync(outputPath).size;
  log(
    `${parts.length} chunk(s), ${text.trim().length} chars, ` +
      `${(pcm.length / 2 / SAMPLE_RATE).toFixed(2)}s audio, ` +
      `pcm ${(pcm.length / 1024).toFixed(0)}KiB -> opus ${(written / 1024).toFixed(0)}KiB, ` +
      `${((Date.now() - started) / 1000).toFixed(1)}s via ${MODEL}/${VOICE}/${PROVIDER}`,
  );
}

main().catch((e) => {
  log(`failed: ${e.message}`);
  process.exit(1);
});
