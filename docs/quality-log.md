# Quality log

## 2026-10-27 — S1-mini baseline (llama.cpp, real model, real prompt)

Command: llama-server, S1-mini Q4_K_M, ChatML prompt rendered exactly as `LlamaPrompt.render`,
empty think block, temperature 0, top_k 1, 512 max tokens.

Input: hand-written 140-word raw-ASR transcript with fillers, a false start, a self-correction
("one hundred twenty five dollars — no wait, one hundred twenty five thousand"), prices,
a spoken list, and tech terms.

Measured: 141 tokens in 1.75 s (~80 tok/s on M1).

Output (verbatim):
"Okay, so for the sync tomorrow I need you to start with the paywall screen, because that's where we're losing people, like about 30% drop off on step two. Also, we need to add the new pricing page with three tiers: basic at $20, pro at $60, and enterprise. Call us. Then make sure the next JS app still builds with the Tanstack Query upgrade and the Tailwind config, the one that broke last week. Also, send the notes to Morgan and Priya by Thursday, and include the updated budget of $125,000. And make it clear that the deadline is October 31."

Passed: self-correction resolved to $125,000; 30%; $20/$60; October 31; fillers "um/uh/you know" removed; meaning intact; no hallucinated content; list kept as a list.
Failed / needs pipeline work: "Okay, so" opener retained; "next JS" not "Next.js"; "Tanstack" not "TanStack" (both are TextLexicon tier-0 jobs, bypassed in this isolated check); no paragraph formatting (TextLineFormat not in this path).

Verdict: S1-mini itself is good enough to build on. Remaining defects are in our deterministic layers, not the model.
