# ChatWise UI Design Language + OpenRouter API Reference

## PART A — ChatWise visual design (replicate in SwiftUI)

ChatWise imitates native macOS conventions. Colors pixel-sampled from official material.

### Window anatomy
- Hidden title bar, full-size content view. Left sidebar (~255 pt) full-height; traffic lights inside sidebar top. Toolbar (~40-44 pt) spans content pane only, white with 1px hairline bottom border (#EFEFEF).
- **Settings window clones macOS System Settings**: centered bold "Settings" title, horizontal icon-tab strip (line icon above ~12pt label per tab). Selected tab = rounded-rect gray pill (#E4E4E7, radius ~8) with accent-blue icon+label. Below a hairline: master-detail (narrow source list ~160-180pt + form detail pane) on pages that need it; +/- bordered buttons at list bottom.

### Palette
| Token | Light | Dark |
|---|---|---|
| Content background | #FFFFFF | #222125 |
| Sidebar background | #F2EDEC (warm stone) | ~#28272B |
| Selected sidebar row | #E1DDDC, radius ~6 | — |
| Settings chrome | #EFEFF4 | #222125 |
| Tab pill / segmented track | #E4E4E7 (zinc-200) | #3F3F46 (zinc-700) |
| Input/bubble fill | #F4F4F5 | #343337 |
| Hairlines | #E4E4E7 / #EFEFEF | #3F3F46 |
| Primary text | #0A0A0B | #F9F9F9 |
| Secondary text | #707074 | #96969C |
| Accent blue | #4E80EE | #2464EB |

Grays = Tailwind zinc (chrome) + stone (sidebar); accent = blue-600 family. Use custom Color values, not system grays.

### Typography & components
- Inter / system sans. Body ~15px lh 1.6; form labels ~13px semibold; helper text ~12px secondary gray UNDER the label, above the field. NO uppercase section headers — hierarchy from weight and spacing.
- Filled rounded input fields (#F4F4F5 light / #343337 dark, radius 6-8, subtle 1px border), iOS-style blue toggles right-aligned, blue checkboxes, popup buttons with blue dual-chevron caps.
- Secondary things collapse into small gray pills. Icons: 1.5px-stroke line icons ~16-18pt (Lucide-like → use SF Symbols light/regular weight).
- Hairlines instead of boxes, whitespace instead of dividers, single blue accent.

## PART B — OpenRouter API: openai/gpt-oss-120b:free

```
POST https://openrouter.ai/api/v1/chat/completions
Authorization: Bearer sk-or-v1-...
Content-Type: application/json
HTTP-Referer: <app url>   (optional attribution)
X-Title: VoiceInput       (optional)
```

Request:
```json
{
  "model": "openai/gpt-oss-120b:free",
  "messages": [{"role":"system","content":"..."},{"role":"user","content":"..."}],
  "temperature": 0.3,
  "max_tokens": 1024,
  "reasoning": { "effort": "low" },
  "stream": false
}
```
- Free endpoint supported params (exact): include_reasoning, max_tokens, reasoning, seed, stop, temperature, tool_choice, tools. **NO response_format on :free** — prompt for plain text output.
- Use reasoning effort "low" + low temperature for cleanup latency.
- Response: choices[0].message.content (may also carry .reasoning — ignore it). finish_reason normalized stop|length|tool_calls|content_filter|error. usage.cost = 0.
- Context 131,072 tokens. Moderated endpoint.

Rate limits (June 2026): 20 req/min across all :free models; 50 req/day if <$10 lifetime credits purchased, 1,000 req/day after a $10 lifetime purchase. 402 possible on negative balance. On 429/503 respect Retry-After header, else exponential backoff. Error JSON: {"error":{"code":429,"message":"...","metadata":{}}}.

Design consequence for the app: every dictation = 1 polish request → free tier fine; on 429 fall back to unpolished transcript and surface a subtle notice.
