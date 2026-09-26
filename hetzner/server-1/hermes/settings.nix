{
  config,
  pkgs,
  hermesPorts,
  ...
}:

let
  # Voice-note transcription goes through a multimodal model on OpenRouter (ZDR
  # is enforced account-level and requested per call). The script itself is
  # ./scripts/hermes-openrouter-stt.js; the shebang is added here so the source
  # file stays plain JS (no `''${` escaping) and node comes from the store rather
  # than the unit PATH.
  sttScript = pkgs.writeTextFile {
    name = "hermes-openrouter-stt";
    executable = true;
    destination = "/bin/hermes-openrouter-stt";
    text = "#!${pkgs.nodejs}/bin/node\n" + builtins.readFile ./scripts/hermes-openrouter-stt.js;
  };

  # Voice replies (TTS) use the same shape: ./scripts/hermes-openrouter-tts.js
  # posts the reply text to OpenRouter's speech endpoint (Kokoro-82M, served by
  # DeepInfra/Together — those endpoints pass the account ZDR guardrail, unlike
  # the audio-*output* chat models), then encodes the raw PCM to Ogg/Opus with
  # the ffmpeg already on the unit PATH. Store shebang again, so node need not
  # be on the unit PATH.
  ttsScript = pkgs.writeTextFile {
    name = "hermes-openrouter-tts";
    executable = true;
    destination = "/bin/hermes-openrouter-tts";
    text = "#!${pkgs.nodejs}/bin/node\n" + builtins.readFile ./scripts/hermes-openrouter-tts.js;
  };

  # Offline fallback model for that script (whisper.cpp): small is the
  # speed/quality compromise that still fits the 300 s local-STT timeout on 4
  # cores. large-v3-turbo transcribes far better (and is what OpenRouter is
  # asked for) but runs ~10-15x realtime here.
  whisperModel = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
    hash = "sha256-G+OpsgY4Z7k35k4ux0gzZKeZF+FX+pjF2UtcH//qmHs=";
  };
