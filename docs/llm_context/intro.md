# LLM Context — QuintoAndar Data Platform

You are being provided with structured context about QuintoAndar's data platform. This context is essential for answering user questions accurately. **Read and internalize these instructions before generating any response.** Users asking questions will typically be data analysts, product managers, or operations leads. They may ask in **Brazilian Portuguese** or **English**. Questions range from SQL query requests and data insights to simpler inquiries — such as finding the authoritative source for a piece of information, understanding what a column means, or clarifying business logic. You must translate their business terms into the correct technical entities and columns.

## How to Use This Context

This file is the **single source of truth for how to look for data context.** Other files (`.cursor/rules/data_exploration.mdc`, `.cursor/subagents/data_analyst.md`, etc.) must not redefine this order — they only point you here. Whenever you need context about the data, follow this:

1. **DataHub first.** Query the DataHub MCP and search for the **Data Product(s)** related to the user's terms — it is the authoritative catalog for schema, columns, glossary, and golden queries. Always start here.
2. **Entity files if you need more.** If DataHub returns nothing relevant, or you need business rules, domain nuance, or an official metric's formula not captured there, the two supplementary layers below are at your disposal. **You decide** which is most adequate for the question — read one, the other, or both.

**Knowing the difference between the two layers tells you what each is good for:**

- **Business entities** (`business_entities/`) — carry **business rules and broader characteristics of the data** (domain, tables, grain, joins, component metrics). Reach for them when you need **wide context** or to build an ad-hoc query.
- **Metric entities** (`metric_entities/`) — **objective and narrow**: they explain **how to calculate an official indicator the company tracks** (scope, exact formula, canonical filter, weight sources).

Both are useful and there is **no fixed precedence** between them — let the question decide when to read each. When in doubt, it is better to check more than to miss relevant context.

### Primary source — DataHub catalog

DataHub MCP tools (your first stop — see "How to Use This Context" above):

| MCP tool | Use it to |
|---|---|
| `search(query=<entity_or_synonym>, entity_types=["DATA_PRODUCT","DATASET"])` | Find the Data Product or datasets for an entity |
| `get_entities(urns=[<urn>])` | Get descriptions, glossary terms, owners, and linked assets |
| `list_schema_fields(urn=<dataset_urn>)` | Enumerate columns with types and descriptions |
| `get_dataset_queries(urn=<dataset_urn>)` | Retrieve validated golden queries |

### Supplementary source — entity MD files

