# OPEN_SOURCE_TOOLS.md

Every tool this project uses is **free and open source**. The licenses below were
verified from each project's official repository / official documentation.

> **Note:** This file is a reference copy. Each time you run
> `Run_OG_TikTok_Downloader.command` on your Mac, the script **refreshes this file
> automatically** with the exact versions actually installed on your Mac (and keeps
> a timestamped backup of the previous copy in the `Archive/` folder).

| Tool | Official source | License | Purpose | Open source? |
|------|-----------------|---------|---------|--------------|
| **yt-dlp** | https://github.com/yt-dlp/yt-dlp | The Unlicense (public domain) | The downloader. Fetches the videos, metadata JSON, thumbnails, and descriptions. | ✅ Yes |
| **FFmpeg / FFprobe** | https://ffmpeg.org | LGPL-2.1-or-later (some optional parts GPL) | Remuxes/merges to MP4, converts thumbnails to JPG, and verifies each file is a real, playable video (FFprobe). | ✅ Yes |
| **Python 3** | https://www.python.org | PSF License (OSI-approved) | Runs the small indexing script (`Scripts/organize_and_index.py`) that builds `video_index.csv`. Standard library only — **no pandas**. | ✅ Yes |
| **Homebrew** | https://brew.sh | BSD-2-Clause | The macOS package manager, used **only** to install the open-source tools above. | ✅ Yes |
| **curl_cffi** (optional) | https://github.com/lexiforest/curl_cffi | MIT License | Optional "browser impersonation" that helps yt-dlp reach TikTok more reliably. Installed automatically if possible; the tool still works without it. | ✅ Yes |

## What is explicitly NOT used

- ❌ No paid APIs
- ❌ No Apify
- ❌ No Google Drive / Google Sheets
- ❌ No cloud storage
- ❌ No browser extensions
- ❌ No closed-source downloading applications

## Reference versions verified during the build

These were the versions confirmed while building this project (your Mac may install
newer ones — that is expected and good):

- yt-dlp: `2026.06.09`
- FFmpeg / FFprobe: `6.1.1`
- Python 3: `3.11.x`

To update yt-dlp to the newest release later, run in Terminal:

```
brew upgrade yt-dlp
```
