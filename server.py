#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
مساري - خادم الصوت المحلي
يجلب مسار الصوت من يوتيوب عبر yt-dlp ويقدّمه لتطبيق مساري بنفس شكل واجهة Piped،
فيعمل وضع الصوت (التشغيل في الخلفية مع إغلاق الشاشة) دون الاعتماد على خوادم عامة.

التشغيل:   python server.py [المنفذ]        (الافتراضي 8787)
الإعداد في التطبيق:  وضع الصوت ← ⚙ ← "+ محلي" ← اختبار ← حفظ
"""
import json, sys, time, shutil, threading, urllib.request, urllib.error
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

try:
    from yt_dlp import YoutubeDL
except ImportError:
    print("yt-dlp is not installed.  Run:  pip install -U yt-dlp")
    sys.exit(1)

PORT = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 8787
CACHE, LOCK = {}, threading.Lock()


def ydl(**o):
    base = {"quiet": True, "no_warnings": True, "skip_download": True,
            "noplaylist": True, "socket_timeout": 20}
    rt = {n: {} for n in ("deno", "node", "bun") if shutil.which(n)}
    if rt:
        base["js_runtimes"] = rt   # recent YouTube extraction may need a JavaScript runtime
    base.update(o)
    return YoutubeDL(base)


def stream_info(vid):
    with LOCK:
        c = CACHE.get(vid)
    if c and time.time() - c["t"] < 1800:
        return c
    i = ydl(format="bestaudio[ext=m4a]/bestaudio/best").extract_info(
        "https://www.youtube.com/watch?v=" + vid, download=False)
    f = i if i.get("url") else (i.get("requested_formats") or [{}])[0]
    if not f.get("url"):
        raise RuntimeError("no audio url")
    ext = f.get("ext") or i.get("ext") or "m4a"
    c = {"t": time.time(), "url": f["url"],
         "hdr": f.get("http_headers") or i.get("http_headers") or {},
         "title": i.get("title") or "", "dur": int(i.get("duration") or 0),
         "mime": "audio/mp4" if ext in ("m4a", "mp4") else "audio/webm",
         "abr": int((f.get("abr") or 128) * 1000)}
    with LOCK:
        CACHE[vid] = c
    return c


FCACHE = {}


def all_info(vid):
    with LOCK:
        c = FCACHE.get(vid)
    if c and time.time() - c["t"] < 1800:
        return c
    i = ydl().extract_info("https://www.youtube.com/watch?v=" + vid, download=False)
    fm = {}
    for f in i.get("formats") or []:
        if f.get("url") and f.get("format_id") and f.get("protocol") in ("https", "http"):
            fm[str(f["format_id"])] = f
    c = {"t": time.time(), "title": i.get("title") or "", "dur": int(i.get("duration") or 0), "fm": fm}
    with LOCK:
        FCACHE[vid] = c
    return c


def playlist_items(pid):
    i = ydl(extract_flat="in_playlist", noplaylist=False).extract_info(
        "https://www.youtube.com/playlist?list=" + pid, download=False)
    out = []
    for e in i.get("entries") or []:
        if not e or not e.get("id"):
            continue
        t = e.get("title") or ""
        if t in ("[Private video]", "[Deleted video]"):
            continue
        out.append({"url": "/watch?v=" + e["id"], "type": "stream",
                    "title": t, "duration": int(e.get("duration") or 0)})
    return out


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")

    def send_json(self, obj, code=200):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Max-Age", "600")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def base(self):
        host = self.headers.get("Host") or "localhost:%d" % PORT
        proto = self.headers.get("X-Forwarded-Proto") or ("https" if host.endswith("trycloudflare.com") else "http")
        return proto + "://" + host

    def do_GET(self):
        p = urlparse(self.path).path
        try:
            if p in ("/", "/ping"):
                return self.send_json({"ok": True, "server": "masari-audio"})
            if p.startswith("/streams/"):
                return self.send_json(self.streams_json(p.split("/")[2]))
            if p.startswith("/playlists/"):
                return self.send_json({"relatedStreams": playlist_items(p.split("/")[2]), "nextpage": None})
            if p.startswith("/nextpage/"):
                return self.send_json({"relatedStreams": [], "nextpage": None})
            if p.startswith("/audio/"):
                return self.audio(p.split("/")[2])
            if p.startswith("/media/"):
                _, _, vid, fid = p.split("/")[:4]
                return self.media(vid, fid)
            self.send_json({"message": "not found"}, 404)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except Exception as e:
            print("error:", str(e)[:300])
            try:
                self.send_json({"error": "failed", "message": str(e)[:300]}, 500)
            except Exception:
                pass

    def streams_json(self, vid):
        base = self.base()
        vs, au = [], []
        try:
            a = all_info(vid)
            title, dur = a["title"], a["dur"]
            for fid, f in a["fm"].items():
                url = base + "/media/" + vid + "/" + fid
                ext, vc, ac = f.get("ext"), f.get("vcodec") or "none", f.get("acodec") or "none"
                size = int(f.get("filesize") or f.get("filesize_approx") or 0)
                if vc != "none" and f.get("height"):
                    vs.append({"url": url, "mimeType": "video/mp4" if ext in ("mp4", "m4v") else "video/webm",
                               "videoOnly": ac == "none", "quality": "%sp" % f["height"], "height": f["height"],
                               "bitrate": int((f.get("tbr") or 0) * 1000), "contentLength": size, "codec": vc})
                elif ac != "none":
                    m4a = ext in ("m4a", "mp4")
                    au.append({"url": url, "mimeType": "audio/mp4" if m4a else "audio/webm",
                               "format": "M4A" if m4a else "WEBM", "videoOnly": False,
                               "bitrate": int((f.get("abr") or f.get("tbr") or 0) * 1000), "contentLength": size})
        except Exception:
            i = stream_info(vid)
            title, dur = i["title"], i["dur"]
        if not au:
            i = stream_info(vid)
            au = [{"url": base + "/audio/" + vid, "mimeType": i["mime"],
                   "format": "M4A" if i["mime"] == "audio/mp4" else "WEBM", "bitrate": i["abr"], "videoOnly": False}]
        return {"title": title, "duration": dur, "audioStreams": au, "videoStreams": vs}

    def media(self, vid, fid):
        f = all_info(vid)["fm"].get(fid)
        if not f:
            return self.send_json({"message": "format not found"}, 404)
        self.proxy(f["url"], f.get("http_headers") or {}, lambda: FCACHE.pop(vid, None))

    def audio(self, vid):
        i = stream_info(vid)
        self.proxy(i["url"], i["hdr"], lambda: CACHE.pop(vid, None))

    def proxy(self, url, hdr, drop=None):
        h = dict(hdr)
        rng = self.headers.get("Range")
        if rng:
            h["Range"] = rng
            return self.pipe(url, h, drop)
        self.whole(url, h, drop)

    def pipe(self, url, h, drop):
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=30)
        except urllib.error.HTTPError as e:
            if drop:
                drop()
            self.send_response(e.code)
            self.cors()
            self.end_headers()
            return
        self.send_response(r.status)
        self.cors()
        for k in ("Content-Type", "Content-Length", "Content-Range"):
            v = r.headers.get(k)
            if v:
                self.send_header(k, v)
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        try:
            while True:
                b = r.read(65536)
                if not b:
                    break
                self.wfile.write(b)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        finally:
            r.close()

    def whole(self, url, h, drop):
        # the whole file was requested: YouTube throttles one big request, so fetch it in 8 MB ranges
        total, ctype = 0, "application/octet-stream"
        try:
            r0 = urllib.request.urlopen(urllib.request.Request(url, headers=dict(h, Range="bytes=0-0")), timeout=30)
            cr = r0.headers.get("Content-Range") or ""
            ctype = r0.headers.get("Content-Type") or ctype
            r0.read(1)
            r0.close()
            total = int(cr.split("/")[-1]) if "/" in cr else 0
        except Exception:
            total = 0
        if not total:
            return self.pipe(url, h, drop)
        self.send_response(200)
        self.cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(total))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        pos, step = 0, 8 * 1024 * 1024
        try:
            while pos < total:
                end = min(pos + step, total) - 1
                r = urllib.request.urlopen(urllib.request.Request(url, headers=dict(h, Range="bytes=%d-%d" % (pos, end))), timeout=30)
                try:
                    while True:
                        b = r.read(65536)
                        if not b:
                            break
                        self.wfile.write(b)
                finally:
                    r.close()
                pos = end + 1
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except Exception as e:
            print("download error:", str(e)[:200])


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    srv.daemon_threads = True
    print("Masari audio server is running on  http://localhost:%d   (Ctrl+C to stop)" % PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