The `business_entities/` folder contains **one markdown file per business entity** with business rules, mandatory dos/don'ts, JOIN recipes, and edge cases not yet encoded in DataHub. Consult an entity file **after DataHub** when the user's question requires domain patterns or nuances. Every entity file includes a **DataHub catalog** section with direct links to its DataHub **Data Product** and **golden query** (`Query` entity). CI publishes catalog metadata from the MD via [`generate_and_push_datahub_entities.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py) and [`load_collections_context.py`](../../dags/governance/datahub_business_context/load_collections_context.py); some domains also list dataset schema links inline.
The roles of the two layers and when to reach for each are covered in "How to Use This Context" above; this section covers their **file structure**.

The `metric_entities/` folder contains **one markdown file per official metric**, thin on schema (it delegates that to its linked business entity) and thick on the metric's definition, scope, exact calculation, canonical filter, and weight sources.

Each **business entity** file follows a standard structure:

| Section | What it gives you |
|---------|-------------------|
| **Overview** | What the entity is, its lifecycle stages, and key timestamps — use this to understand the domain before answering |
| **Related Metric Entities** | Plain list of the official metric(s) that build on this entity — see "Cross-link sections" below |
| **DataHub catalog** | Direct UI links to the Data Product and golden Query entity; dataset links (CI-published from the MD on merge to master) |
| **Glossary and Synonyms** | Domain-specific jargon, common names, and terms — use this to map the user's question to the right technical term |
| **Tables** | Available tables by layer (DW, Enrich) with aliases, descriptions, key fields, and type caveats — use this to pick the right table |
| **Key Metrics** | Common KPIs and which columns compute them — use this to answer metric questions correctly |
| **Relationships** | How entities connect, with JOIN keys and cardinalities — use this when the question spans multiple entities |
| **Dos and Don'ts** | Critical rules, common traps, and mandatory patterns (CAST, ROW_NUMBER, filters) — **always check this before writing SQL** |
| **Golden Queries** | Validated query patterns ready to adapt — `SELECT *` is used for brevity; always select specific columns in production queries |

Each **metric entity** file follows a different, leaner structure focused on the official metric rather than the schema:

| Section | What it gives you |
|---------|-------------------|
| **Overview** | What the official metric is, which product it applies to, and how it differs from the naive/component version |
| **Related Business Entities** | Plain list of the business entity (or entities) that own the underlying tables, columns, and grain — **start there for schema**, this file does not repeat it; see "Cross-link sections" below |
| **Glossary and Synonyms** | Names and terms used to ask for this metric — use this to map the user's question to the right metric entity |
| **Scope** | What is included and excluded (journeys, segments, campaign purposes) — defines the metric's boundary |
| **Calculation** | The exact official calculation (weighting, aggregation), the **Canonical Filter**, and **Nuances** (weight sources, fallback, dedup) — this **overrides** any generic logic in the business entity |
| **Dos and Don'ts** | Traps specific to the official metric (e.g. don't hardcode weights, don't pool journeys directly) |
| **Golden Queries** | The single canonical query that produces the official metric — references the business-entity component pattern instead of re-teaching it |
| **Superset Golden Assets** | Reference Superset datasets/dashboards to use as the canonical starting point for data manipulation on this metric in Superset |

> **Cross-link sections** (`Related Business Entities` / `Related Metric Entities`): these are plain lists of the **names** of related entities — no paths or descriptions. To open one, look it up in the "Available entities" / "Available metric entities" index below: business entities live in `business_entities/`, metric entities in `metric_entities/`, one file per entity. A business entity points *up* to the official metrics built on it; a metric entity points *down* to the business entities it draws its schema from.

> **Role contract (avoid redundancy):** a business entity documents *schema + component/generic metrics*; a metric entity documents *one official metric's calculation*. When both touch the same domain (e.g. NPS), the metric entity links to the business entity rather than copying its tables, columns, or component queries.


### Available entities

- `business_entities/3p_demand.md` — 3P Demand — Broker XP: 3P demand funnel (Visit → Offer → CCV) and Buyer Prospects (TSC / 3P Demand / 3P Lead Gen / CQA)
- `business_entities/3p_supply.md` — 3P Supply — Broker XP: funnel for capturing leads from commercial partners up to the first listing, covering the entire 3P supply journey (e.g., BSP, partner leads, partner network, and marketplace). Related to partner operations (see also `broker_xp.md` for details on the real estate and partner 3P Partners ecosystem).
- `business_entities/bank_reconciliation.md` — Bank reconciliation across billing, bank CNAB/statements, payment rails, and SAP (conciliação bancária / FinOps)
- `business_entities/accounting_funnel.md` — Accounting Funnel / Canudo Contábil (Accounting Straw): financial reconciliation between product systems and SAP, tie-out methodology (Straw vs Reverse Straw), ISA 315 assertions — completeness, correctness, temporality, compliance (canudo contábil / batida / conciliação contábil / SAP)
- `business_entities/broker_xp.md` — Partner real estate agencies (Brokers) and 3P Partners / Marketplace operation (Rede / 3P partners / Marketplace)
- `business_entities/chatbot_sessions.md` — AI chatbot conversation sessions (sessões de chatbot / atendimento bot)
- `business_entities/closing.md` — For Rent contract closing / CC2CS journey: draft → sent → signed (fechamento, assinatura de contrato)
- `business_entities/collections.md` — Overdue payment recovery operations (cobrança)
- `business_entities/contact.md` — Voice and chat contacts with support agents — Front Office interactions (BigFone, Twilio, Sauron) before ticket creation (contato / ligação / reserva / tarefa)
- `business_entities/conversation_explorer.md` — Conversation Explorer sampled Wall-E chatbot sessions only (~7.5K/day): taxonomy (`category`/`subcategory`) and human annotations (produto Conversation Explorer / domínio–problema do usuário)
- `business_entities/department.md` — Support queue routing and SLA targets (departamento / fila / caixa)
- `business_entities/fs-transact.md` — FS Transact — For Sale transaction funnel: EoF (OS → CCV → Closed Deal) and EoP (CCV → CRI → key delivery), 1P scope, Buyer Prospect, lead times by payment track, LegoContract contract analysis and assessment performance metrics (funil de transação de venda / CCV / Closed Deal / EoP / análise de contratos / LegoContract / assessments / Salesforce CDC event tables: `datalake_salesforce_clean.events_pendency` (Solicitações CRN), `datalake_salesforce_clean.events_received_document` (Solicitações de documentos), `datalake_salesforce_clean.events_incident` (Incidentes Legal Ops), `datalake_salesforce_clean.events_case_legal_ops` (Casos Legal Ops / due diligence).)
- `business_entities/evals.md` — Online LLM-as-a-judge evaluation scores of the Domi Platform AI agents (evals / avaliações / online evals)
- `business_entities/inspection.md` — Property inspections (vistorias)
- `business_entities/knowledge_base.md` — Operations help-article catalog used by customer support and the support bot (base de conhecimento / central de ajuda). Operations-facing context only, not a business source of truth.
- `business_entities/losses.md` — Accounting write-offs and provisioning (perdas / PDD)
- `business_entities/matthew.md` — Collections AI agent for tenants with open balances (agente Matthew / cobrança IA)
- `business_entities/nps.md` — Net Promoter Score campaigns via Tracksale (NPS)
- `business_entities/org_chart.md` — Public active workforce org chart: manager, job, cost center, Codex taxonomy, P&T teams (organograma / quadro ativo)
- `business_entities/payments.md` — Payment transactions across Checkout, Wall Street, and Vans (pagamentos / cobrança checkout)
- `business_entities/recovery_collections_fr_tenants.md` — Overdue debt recovery rate analytics for For-Rent tenants (recuperação / cobrança FR / wallet / recovery rate)
- `business_entities/repairs.md` — Offboarding and ongoing property repairs (reparos)
- `business_entities/recs.md` — Recommendation exposures and downstream journey attribution (recomendacoes / carrossel de recomendacao)
- `business_entities/search.md` — Search result impressions, CTR, ranking, and downstream journey attribution (busca / resultado de busca)
- `business_entities/satisfaction.md` — Customer Satisfaction scores across channels (CSAT / satisfação)
- `business_entities/salesforce_sst_pipeline.md` — Salesforce Single Station pipeline health: hourly volume, latency, CDC gaps, Appflow connector status, and contract quality checks in `datalake_sst_metrics` (pipeline SST / saúde do pipeline / Appflow / recovery flow)
- `business_entities/seo.md` — SEO performance, keyword clusters and demand top-of-funnel metrics (SEO / Search Engine Optimization)
- `business_entities/supply.md` — Property owner acquisition funnel from lead to first listing (captação / supply / aquisição de proprietários)
- `business_entities/ticket.md` — Zendesk support tickets — central anchor for Support & Services metrics (ticket / chamado / demanda)
- `business_entities/termination.md` — Contract terminations (rescisões / offboarding)
- `business_entities/visits.md` — Visit requests and scheduled property visits, capturing the full journey from visit intention to completion (agendamentos e realização de visitas a imóveis)

### Available metric entities

Official, named metrics. Each builds on one or more business entities (linked at the top of its file).

- `metric_entities/nps_fr.md` — NPS FR True: official For-Rent weighted NPS, with per-journey weighting and quarterly weights read from GSheets (NPS FR / NPS True / NPS oficial / NPS ponderado). Builds on `business_entities/nps.md`.

- `metric_entities/first_listings_1p.md` — FL 1P: official First Listings metric for 1P supply, counting unique properties/listings first published in the selected period for For Rent and For Sale in Brazil, with channel classification separating 1P from 3P/Rede supply. Builds on `business_entities/supply.md`.

- `metric_entities/funnel_conversions_supply.md` — Supply Funnel Conversions: cohort-based conversion rates between all stages of the supply acquisition funnel (L2P, P2Q, Q2O, O2L) plus non-adjacent transitions (P2O, P2L, Lead to Listing). Supports both RENT and SALE verticals with week-0 velocity variants. Builds on `business_entities/supply.md`.

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

These topics are defined in `.cursor/rules/data_exploration.mdc`, which is loaded automatically when the Data Analyst (TARS) subagent is active. Use `@tars` to activate exploration mode.

The **context-search order** (DataHub first, then business/metric entity files as needed) lives **here**, in "How to Use This Context" above — `data_exploration.mdc` does not redefine it. That rule owns SQL dialect/conventions, layer priority, response guidelines, and the repo-search fallback for verifying table columns when this route isn't enough (its "Finding Context" section — `dags/**/queries/*.sql` + `dags/**/metadata/*.yml`).
