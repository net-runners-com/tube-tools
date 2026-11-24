# tube-tools

The programs [Tube](https://github.com/net-runners-com/tube) downloads on first start, from one place.

Each release holds, for macOS, Windows and Linux (x64 and arm64):

| Tool | What for | Source |
|---|---|---|
| **yt-dlp** | reading YouTube | [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp) official builds |
| **Node.js** (LTS) | yt-dlp's JavaScript runtime for YouTube's player | [nodejs.org](https://nodejs.org/dist/) |
| **ffmpeg** | joining video and audio for downloads | [yt-dlp/FFmpeg-Builds](https://github.com/yt-dlp/FFmpeg-Builds) (Windows, Linux), [Martin Riedl's builds](https://ffmpeg.martin-riedl.de) (macOS) |

plus `manifest.json` with each file's SHA-256. The release workflow (run by hand) fetches every
tool from its publisher and checks it against the checksum that publisher posts. Each Tube version
pins the release it uses, so new tools reach people with the next Tube update; Tube verifies the
manifest's SHA-256 before it unpacks anything.

Each tool keeps its own license (yt-dlp: Unlicense, Node.js: MIT, ffmpeg builds: GPL).
