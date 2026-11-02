# Tech dictionary audit

Source: `Packages/L2-Engines/catalog/tech-dictionary.json` — 687 entries, 3405 aliases.
Common-word list: 30000 tokens (wordfreq top 30000)

## Summary

- Alias collisions: **118**
- Duplicate canonical forms: **9**
- Common-word risk rows: **2215**
- Destructive aliases: **1334**
- Identity aliases: **561/3405** (16.5%)

## Alias collisions (top 25)

| alias | canonical | other owners |
| --- | --- | --- |
| `asus expect center` | ASUS ExpertCenter | ASUS ExpertCenter Pro ET900N G3 |
| `asus expect center` | ASUS ExpertCenter Pro ET900N G3 | ASUS ExpertCenter |
| `asus expertcenter` | ASUS ExpertCenter Pro ET900N G3 | ASUS ExpertCenter |
| `automatic speech recognition` | ASR | STT |
| `automatic speech recognition` | STT | ASR |
| `bash` | bash | .bash |
| `bearer token` | Access Token | Bearer Token |
| `bearer token` | Bearer Token | Access Token |
| `code review` | Code Review | code review |
| `code review` | code review | Code Review |
| `code-review` | Code Review | code review |
| `cpp` | C++ | .cpp |
| `css` | CSS | .css |
| `custom elements` | Custom Element | Web Components |
| `custom elements` | Web Components | Custom Element |
| `database query` | Query | SQL |
| `database query` | SQL | Query |
| `docker container` | Container | Docker |
| `docker container` | Docker | Container |
| `docker container` | Docker | Container |
| `dockerfile` | Docker | Dockerfile |
| `dockerfile` | Dockerfile | Docker |
| `go` | Go | .go |
| `go lang` | Go | Golang |
| `go lang` | Golang | Go |

Full list: `audit/collisions.csv` (118 rows).

## Duplicate canonicals

| canonical | count |
| --- | --- |
| code review | 2 |
| deepseek-v4-flash | 2 |
| dgx station | 2 |
| gb300 | 2 |
| moe | 2 |
| pull request | 2 |
| radeon 8060s | 2 |
| rtx 5080 | 2 |
| rtx pro 6000 | 2 |

## Common-word risk (top 30)

| alias | canonical | score | reason | pack |
| --- | --- | --- | --- | --- |
| `.bash` | .bash | 2 | single common word (canonical) | command |
| `.c` | .c | 2 | single common word (canonical) | core |
| `.cc` | .cc | 2 | single common word (canonical) | core |
| `.conf` | .conf | 2 | single common word (canonical) | core |
| `.cs` | .cs | 2 | single common word (canonical) | core |
| `.css` | .css | 2 | single common word (canonical) | web |
| `.go` | .go | 2 | single common word (canonical) | core |
| `.h` | .h | 2 | single common word (canonical) | core |
| `.html` | .html | 2 | single common word (canonical) | web |
| `.java` | .java | 2 | single common word (canonical) | core |
| `.js` | .js | 2 | single common word (canonical) | core |
| `.kt` | .kt | 2 | single common word (canonical) | core |
| `.less` | .less | 2 | single common word (canonical) | core |
| `.lock` | .lock | 2 | single common word (canonical) | core |
| `.md` | .md | 2 | single common word (canonical) | core |
| `.php` | .php | 2 | single common word (canonical) | core |
| `.rb` | .rb | 2 | single common word (canonical) | core |
| `.rs` | .rs | 2 | single common word (canonical) | core |
| `.sh` | .sh | 2 | single common word (canonical) | core |
| `.sql` | .sql | 2 | single common word (canonical) | core |
| `.swift` | .swift | 2 | single common word (canonical) | mobile |
| `.ts` | .ts | 2 | single common word (canonical) | core |
| `.txt` | .txt | 2 | single common word (canonical) | core |
| `.xml` | .xml | 2 | single common word (canonical) | core |
| `accessibility` | Accessibility | 2 | single common word | core |
| `Accessibility` | Accessibility | 2 | single common word (canonical) | core |
| `accessible` | Accessibility | 2 | single common word | core |
| `AMD` | AMD | 2 | single common word (canonical) | hardware |
| `angular` | Angular | 2 | single common word | web |
| `Angular` | Angular | 2 | single common word (canonical) | web |

