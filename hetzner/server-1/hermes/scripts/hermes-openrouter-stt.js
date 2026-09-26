// Hermes STT provider — transcribe audio with a multimodal model on OpenRouter.
//
//   openrouter-stt.js <input-audio> <output-dir>
//
// Contract of HERMES_LOCAL_STT_COMMAND: the templated command is run through
// shlex.split (no shell) and must leave a .txt transcript in <output-dir>.
// ZDR is enforced account-level; provider.zdr is also requested per call.
// Falls back to a local whisper-cli when OpenRouter is unreachable.
//
// Env overrides: OR_STT_MODEL (default google/gemini-3.5-flash-lite),
// OR_STT_TONE=0 (plain transcript, no delivery tags), OR_STT_FALLBACK=0,
// OR_STT_ENV_FILE (default /var/lib/hermes/.hermes/.env), OR_STT_WHISPER_MODEL.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const [input, outdir] = process.argv.slice(2);
const MODEL = process.env.OR_STT_MODEL || 'google/gemini-3.5-flash-lite';
const TONE = (process.env.OR_STT_TONE ?? '1') !== '0';
const FALLBACK = (process.env.OR_STT_FALLBACK ?? '1') !== '0';
const ENV_FILE = process.env.OR_STT_ENV_FILE || '/var/lib/hermes/.hermes/.env';
const WHISPER_BIN = process.env.OR_STT_WHISPER_BIN || 'whisper-cli';
// Path assembled at runtime: keeps static readers (including Hermes' own
// command-lifecycle scanner) from walking a 400 MB model file.
const WHISPER_MODEL =
  process.env.OR_STT_WHISPER_MODEL ||
  ['/var/lib/hermes/.hermes/models', 'ggml-small.bin'].join('/');
const TIMEOUT_MS = Number(process.env.OR_STT_TIMEOUT || 180) * 1000;

const log = (m) => process.stderr.write(`openrouter-stt: ${m}\n`);

if (!input || !outdir) {
  log('usage: openrouter-stt.js <input-audio> <output-dir>');
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

// 16 kHz mono keeps the upload and the audio-token bill down. ffmpeg is on the
// gateway PATH; without it the raw input is used as-is.
function prepare(audio) {
  const target = path.join(outdir, 'prep.wav');
  const r = spawnSync(
    'ffmpeg',
    ['-y', '-loglevel', 'error', '-i', audio, '-ar', '16000', '-ac', '1', target],
    { encoding: 'utf8' },
  );
  if (r.status === 0 && fs.existsSync(target)) return target;
  return audio;
}

function localWhisper() {
  log(`falling back to local ${WHISPER_BIN}`);
  const r = spawnSync(
    WHISPER_BIN,
    ['--model', WHISPER_MODEL, '--file', input, '--language', 'auto',
     '--output-txt', '--output-file', path.join(outdir, 'transcript'), '--no-prints'],
    { encoding: 'utf8' },
  );
  const txt = path.join(outdir, 'transcript.txt');
  if (r.status === 0 && fs.existsSync(txt) && fs.statSync(txt).size > 0) return true;
  if (r.error) log(`local fallback unavailable: ${r.error.message}`);
  return false;
}

const PROMPT_TONE =
  'Transcribe this audio verbatim, in the language actually spoken. Do not translate, ' +
  'summarise, censor or add commentary. Mark the delivery: when a sentence is not plainly ' +
  'neutral, START that sentence with one short bracketed tag describing the tone, e.g. ' +
  '[sarcastic], [joking], [teasing], [serious], [annoyed], [hesitant], [excited], [mocking], ' +
  '[tired], [amused]. No tag means neutral delivery. Write straight prose (no line breaks per ' +
  'sentence), keep fillers like "uh" only when they carry hesitation, and output nothing but ' +
  'the annotated transcript.';
const PROMPT_PLAIN =
  'Transcribe this audio verbatim, in the language actually spoken. Do not translate, ' +
  'summarise, censor or add commentary. Output only the transcript.';

async function main() {
  const key = apiKey();
  if (!key) {
    log(`no OPENROUTER_API_KEY (env or ${ENV_FILE})`);
    if (FALLBACK && localWhisper()) return;
    process.exit(1);
  }

  const audio = prepare(input);
  const body = {
    model: MODEL,
    provider: { zdr: true, data_collection: 'deny' },
    max_tokens: 2048,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: TONE ? PROMPT_TONE : PROMPT_PLAIN },
          {
            type: 'input_audio',
            input_audio: { data: fs.readFileSync(audio).toString('base64'), format: 'wav' },
          },
        ],
      },
    ],
  };

  const started = Date.now();
  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://hermes.lab.alper-celik.dev',
        'X-Title': 'hermes-gateway-stt',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const json = await res.json();
    const text = json?.choices?.[0]?.message?.content?.trim();
    if (!res.ok || !text) {
      log(`no transcript from ${MODEL} (HTTP ${res.status}): ${JSON.stringify(json).slice(0, 300)}`);
      if (FALLBACK && localWhisper()) return;
      process.exit(1);
    }
    fs.writeFileSync(path.join(outdir, 'transcript.txt'), `${text}\n`);
    log(
      `transcribed ${path.basename(input)} via ${MODEL} ` +
        `(upstream=${json.provider ?? '?'}, ${text.length} chars, ${((Date.now() - started) / 1000).toFixed(1)}s)`,
    );
  } catch (e) {
    log(`request failed: ${e.message}`);
    if (FALLBACK && localWhisper()) return;
    process.exit(1);
  }
}

main();
