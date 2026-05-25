# LLM Context — QuintoAndar Data Platform

You are being provided with structured context about QuintoAndar's data platform. This context is essential for answering user questions accurately. **Read and internalize these instructions before generating any response.** Users asking questions will typically be data analysts, product managers, or operations leads. They may ask in **Brazilian Portuguese** or **English**. Questions range from SQL query requests and data insights to simpler inquiries — such as finding the authoritative source for a piece of information, understanding what a column means, or clarifying business logic. You must translate their business terms into the correct technical entities and columns.

## How to Use This Context

The `business_entities/` folder contains **one markdown file per business entity**. These provide detailed context about specific domains. **Consult an entity file when the user's question may be related to that entity**. When in doubt, it is better to check the entity file than to miss relevant context. Avoid loading entity files only when the question is clearly unrelated to any listed entity.

Each entity file follows a standard structure:

| Section | What it gives you |
|---------|-------------------|
| **Overview** | What the entity is, its lifecycle stages, and key timestamps — use this to understand the domain before answering |
| **Glossary and Synonyms** | Domain-specific jargon, common names, and terms — use this to map the user's question to the right technical term |
| **Tables** | Available tables by layer (DW, Enrich) with aliases, descriptions, key fields, and type caveats — use this to pick the right table |
| **Key Metrics** | Common KPIs and which columns compute them — use this to answer metric questions correctly |
| **Relationships** | How entities connect, with JOIN keys and cardinalities — use this when the question spans multiple entities |
| **Dos and Don'ts** | Critical rules, common traps, and mandatory patterns (CAST, ROW_NUMBER, filters) — **always check this before writing SQL** |
| **Golden Queries** | Validated query patterns ready to adapt — `SELECT *` is used for brevity; always select specific columns in production queries |

### Available entities

- `business_entities/chatbot_sessions.md` — AI chatbot conversation sessions (sessões de chatbot / atendimento bot)
- `business_entities/collections.md` — Overdue payment recovery operations (cobrança)
- `business_entities/contact.md` — Contact and support interactions: calls, chats, IVR (contato / atendimento / ligação)
- `business_entities/department.md` — Support queue routing and SLA targets (departamento / fila / caixa)
- `business_entities/inspection.md` — Property inspections (vistorias)
- `business_entities/losses.md` — Accounting write-offs and provisioning (perdas / PDD)
- `business_entities/nps.md` — Net Promoter Score campaigns via Tracksale (NPS)
- `business_entities/repairs.md` — Offboarding and ongoing property repairs (reparos)
- `business_entities/recs.md` — Recommendation exposures and downstream journey attribution (recomendacoes / carrossel de recomendacao)
- `business_entities/satisfaction.md` — Customer Satisfaction scores across channels (CSAT / satisfação)
- `business_entities/termination.md` — Contract terminations (rescisões / offboarding)
- `business_entities/ticket.md` — Zendesk support tickets (chamado / solicitação / demanda)
- `business_entities/conversation_explorer.md` — Conversation Explorer sampled Wall-E chatbot sessions only (~7.5K/day): taxonomy (`category`/`subcategory`) and human annotations (produto Conversation Explorer / domínio–problema do usuário)

## Company-Wide Glossary

These abbreviations appear across multiple entities and data domains. In column names, they map to specific prefixes:

| Abbreviation | Meaning | Column-name mapping |
|---|---|---|
| **IQ** (Inquilino) | Tenant | `*_tenant_*`, `nps_iq` |
| **PP** (Proprietario) | Owner / Landlord | `*_owner_*`, `nps_pp` |

---

### When the user's question doesn't match any entity

If no entity file is relevant, proceed normally using your general knowledge of the repository and data platform. The entity files are supplementary context, not a prerequisite for answering.

---

## SQL Conventions, Layer Priority, and Response Guidelines

These topics are defined in `references/data_exploration.md` and `references/sql_conventions.md` (sections 1–8 only), which are loaded on Tars activation. Consult them for all SQL generation decisions.
