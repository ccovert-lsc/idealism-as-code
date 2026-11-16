# 0018. Structured Source Fetching for Event Discovery

**Date:** 2026-11-16
**Status:** Accepted

## Context

A self-hosted agent (n8n + Ollama) discovers local events matching a set of personal interest criteria and proposes them for approval. The original discovery path was entirely search-engine-mediated: a long list of `site:X keyword` style queries issued against a self-hosted search backend (itself proxying general web search engines), with an LLM asked to extract and score candidate events from the raw search snippets returned.

Yield from this path was very low — a handful of events found over several weeks, heavily skewed toward whichever single source happened to rank best in search results. Widening the query list made things worse, not better: general web search engines rate-limit automated query volume aggressively, and funneling more queries through the same search backend just exhausted that rate limit faster.

A separate, manually-run research pass over the same time window — fetching known event-listing pages directly instead of going through a search engine — surfaced substantially more relevant events in a single pass. That gap was the trigger for this decision.

## Decision

Treat "search the web for events" and "fetch a known event-listing page directly" as two different techniques with different reliability characteristics, and prefer direct fetching wherever a source is already known, reserving the search-engine path for genuinely unknown or long-tail sources.

The underlying observation: several event-listing platforms render their event data as structured JSON embedded in the server-rendered HTML response (titles, ISO 8601 timestamps, venue, cost — not just prose a search engine would see). That data can be extracted directly and far more reliably than asking an LLM to reconstruct the same facts from a lossy search-result snippet. No headless browser or JS execution was needed for any source tried — the structured data was present in the plain HTTP response every time.

Workflow shape (n8n "Discovery" workflow):
- The original search-engine query step is kept unchanged as one input branch.
- New parallel branches fetch known event-listing sources directly via a plain HTTP GET with a standard browser user-agent, then pull the embedded structured records out with a small regex-based extractor (not a general HTML/DOM parser, since the payload in each case is machine-generated JSON rather than semantic markup).
- Each branch normalizes its output to the same `{title, url, content}` shape the rest of the pipeline already expects, so the downstream LLM relevance-scoring step — and the single place the actual interest criteria live — doesn't change at all regardless of which path found a given event.
- All branches merge, deduplicated by URL, before that scoring step.
- Each source's published crawl rules (`robots.txt`) were checked before adding it. One otherwise-attractive candidate source was excluded specifically because it opted out of AI-crawler traffic; its exclusion was respected rather than routed around.

## Consequences

- Event discovery volume increased substantially in the same run, without any further widening of the search-engine query list — confirming that query count was never the actual bottleneck; source selection was.
- New maintenance burden: each direct-fetch source's extractor is coupled to that specific page's current JSON/markup shape, and will break silently (producing zero or partial results from that branch) if the source redesigns its page. The scoring step has no way to distinguish "this source changed its markup" from "no new events this week," so a silent regression here needs to be checked deliberately rather than assumed absent.
- Rate-limit pressure moved off the shared search backend, since each direct fetch now hits its own source's servers once per run rather than adding to a shared, already-constrained query budget.
- The specific sources wired in this way aren't enumerated here — they were chosen opportunistically to close the volume gap and will keep changing. The durable thing worth recording is the pattern (parse known structured sources directly; fall back to search only for the unknown long tail), not the current source list.

## Alternatives considered

**Headless browser / JS rendering per source**: Not needed for any source tried — the structured event data was present in the first HTTP response every time, no client-side rendering required. Adopting a browser runtime for this would add real operational weight (memory, another failure mode) for no observed benefit; worth revisiting only if a future source turns out to require it.

**Official per-source APIs**: Likely available for some of these platforms. Not pursued for this pass, since getting direct-fetch working cheaply against the existing page structure was the immediate goal. Worth moving to an API per source if its page-scrape proves fragile over time — an API is a strictly more durable integration than parsing embedded JSON out of HTML.

**Further widening the search-engine query list**: The original approach, and the one this decision moves away from. Made the rate-limiting problem worse without closing the volume gap — the bottleneck was never how many queries were issued, but how much a search engine's indexed snippet can actually tell an LLM about an event it only crawled shallowly.
