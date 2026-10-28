#!/usr/bin/env python3
"""Freesound helper for game sound effects.

  freesound.py search  "axe chop log" [--max-dur 3] [--min-dur 0.1] [-n 12] [--loop]
  freesound.py audition OUT.html  "slot: query" ["slot: query" ...]  [--max-dur 3] [-n 6]
  freesound.py fetch   ID NAME --to DIR [--loop] [--peak -1] [--rms -14] [--start S] [--length L]

Only Creative Commons 0 sounds are ever returned, so anything found can go in
a game with no credit owed (the source is still written down in SOURCES.md).

The API key is read from, in order: --key-file, $FREESOUND_API_KEY, a
.freesound_key file in the current folder or any folder above it, then
~/.freesound_key. It is never printed.

Audio comes from Freesound's high-quality previews (the original files need a
full OAuth login), converted to 44.1 kHz mono 16-bit WAV with ffmpeg.
"""
import argparse, html, json, os, pathlib, re, shutil, subprocess, sys, tempfile, urllib.parse, urllib.request

API = "https://freesound.org/apiv2"
FIELDS = "id,name,duration,license,username,previews,avg_rating,num_downloads,tags,url"


def api_key(path=None):
    if path:
        return pathlib.Path(path).expanduser().read_text().strip()
    if os.environ.get("FREESOUND_API_KEY"):
        return os.environ["FREESOUND_API_KEY"].strip()
    here = pathlib.Path.cwd()
    for d in [here, *here.parents]:
        f = d / ".freesound_key"
        if f.is_file():
            return f.read_text().strip()
    f = pathlib.Path.home() / ".freesound_key"
    if f.is_file():
        return f.read_text().strip()
    sys.exit("No Freesound API key found. Put it in a file named .freesound_key in the project "
             "folder (get one free at https://freesound.org/apiv2/apply), or set FREESOUND_API_KEY.")


def search(key, query, n=12, min_dur=0.0, max_dur=10.0, loop=False):
    filt = f'license:"Creative Commons 0" duration:[{min_dur} TO {max_dur}]'
    if loop:
        filt += " tag:loop"
    q = urllib.parse.urlencode({
        "query": query, "filter": filt, "fields": FIELDS, "page_size": n,
        "sort": "score", "token": key,
    })
    try:
        with urllib.request.urlopen(f"{API}/search/text/?{q}", timeout=30) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"Freesound said {e.code}: {e.read()[:200]!r}")
    out = []
    for s in data.get("results", []):
        out.append({
            "id": s["id"], "name": s["name"], "duration": round(s["duration"], 2),
            "user": s["username"], "rating": round(s.get("avg_rating") or 0, 1),
            "downloads": s.get("num_downloads", 0), "page": s["url"],
            "preview": s["previews"].get("preview-hq-mp3"),
            "tags": s.get("tags", [])[:8],
        })
    # Well-liked, much-used sounds first among the matches.
    out.sort(key=lambda s: -(s["rating"] * 2 + min(s["downloads"], 5000) / 1000))
    return out


def sound_info(key, sid):
    q = urllib.parse.urlencode({"fields": FIELDS, "token": key})
    with urllib.request.urlopen(f"{API}/sounds/{sid}/?{q}", timeout=30) as r:
        s = json.load(r)
    if "publicdomain/zero" not in s["license"]:
        sys.exit(f"Sound {sid} is not CC0 ({s['license']}); refusing to use it.")
    return s


def run(*cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"{cmd[0]} failed: {p.stderr[-400:]}")
    return p.stdout + p.stderr


def levels(path):
    out = run("ffmpeg", "-nostdin", "-i", str(path), "-af", "volumedetect", "-f", "null", "-")
    mean = float(re.search(r"mean_volume: (-?[\d.]+)", out).group(1))
    peak = float(re.search(r"max_volume: (-?[\d.]+)", out).group(1))
    return mean, peak


def duration(path):
    return float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)).strip())


def crossfade_loop(src, dst, fade):
    """The last `fade` seconds faded into the first, the rest after: played
    round and round, the end runs straight on into the faded start."""
    import array, wave
    with wave.open(str(src)) as w:
        rate, width = w.getframerate(), w.getsampwidth()
        frames = array.array("h", w.readframes(w.getnframes()))
    if width != 2:
        sys.exit("expected 16-bit audio")
    k = int(fade * rate)
    if len(frames) < 4 * k:
        k = len(frames) // 4
    head, mid, tail = frames[:k], frames[k:len(frames) - k], frames[len(frames) - k:]
    out = array.array("h")
    for i in range(k):
        t = i / max(1, k - 1)
        out.append(int(round(tail[i] * (1.0 - t) + head[i] * t)))
    out.extend(mid)
    with wave.open(str(dst), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())


