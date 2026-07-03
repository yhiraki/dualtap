# dualtap

Record your **microphone and your Mac's system audio at the same time** — no BlackHole, no loopback drivers, no virtual audio devices to install.

On macOS there is normally no built-in way to capture what you hear *and* what you say in one recording; the usual answer is to install a virtual audio device like BlackHole and wire up an aggregate device by hand. `dualtap` skips all of that: it taps system audio through Core Audio's native process-tap API (macOS 14.4+) and records the mic through the audio engine, then combines them into a single file.

Good for capturing meetings and interviews, podcast or remote-guest recordings, language-learning sessions, or any call you want to keep notes on.

## What you get

- **Two sources, one command.** Mic and system audio recorded together.
- **Native, no extra drivers.** Nothing to install into the system audio stack.
- **Separate channels by default.** The combined file puts your mic on the **left** and system audio on the **right**, so the two voices never mask each other and downstream tools (editors, transcribers) can split or downmix them freely.
- **Robust mic selection.** dualtap probes input devices and pins one that is actually receiving audio, so it won't silently follow a meeting app that hijacks the default input mid-call.
- **Live level meter** in the terminal and an optional **menu bar** indicator — both show whether audio is really flowing, not just whether a process is alive.

## Requirements

- macOS 14.4 or newer (system audio uses the Core Audio process-tap API).
- Swift toolchain (Xcode or the Swift command-line tools) to build.
- `afconvert` — ships with macOS.

## Build

```sh
./build.sh          # → .build/release/dualtap
```

Copy `.build/release/dualtap` somewhere on your `PATH` if you like.

## Permissions

dualtap records from the terminal it's launched in, so the first run triggers two macOS permission prompts attributed to **your terminal app**:

- **Microphone** — for the mic.
- **Audio recording / screen recording** — for the system-audio process tap.

Grant both once; no restart needed.

## Usage

```sh
dualtap record                       # record until Ctrl+C → ./dualtap-<timestamp>.wav
dualtap record -o meeting.m4a -f m4a # choose output path and container
dualtap record --tracks separate     # write mic and system audio as two files
dualtap record --transcribe -o call.m4a   # 16 kHz mono→L/R m4a, tuned for speech-to-text
dualtap record --no-system            # microphone only
dualtap record --exec 'whisper {}'    # run a command on the output once saved
dualtap monitor                       # live meter for a recording running elsewhere
dualtap devices                       # list input devices (for --mic-device)
dualtap menubar                       # menu bar indicator (run in the background)
```

While `record` runs in a terminal, it shows a live meter inline. Press `Ctrl+C` to stop; dualtap finalizes and combines the tracks, then writes the output.

### record options

| Option | Default | Description |
|---|---|---|
| `-o, --output PATH` | `./dualtap-<timestamp>.<ext>` | Output file |
| `-f, --format wav\|m4a` | `wav` | Container |
| `-t, --tracks MODE` | `combined` | `combined` (L=mic, R=sys), `separate` (two files), or `both` |
| `-r, --rate HZ` | `48000` | Resample both sources to this rate |
| `--transcribe` | off | Preset for speech-to-text: 16 kHz, m4a, combined |
| `--mic-device NAME` | auto | Pin the mic by device name or UID (see `dualtap devices`) |
| `--no-mic` / `--no-system` | both | Record only one source |
| `--title NAME` | `recording` | Label shown in `monitor` / `menubar` |
| `-x, --exec CMD` | off | Run `CMD` via `/bin/sh` after saving; `{}` and `$DUALTAP_OUTPUT` expand to the output path |

## How it works

- **System audio** (`SysTap`): creates a system-wide Core Audio process tap and a private aggregate device, then writes the tap's stream to a WAV. Playback is not muted — you still hear everything.
- **Microphone** (`MicTap`): probes candidate input devices (explicit → built-in → physical → default), picks one that delivers non-silent audio, and pins it so a default-input change can't hijack the recording. It reconfigures automatically if a device is switched or unplugged mid-recording.
- **Combine**: on stop, each source is normalized to 16-bit mono at the target rate with `afconvert`, then interleaved into an L=mic / R=sys stereo file (or emitted separately).

The mic and system tracks run at independent clocks, so they're recorded separately and combined at the end rather than mixed in real time.

## License

MIT — see [LICENSE](LICENSE).
