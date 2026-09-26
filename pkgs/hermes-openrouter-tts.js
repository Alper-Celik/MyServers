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
// Kokoro answers with raw PCM (24 kHz, mono, 16-bit LE); this script wraps that
// in a RIFF/WAVE container itself, so node alone is enough. Hermes turns the WAV
// into Opus for voice-bubble platforms (Telegram) via its own ffmpeg.
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
// request), OR_TTS_TIMEOUT (seconds), OR_TTS_ENV_FILE, OR_TTS_FALLBACK=0 to
// disable the offline fallback, OR_TTS_FALLBACK_CMD (default espeak-ng, with
// {input_path} / {output_path} placeholders).

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const MODEL = process.env.OR_TTS_MODEL || 'hexgrad/kokoro-82m';
const VOICE = process.argv[4] || process.env.OR_TTS_VOICE || 'af_heart';
const PROVIDER = process.env.OR_TTS_PROVIDER || 'DeepInfra';
const ENV_FILE = process.env.OR_TTS_ENV_FILE || '/var/lib/hermes/.hermes/.env';
const TIMEOUT_MS = Number(process.env.OR_TTS_TIMEOUT || 120) * 1000;
const MAX_CHARS = Number(process.env.OR_TTS_MAX_CHARS || 600);
const FALLBACK = (process.env.OR_TTS_FALLBACK ?? '1') !== '0';
const FALLBACK_CMD =
  process.env.OR_TTS_FALLBACK_CMD || 'espeak-ng -w {output_path} -f {input_path}';
const SAMPLE_RATE = 24000;
const CHANNELS = 1;
const BITS = 16;

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

// Last resort so an OpenRouter outage degrades to robotic speech, not silence.
// espeak-ng is a couple of MB, unlike piper-tts whose aarch64 closure drags in
// torch/librosa/numba (torch alone is ~2 GB) for one CPU voice.
function localFallback() {
  if (!FALLBACK) return false;
  log(`falling back to local: ${FALLBACK_CMD}`);
  const quote = (v) => `'${String(v).replace(/'/g, `'\\''`)}'`;
  const command = FALLBACK_CMD.replace(/{input_path}/g, quote(textFile)).replace(
    /{output_path}/g,
    quote(outputPath),
  );
  const r = spawnSync(command, { shell: true, encoding: 'utf8' });
  if (r.status === 0 && fs.existsSync(outputPath) && fs.statSync(outputPath).size > 0) return true;
  if (r.error) log(`local fallback unavailable: ${r.error.message}`);
  else if (r.stderr) log(`local fallback failed: ${r.stderr.trim().slice(0, 200)}`);
  return false;
}

function wav(pcm) {
  const header = Buffer.alloc(44);
  const byteRate = (SAMPLE_RATE * CHANNELS * BITS) / 8;
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(CHANNELS, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE((CHANNELS * BITS) / 8, 32); // block align
  header.writeUInt16LE(BITS, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
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
      if (localFallback()) return;
      process.exit(1);
    }
  }
  const pcm = Buffer.concat(pcmParts);
  fs.writeFileSync(outputPath, wav(pcm));
  log(
    `${parts.length} chunk(s), ${text.trim().length} chars, ` +
      `${(pcm.length / 2 / SAMPLE_RATE).toFixed(2)}s audio, ` +
      `${((Date.now() - started) / 1000).toFixed(1)}s via ${MODEL}/${VOICE}/${PROVIDER}`,
  );
}

main().catch((e) => {
  log(`failed: ${e.message}`);
  process.exit(1);
});
