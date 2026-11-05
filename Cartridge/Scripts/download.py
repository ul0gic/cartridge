import urllib.request

TIMEOUT_SECONDS = 60
CHUNK_BYTES = 1 << 20


def fetch(url, max_bytes):
    if not url.startswith("https://"):
        raise ValueError("refusing non-https url: " + url)
    chunks = []
    total = 0
    with urllib.request.urlopen(url, timeout=TIMEOUT_SECONDS) as response:
        while True:
            chunk = response.read(CHUNK_BYTES)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError("%s exceeds %d bytes" % (url, max_bytes))
            chunks.append(chunk)
    return b"".join(chunks)
