#!/usr/bin/env python3
"""usage.py <usage.jsonl>: deepagents model-call totals per stage and role, with a computed USD estimate (050 run 2).
Rows come from the runner's <run>/usage.jsonl (one per model call: stage, role, model, input, cached, output).
shortcut: prices are the 11-18 developers.openai.com standard-tier short-context rates (<=272K input); a call above 272K
input is counted at the short rate, so the estimate is then a floor (050 run 2: largest input 156,542). Not a bill;
update PRICE when the price page or the models change. Claude rows (Anthropic API, prices cached 2026-11-03 in the
claude-api skill): `input` holds cache reads and cache writes; a write (row field cache_write, skills 0.51.0 Anthropic
commit on) costs 1.25x input (5-minute cache); from skills 0.52.0 (manifest.txt beside usage.jsonl) a Claude stage row of
Stages 3, 4, 7 and 8 writes the 1-hour cache at 2x (052-5; the row does not say which TTL it wrote)."""
import json, os, re, sys, collections
PRICE = {"gpt-6.2-sol": (2.00, 0.10, 10.00), "gpt-6.2-astra": (8.00, 0.40, 40.00),  # USD per 1M: input, cached input, output
         "claude-sonnet-5-5": (2.00, 0.10, 10.00), "claude-opus-5-5": (4.00, 0.20, 20.00),
         # Haiku 5.5 writes the Claude summaries (051-12): a prompt above 100K (cache reads and writes included) pays 5x
         "claude-haiku-5-5": (0.50, 0.05, 2.50)}
HAIKU_SHORT = (0.10, 0.01, 0.50)  # Haiku 5.5 up to 100K prompt (052-6 summarizes below it)
HOUR_STAGES = ("03-", "04-", "07-", "08-")  # 052-5


def hour_cache(path):
    """True when the run beside `path` is skills 0.52.0 or later (its Claude Stage 3/4/7/8 rows wrote the 1-hour cache)."""
    try:
        m = re.search(r"plugin_version=(\d+)\.(\d+)", open(os.path.join(os.path.dirname(path), "manifest.txt")).read())
    except OSError:
        return False
    return bool(m) and (int(m.group(1)), int(m.group(2))) >= (0, 52)


def cost(model, inp, cached, out, write=0, write_x=1.25):
    p = next((v for k, v in PRICE.items() if model and model.startswith(k)), None)
    if p is None:
        return None
    if model.startswith("claude-haiku-5-5") and inp <= 100_000:
        p = HAIKU_SHORT
    return ((inp - cached - write) * p[0] + cached * p[1] + write * write_x * p[0] + out * p[2]) / 1e6


def summarize(path):
    tot = collections.defaultdict(lambda: [0, 0, 0, 0, 0.0, 0])  # calls, input, cached, output, usd, unpriced calls
    hour = hour_cache(path)
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        hour_row = hour and r.get("role") == "stage" and str(r.get("model")).startswith("claude-") \
            and str(r.get("stage", "")).startswith(HOUR_STAGES)
        c = cost(r.get("model"), r.get("input", 0), r.get("cached", 0), r.get("output", 0), r.get("cache_write", 0),
                 2.0 if hour_row else 1.25)
        for key in ((r.get("stage"), r.get("role", "")[:9]), ("all", "all")):
            t = tot[key]
            t[0] += 1; t[1] += r.get("input", 0); t[2] += r.get("cached", 0); t[3] += r.get("output", 0)
            if c is None:
                t[5] += 1
            else:
                t[4] += c
    return tot


if __name__ == "__main__":
    tot = summarize(sys.argv[1])
    for (stage, role), (n, i, c, o, usd, unp) in sorted(tot.items(), key=lambda kv: (str(kv[0][0]), kv[0][1])):
        print(f"usage stage={stage} role={role} calls={n} input={i/1e6:.2f}M cached={c/1e6:.2f}M output={o/1e6:.3f}M usd~{usd:.2f}"
              + (f" unpriced={unp}" if unp else ""))