Full list: `audit/common_word_risk.csv` (2215 rows).

## Destructive aliases (top 30)

| alias | canonical | reason |
| --- | --- | --- |
| `a p i key` | API Key | alias extends 'a p i' (API); suffix is dropped |
| `a w s lambda` | AWS Lambda | alias extends 'a w s' (AWS); suffix is dropped |
| `a100 gpu` | A100 | alias extends its own canonical; suffix is dropped |
| `accessible rich internet applications` | ARIA | alias extends 'accessible' (Accessibility); suffix is dropped |
| `actix rust` | Actix | alias extends its own canonical; suffix is dropped |
| `actix web` | Actix | alias extends its own canonical; suffix is dropped |
| `amazon web services lambda` | AWS Lambda | alias extends 'amazon web services' (AWS); suffix is dropped |
| `amd radeon 8060s` | Radeon 8060S | alias extends 'amd' (AMD); suffix is dropped |
| `angular app` | Angular | alias extends its own canonical; suffix is dropped |
| `angular application` | Angular | alias extends its own canonical; suffix is dropped |
| `angular framework` | Angular | alias extends its own canonical; suffix is dropped |
| `angular frontend framework` | Angular | alias extends its own canonical; suffix is dropped |
| `angular js` | Angular | alias extends its own canonical; suffix is dropped |
| `angular project` | Angular | alias extends its own canonical; suffix is dropped |
| `angular typescript` | Angular | alias extends its own canonical; suffix is dropped |
| `angular typescript framework` | Angular | alias extends its own canonical; suffix is dropped |
| `angular web framework` | Angular | alias extends its own canonical; suffix is dropped |
| `ansible automation` | Ansible | alias extends its own canonical; suffix is dropped |
| `anthropic ai` | Anthropic | alias extends its own canonical; suffix is dropped |
| `anthropic api` | Anthropic | alias extends its own canonical; suffix is dropped |
| `anthropic claude` | Claude | alias extends 'anthropic' (Anthropic); suffix is dropped |
| `anthropic claude model` | Claude | alias extends 'anthropic' (Anthropic); suffix is dropped |
| `apache http server` | Apache | alias extends its own canonical; suffix is dropped |
| `apache kafka` | Kafka | alias extends 'apache' (Apache); suffix is dropped |
| `apache server` | Apache | alias extends its own canonical; suffix is dropped |
| `api access token` | Access Token | alias extends 'api' (API); suffix is dropped |
| `api controller` | Controller | alias extends 'api' (API); suffix is dropped |
| `api endpoint` | API | alias extends its own canonical; suffix is dropped |
| `api key` | API Key | alias extends 'api' (API); suffix is dropped |
| `api rate limit` | Rate Limiting | alias extends 'api' (API); suffix is dropped |

Full list: `audit/destructive_aliases.csv` (1334 rows).

## Longest aliases (top 15)

| words | alias | canonical |
| --- | --- | --- |
| 7 | `u d q four k x l` | UD-Q4_K_XL |
| 7 | `r o c m s m i` | rocm-smi |
| 7 | `local host port five one seven three` | localhost:5173 |
| 6 | `you aren't gonna need it` | YAGNI |
| 6 | `rtx pro 6 0 0 0` | RTX PRO 6000 |
| 6 | `radeon eight zero six zero s` | Radeon 8060S |
| 6 | `local host five one seven three` | localhost:5173 |
| 6 | `kimmy k two point seven code` | Kimi K2.7 Code |
| 6 | `kimi k two point seven code` | Kimi K2.7 Code |
| 6 | `h t t p s secure` | HTTPS |
| 6 | `g l m four point five` | GLM-4.5 |
| 6 | `g l m five point two` | GLM-5.2 |
| 6 | `g l m five point three` | GLM-5.3 |
| 6 | `g l m five point one` | GLM-5.1 |
| 6 | `dot e n v dot local` | .env.local |

## Entries per pack

| pack | entries |
| --- | --- |
| ai-models | 87 |
| command | 47 |
| core | 308 |
| hardware | 62 |
| infra | 34 |
| mobile | 2 |
| python | 7 |
| rust | 9 |
| web | 131 |
