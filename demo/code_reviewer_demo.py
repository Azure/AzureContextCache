"""Azure Context Cache — end-to-end validation demo (AI Code Reviewer).

Sends N PR-review requests to an Azure OpenAI deployment using the **Responses
API**. The same ~2.4K-token system prompt (`system_prompt.md`) is sent on every
call — only the trailing diff varies. If the deployment is linked to an Azure
Context Cache container (as the one created by this repo's `azuredeploy.json`
is), call #2 onward should show large `cached_tokens` and meaningfully lower
latency than call #1.

Usage:
    # Recommended: use the deployment outputs from the ARM deploy
    python code_reviewer_demo.py \
        --endpoint   https://<prefix>-aoai.openai.azure.com \
        --deployment context-cache-deployment \
        --api-key    $env:AOAI_KEY \
        --runs 6

    # Or use Azure AD (DefaultAzureCredential)
    python code_reviewer_demo.py --endpoint ... --deployment ... --aad --runs 6

Environment variables (override CLI defaults):
    AOAI_ENDPOINT, AOAI_DEPLOYMENT, AOAI_API_KEY, AOAI_API_VERSION
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from pathlib import Path

import httpx

HERE = Path(__file__).parent
DEFAULT_API_VERSION = "preview"


def _aad_token() -> str:
    try:
        from azure.identity import DefaultAzureCredential
    except ImportError:
        sys.exit("azure-identity not installed: pip install azure-identity")
    return (
        DefaultAzureCredential(exclude_interactive_browser_credential=False)
        .get_token("https://cognitiveservices.azure.com/.default")
        .token
    )


def load_diffs(n: int) -> list[tuple[str, str]]:
    files = sorted((HERE / "diffs").glob("*.diff"))
    if not files:
        sys.exit("No diffs found under ./diffs")
    out: list[tuple[str, str]] = []
    i = 0
    while len(out) < n:
        f = files[i % len(files)]
        out.append((f.name, f.read_text(encoding="utf-8")))
        i += 1
    return out


def build_payload(deployment: str, system_prompt: str, diff_name: str, diff_body: str,
                  max_output_tokens: int) -> dict:
    user_msg = (
        "Review this PR diff and return the JSON described in your instructions.\n\n"
        f"File: {diff_name}\n\n```diff\n{diff_body}\n```"
    )
    return {
        "model": deployment,
        "input": [
            {
                "type": "message",
                "role": "system",
                "content": [{"type": "input_text", "text": system_prompt}],
            },
            {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": user_msg}],
            },
        ],
        "max_output_tokens": max_output_tokens,
        # Enables SSD-backed prompt cache (pre-req for remote cache).
        "prompt_cache_retention": "24h",
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--endpoint", default=os.getenv("AOAI_ENDPOINT", ""),
                   help="Azure OpenAI endpoint (e.g. https://<prefix>-aoai.openai.azure.com).")
    p.add_argument("--deployment", default=os.getenv("AOAI_DEPLOYMENT", "context-cache-deployment"),
                   help="AOAI deployment name (default: context-cache-deployment).")
    p.add_argument("--api-key", default=os.getenv("AOAI_API_KEY", ""),
                   help="AOAI API key. Ignored when --aad is set.")
    p.add_argument("--aad", action="store_true",
                   help="Use DefaultAzureCredential instead of an API key.")
    p.add_argument("--api-version", default=os.getenv("AOAI_API_VERSION", DEFAULT_API_VERSION))
    p.add_argument("--runs", type=int, default=6,
                   help="How many requests to send (default: 6).")
    p.add_argument("--max-output", type=int, default=200,
                   help="max_output_tokens per call (default: 200).")
    p.add_argument("--concurrency", type=int, default=0,
                   help="Parallel in-flight requests for calls 2..N (0 = all at once; 1 = fully sequential).")
    p.add_argument("--show-output", action="store_true",
                   help="Print the JSON reviewer output for each call.")
    args = p.parse_args()

    if not args.endpoint:
        sys.exit("Set --endpoint or AOAI_ENDPOINT (see deployment Outputs tab).")
    if not args.aad and not args.api_key:
        sys.exit("Provide --api-key / AOAI_API_KEY, or pass --aad.")

    url = f"{args.endpoint.rstrip('/')}/openai/v1/responses?api-version={args.api_version}"
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if args.aad:
        headers["Authorization"] = f"Bearer {_aad_token()}"
    else:
        headers["api-key"] = args.api_key
        headers["Authorization"] = f"Bearer {args.api_key}"

    system_prompt = (HERE / "system_prompt.md").read_text(encoding="utf-8")
    diffs = load_diffs(args.runs)

    concurrency = args.concurrency if args.concurrency > 0 else max(1, args.runs - 1)
    mode = "sequential" if concurrency == 1 or args.runs <= 1 else f"parallel x{concurrency}"

    print(f"\nAzure Context Cache demo  ·  endpoint = {args.endpoint}")
    print(f"deployment = {args.deployment}  ·  runs = {args.runs}  ·  api = {args.api_version}")
    print(f"mode: call #1 warm-up sequential; calls 2..{args.runs} {mode}\n")
    print(f"{'#':>2}  {'diff':<26} {'lat(ms)':>9}  {'in':>6}  {'cached':>7}  {'out':>5}  {'hit%':>5}")
    print("-" * 72)

    # Per-call result slots so parallel results can be printed in order.
    results: list[dict | None] = [None] * len(diffs)

    def _record(i: int, name: str, lat: float, status: int, text: str, data: dict | None) -> None:
        if status >= 400:
            results[i] = {"name": name, "err": f"HTTP {status}: {text[:200]}"}
            return
        usage = (data or {}).get("usage", {}) or {}
        in_tok = int(usage.get("input_tokens") or 0)
        out_tok = int(usage.get("output_tokens") or 0)
        cached = int((usage.get("input_tokens_details") or {}).get("cached_tokens") or 0)
        pct = (100.0 * cached / in_tok) if in_tok else 0.0
        results[i] = {"name": name, "lat": lat, "in": in_tok, "cached": cached,
                      "out": out_tok, "pct": pct, "data": data}

    def _print_row(i: int) -> None:
        r = results[i]
        if r is None:
            return
        if "err" in r:
            print(f"{i+1:>2}  {r['name']:<26}  {r['err']}")
            return
        print(f"{i+1:>2}  {r['name']:<26} {r['lat']:>9.0f}  {r['in']:>6}  "
              f"{r['cached']:>7}  {r['out']:>5}  {r['pct']:>4.0f}%")
        if args.show_output and r.get("data"):
            text = r["data"].get("output_text") or json.dumps(r["data"].get("output"), indent=2)[:500]
            print(f"      output: {text[:300]}{'…' if len(text) > 300 else ''}")

    # ---- Call #1: sequential warm-up so the cache is populated before the burst. ----
    name0, body0 = diffs[0]
    payload0 = build_payload(args.deployment, system_prompt, name0, body0, args.max_output)
    t0 = time.perf_counter()
    with httpx.Client(timeout=240.0) as client:
        try:
            r0 = client.post(url, json=payload0, headers=headers)
            lat0 = (time.perf_counter() - t0) * 1000.0
            try:
                data0 = r0.json()
            except Exception:
                data0 = None
            _record(0, name0, lat0, r0.status_code, r0.text, data0)
        except httpx.HTTPError as e:
            results[0] = {"name": name0, "err": f"transport error: {e}"}
    _print_row(0)

    # ---- Calls 2..N: fire in parallel (concurrency-limited) to exercise distributed cache. ----
    parallel_wall_ms = 0.0
    if len(diffs) > 1:
        async def _run_parallel() -> None:
            sem = asyncio.Semaphore(concurrency)
            limits = httpx.Limits(max_connections=concurrency, max_keepalive_connections=concurrency)
            async with httpx.AsyncClient(timeout=240.0, limits=limits) as aclient:
                async def _one(i: int, name: str, body: str) -> None:
                    payload = build_payload(args.deployment, system_prompt, name, body, args.max_output)
                    async with sem:
                        ts = time.perf_counter()
                        try:
                            rr = await aclient.post(url, json=payload, headers=headers)
                            lat = (time.perf_counter() - ts) * 1000.0
                            try:
                                jd = rr.json()
                            except Exception:
                                jd = None
                            _record(i, name, lat, rr.status_code, rr.text, jd)
                        except httpx.HTTPError as e:
                            results[i] = {"name": name, "err": f"transport error: {e}"}

                tasks = [_one(i, n, b) for i, (n, b) in enumerate(diffs) if i >= 1]
                await asyncio.gather(*tasks)

        burst_start = time.perf_counter()
        asyncio.run(_run_parallel())
        parallel_wall_ms = (time.perf_counter() - burst_start) * 1000.0
        for i in range(1, len(diffs)):
            _print_row(i)

    # ---- Aggregate. ----
    ok = [r for r in results if r and "err" not in r]
    if not ok:
        return 2
    latencies = [r["lat"] for r in ok]
    cached_pcts = [r["pct"] for r in ok]
    first_latency = results[0]["lat"] if results[0] and "err" not in results[0] else None
    warm_latencies = [results[i]["lat"] for i in range(1, len(results))
                      if results[i] and "err" not in results[i]]

    print("-" * 72)
    print(f"mean latency        : {statistics.mean(latencies):>7.0f} ms")
    if first_latency is not None:
        print(f"call 1 (cold)       : {first_latency:>7.0f} ms")
    if warm_latencies:
        warm_mean = statistics.mean(warm_latencies)
        print(f"calls 2..N (warm)   : {warm_mean:>7.0f} ms mean per call", end="")
        if first_latency:
            print(f"   →   {(first_latency / warm_mean):.2f}× speedup")
        else:
            print("   (call 1 failed; no cold baseline)")
        if parallel_wall_ms > 0:
            n_warm = len(warm_latencies)
            serial_est = sum(warm_latencies)
            print(f"calls 2..N wall-clock: {parallel_wall_ms:>7.0f} ms for {n_warm} parallel calls "
                  f"(serial would be ~{serial_est:.0f} ms)")
    print(f"mean cached prefix  : {statistics.mean(cached_pcts):>6.1f}% of input tokens")
    warm_hits = [results[i]["pct"] for i in range(1, len(results))
                 if results[i] and "err" not in results[i]]
    if warm_hits:
        print(f"warm-call hit-rate  : {statistics.mean(warm_hits):>6.1f}% mean   "
              f"(min {min(warm_hits):.0f}%, max {max(warm_hits):.0f}%)")
    if statistics.mean(cached_pcts) < 1:
        print("\n⚠  cached_tokens is ~0. Things to check:")
        print("    · The deployment has properties.contextCacheContainerId set (this is what the ARM template does).")
        print("    · You are sending the byte-identical system prompt every call.")
        print("    · The Microsoft.CognitiveServices/OpenAI.ContextCacheAllowed feature is Registered.")
    else:
        print("\n✓  Prompt cache is active — the linked Azure Context Cache container is serving hits.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