def fetch(key, sid, name, to, loop=False, peak=-1.0, rms=-14.0, start=None, length=None):
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg is needed (install it and try again).")
    s = sound_info(key, sid)
    to = pathlib.Path(to)
    to.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        src = tmp / "src.mp3"
        urllib.request.urlretrieve(s["previews"]["preview-hq-mp3"], src)
        cut = ["-ss", str(start)] if start is not None else []
        cut += ["-t", str(length)] if length is not None else []
        a = tmp / "a.wav"
        run("ffmpeg", "-nostdin", "-y", *cut, "-i", str(src), "-ac", "1", "-ar", "44100", str(a))
        out = to / f"{name}.wav"
        if loop:
            # Levelled by loudness; the end is crossfaded into the start so it
            # goes round with no click or bump.
            mean, _ = levels(a)
            d = duration(a)
            fade = min(0.25, d * 0.15)
            b = tmp / "b.wav"
            crossfade_loop(a, b, fade)
            run("ffmpeg", "-nostdin", "-y", "-i", str(b), "-af",
                f"volume={rms - mean}dB,alimiter=limit=0.95", "-c:a", "pcm_s16le", str(out))
        else:
            # Peak-levelled first, then the silence before it cut and the end faded.
            _, pk = levels(a)
            b = tmp / "b.wav"
            run("ffmpeg", "-nostdin", "-y", "-i", str(a), "-af",
                f"volume={peak - pk}dB,silenceremove=start_periods=1:start_duration=0:start_threshold=-36dB:start_silence=0.004",
                str(b))
            d = duration(b)
            run("ffmpeg", "-nostdin", "-y", "-i", str(b), "-af",
                f"afade=t=out:st={max(0.0, d - 0.04)}:d=0.04", "-c:a", "pcm_s16le", str(out))
    mean, pk = levels(out)
    src_line = f"- `{name}.wav` - \"{s['name']}\" by {s['username']}, {s['url']} (CC0)\n"
    sources = to / "SOURCES.md"
    lines = sources.read_text().splitlines(keepends=True) if sources.exists() else ["# Where these sounds came from\n\n"]
    lines = [l for l in lines if not l.startswith(f"- `{name}.wav`")] + [src_line]
    sources.write_text("".join(lines))
    print(json.dumps({"file": str(out), "seconds": round(duration(out), 2), "loop": loop,
                      "mean_db": mean, "peak_db": pk, "source": s["url"], "by": s["username"]}))


AUDITION_HEAD = """<!doctype html><meta charset=utf-8><title>Sound audition</title>
<style>body{font:15px system-ui;margin:24px;background:#16181c;color:#eee}h2{margin:28px 0 8px;color:#f6c25b}
.s{display:flex;gap:12px;align-items:center;padding:6px 0;border-bottom:1px solid #2a2d33}
.id{font:12px monospace;color:#9aa;min-width:70px}.n{flex:1}audio{height:30px}a{color:#8cf}</style>
<h1>Pick a sound for each slot</h1><p>Play them, then tell Claude the slot and the number (e.g. <b>chop: 2</b>).</p>
"""


def audition(key, out, slots, n=6, min_dur=0.0, max_dur=10.0):
    parts = [AUDITION_HEAD]
    picks = {}
    for slot in slots:
        name, _, query = slot.partition(":")
        name, query = name.strip(), (query or name).strip()
        loop = name.startswith("engine") or name.endswith("_loop") or "loop" in query
        found = search(key, query, n=n, min_dur=min_dur, max_dur=max_dur if not loop else 30.0)
        picks[name] = [s["id"] for s in found]
        parts.append(f"<h2>{html.escape(name)} <small style='color:#888'>({html.escape(query)})</small></h2>")
        if not found:
            parts.append("<p>Nothing CC0 found - try other words.</p>")
        for i, s in enumerate(found, 1):
            parts.append(
                f"<div class=s><b>{i}</b><span class=id>#{s['id']}</span>"
                f"<span class=n>{html.escape(s['name'])} <small>({s['duration']}s, by {html.escape(s['user'])}, "
                f"rated {s['rating']})</small></span><audio controls preload=none src='{s['preview']}'></audio>"
                f"<a href='{s['page']}' target=_blank>page</a></div>")
    pathlib.Path(out).write_text("".join(parts))
    print(json.dumps({"page": str(out), "slots": picks}))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key-file")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search"); s.add_argument("query"); s.add_argument("-n", type=int, default=12)
    s.add_argument("--min-dur", type=float, default=0.0); s.add_argument("--max-dur", type=float, default=10.0)
    s.add_argument("--loop", action="store_true")
    a = sub.add_parser("audition"); a.add_argument("out"); a.add_argument("slots", nargs="+")
    a.add_argument("-n", type=int, default=6)
    a.add_argument("--min-dur", type=float, default=0.0); a.add_argument("--max-dur", type=float, default=10.0)
    f = sub.add_parser("fetch"); f.add_argument("id", type=int); f.add_argument("name")
    f.add_argument("--to", required=True); f.add_argument("--loop", action="store_true")
    f.add_argument("--peak", type=float, default=-1.0); f.add_argument("--rms", type=float, default=-14.0)
    f.add_argument("--start", type=float); f.add_argument("--length", type=float)
    args = ap.parse_args()
    key = api_key(args.key_file)
    if args.cmd == "search":
        print(json.dumps(search(key, args.query, args.n, args.min_dur, args.max_dur, args.loop), indent=1))
    elif args.cmd == "audition":
        audition(key, args.out, args.slots, args.n, args.min_dur, args.max_dur)
    else:
        fetch(key, args.id, args.name, args.to, args.loop, args.peak, args.rms, args.start, args.length)


if __name__ == "__main__":
    main()