in
{
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    # nix on PATH so the agent can run throwaway tools: nix shell/run/nix-shell
    # mcp-grafana: the Grafana MCP stdio server in mcp-servers.nix, as a
    #   nix-built binary — uvx cannot run it on this host (see the grafana MCP
    #   server comment)
    # github-mcp-server: the GitHub MCP stdio server there, likewise a nix-built
    #   Go binary (no interpreter)
    # gh: the GitHub CLI, still here alongside the MCP server — it reads the
    #   sops-rendered ~/.config/gh/hosts.yml from secrets.nix, and covers what
    #   the MCP server does not (raw `gh api`, `gh run watch`, ad-hoc `gh pr`
    #   output)
    extraPackages = with pkgs; [
      nix
      chromium
      git
      fd
      ripgrep
      uv
      gh
      mcp-grafana
      github-mcp-server
      # whisper-cli: OFFLINE fallback for the STT script below (node itself is
      # pinned by the script's store shebang). ffmpeg, needed to turn the
      # Telegram .ogg into 16 kHz wav, is already on the unit PATH from the module.
      whisper-cpp
    ];
    extraDependencyGroups = [
      "messaging"
      "exa"
    ];

    settings = {
      plugins.enabled = [
        "hermes-workbench"
      ];
      approvals.mode = "off";
      # Writes to agent-instruction files (AGENTS.md/CLAUDE.md/SOUL.md/
      # .cursorrules, project-local .hermes config) normally require human
      # approval even under yolo. The gate covers only the AGENT'S file-edit
      # tools: a plain shell write to the same file is not gated by it at all,
      # so it stops the careful path and nothing else — and on this host the
      # approval prompt is delivered to the dashboard/Telegram surface where a
      # timeout counts as DENY, which silently blocks legitimate policy edits
      # (e.g. adding the worktree rule to AGENTS.md). The real protection for
      # instruction files is the PR route: agent edits land as reviewed
      # Alper-Celik/* pull requests, never as direct workspace writes.
      security.protected_instruction_files = false;
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "@preset/hermes-agent";
        context_length = 900000;
      };
      api_server = {
        enabled = true;
        port = hermesPorts.api;
      };
      # GitHub /ac_agent trigger endpoint. GitHub POSTs comment events here and the
      # route's script decides whether the comment is a real /ac_agent request
      # (marker + allow-listed author) before anything runs. The adapter binds
      # LOOPBACK ONLY on purpose: caddy is the sole public surface, and only for
      # the single /webhooks/github-ac-agent path (see the virtualHosts block in
      # ./web.nix). Per-route HMAC secrets live in
      # $HERMES_HOME/webhook_subscriptions.json (runtime state, not nix-managed),
      # so no secret belongs in this file or in the sops-rendered .env.
      platforms.webhook = {
        enabled = true;
        extra = {
          host = "127.0.0.1";
          port = 8644;
        };
      };
      gateway.platforms.telegram.extra = {
        drop_pending_on_cold_boot = false;
        status_indicator = true;
        # Optional custom strings (defaults: "Online" / "Offline"):
        status_online = "🟢 Online";
        status_offline = "🔴 Offline";
      };

      # Home channel = where cron output and proactive notifications land when a
      # job does not name its own target. Declared here rather than in the
      # sops-rendered .env on purpose: activation rewrites .env from scratch, so
      # a hand-added TELEGRAM_HOME_CHANNEL would be deleted by the next deploy.
      # config.yaml is the canonical store (what `/sethome` persists); the env
      # var is only a best-effort mirror of it.
      #
      # thread_id is REQUIRED on this account: the DM runs in topic mode, and a
      # delivery with no thread id lands in Telegram's system-only lobby, where
      # Alper cannot reply and the gateway drops reply_to_message_id. 1089 is the
      # topic Alper actually chats in; TELEGRAM_CRON_THREAD_ID would override it
      # for cron only. `platform` is required by HomeChannel.from_dict.
      gateway.platforms.telegram.home_channel = {
        platform = "telegram";
        chat_id = "1228209533";
        name = "Home";
        thread_id = "1089";
      };
      gateway.streaming = {
        enabled = true;
        transport = "auto";
      };

      # Voice replies (TTS). A command provider rather than a built-in one: every
      # built-in cloud provider needs its own key, and the local piper backend
      # imports the python `piper` package from the hermes env (an
      # extraDependencyGroups entry that drags torch on aarch64). Kokoro-82M on
      # OpenRouter's speech endpoint passes the account-level ZDR guardrail — the
      # audio-output chat models do not ("0 endpoints … ZDR violation"), and a
      # per-request provider.zdr cannot loosen it. The script writes Ogg/Opus
      # (encoded with the ffmpeg already on the unit PATH); `output_format = ogg`
      # matches that, and `voice_compatible = true` is what makes Hermes deliver
      # a .ogg from a command provider as a native voice bubble — already Opus,
      # so the gateway skips its own ffmpeg transcode. There is deliberately no
      # offline fallback: if OpenRouter fails, the tool reports the error instead
      # of burning VPS CPU on local synthesis. {text_path},
      # {output_path} and {voice} are Hermes' command placeholders.
      tts = {
        provider = "openrouter-kokoro";
        providers."openrouter-kokoro" = {
          type = "command";
          command = "${ttsScript}/bin/hermes-openrouter-tts {text_path} {output_path} {voice}";
          output_format = "ogg";
          voice_compatible = true;
          voice = "af_heart";
        };
      };
      dashboard = {
        public_url = "https://hermes.lab.alper-celik.dev";
        oauth = {
          provider = "self-hosted";
          self_hosted = {
            issuer = "https://id.auth.how/realms/private";
            client_id = "hermes-dashboard";
          };
        };
      };
    };

    environmentFiles = [ config.sops.templates."hermes-env".path ];

    # Commit attribution: agent-made commits carry the automation account's
    # identity, never Alper-Celik's personal one. Requires agent@alper-celik.dev
    # to be a verified email on the bot GitHub account (MCP/API actions — PRs,
    # issues — attribute to the GITHUB_TOKEN account automatically).
    # GIT_CONFIG_* wires git's credential `store` helper to the sops-rendered
    # ~/.git-credentials without editing ~/.gitconfig (hand-managed on the
    # host; it keeps its own `gh auth git-credential` line, whose nix-store path
    # would go stale were gh ever dropped again). Env-config entries outrank
    # file config, so `store` is consulted first while the gh helper stays as a
    # fallback; verified with `git credential fill` against a failing
    # file-level helper. git >= 2.31 (host runs 2.54).
    environment = {
      GIT_AUTHOR_NAME = "hermes-agent";
      GIT_COMMITTER_NAME = "hermes-agent";
      GIT_AUTHOR_EMAIL = "agent@alper-celik.dev";
      GIT_COMMITTER_EMAIL = "agent@alper-celik.dev";
      GIT_CONFIG_COUNT = "1";
      GIT_CONFIG_KEY_0 = "credential.https://github.com.helper";
      GIT_CONFIG_VALUE_0 = "store";

      # Voice-note transcription (Telegram voice messages). Without this, every
      # voice note fails with "No STT provider available":
      #   - the bundled default (faster-whisper) cannot be lazy-installed on a
      #     nixos-managed install ("Feature 'stt.faster_whisper' unavailable:
      #     unsupported on nixos-managed installs"), and the dependency group
      #     would compile 31 derivations from source on aarch64;
      #   - Hermes' local-CLI detector looks for a binary named exactly
      #     `whisper`, while whisper.cpp ships `whisper-cli` — no match;
      #   - no first-party cloud STT key is configured.
      # HERMES_LOCAL_STT_COMMAND is the documented escape hatch: the value runs
      # through shlex.split (no shell — no pipes/globs) and must leave a .txt in
      # {output_dir}. It points at a small script (./scripts/hermes-openrouter-stt.js)
      # that posts the audio to a multimodal model on OpenRouter — ~2 s per note
      # and no CPU load, versus ~10-15x realtime for a local whisper.cpp model on
      # this box's 4 cores. ZDR is enforced account-level and requested per call
      # (provider.zdr). The script falls back to whisper-cli below if the API is
      # unreachable, so an outage degrades to slow, not broken.
      # It also asks the model to tag non-neutral delivery ([sarcastic],
      # [joking], …) so tone survives the transcription; OR_STT_TONE=0 disables.
      HERMES_LOCAL_STT_COMMAND = "${sttScript}/bin/hermes-openrouter-stt {input_path} {output_dir}";
      OR_STT_WHISPER_MODEL = "${whisperModel}";
      # STT model: Voxtral Small 24B (Apache-2.0 open weights) instead of the
      # script's default (google/gemini-3.5-flash-lite). Measured on real voice
      # notes, same verbatim+tone prompt: gemini-3.5-flash-lite turned a spoken
      # "I can talk with you" into "I can't talk with you" on 5 of 5 runs of one
      # clip (a contracted-negative inversion — the exact failure that flips
      # meaning), while voxtral-small-24b did not flip once, at ~0.9 s and ~30x
      # lower cost per note (audio input tokens bill heavily on Gemini rates;
      # the pro Gemini tiers were no more accurate, only slower and pricier).
      # OpenRouter serves it from DeepInfra/Together, both of which pass the
      # account-level ZDR guardrail. Tone tagging is sparser than Gemini's but
      # present; OR_STT_MODEL here beats the script default so the choice is
      # visible in host config, not buried in a JS file.
      OR_STT_MODEL = "mistralai/voxtral-small-24b-2507";
    };

    # Workspace policy file, installed on every activation (nix-managed —
    # runtime edits to it are overwritten on deploy).
    workingDirectory = "/var/lib/hermes/workspace";
    documents."AGENTS.md" = ''
      # Agent identity & GitHub policy

      - You are an automated system and must stay clearly distinguishable from
        Alper: commits use the agent@alper-celik.dev identity, and API actions
        (PRs, issues, comments) attribute to the bot account owning
        GITHUB_TOKEN.
      - NEVER open issues, pull requests, discussions, comments or reviews in
        repositories outside Alper-Celik/* — including "helpful" typo fixes or
        bug reports in third-party projects; that is spam. Reading third-party
        code (clone, search, research) is always fine.
      - If work in a third-party project looks like it needs an issue or PR,
        stop and tell Alper what you would file — Alper decides and acts
        personally.
      - Exception: repositories Alper explicitly names for the task at hand.
      - Work in a dedicated git worktree for every task, never in a shared
        checkout: `git fetch origin && git worktree add -b agent/<topic>
        ../<repo>-<topic> origin/main`, then do all edits and commits there.
        Other agents keep in-flight branches checked out in
        `~/workspace/<repo>`, so committing in the shared tree steps on their
        work; run `git worktree list` first and leave their branches alone.
        Branch from freshly fetched `origin/main`, not from whatever branch the
        shared checkout happens to have checked out. Remove the worktree once
        its PR has merged.
    '';

    backend = {
      # native hardened systemd service; gateway runs as hermes-agent,
      # the dashboard backend runs as the separate hermes-backend unit
      mode = "dashboard";
      port = hermesPorts.dashboard;
    };
  };
}
