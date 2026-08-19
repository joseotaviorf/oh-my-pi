# Supply

## Ownership

**Data Owner:**
- alexandre.gimenez@quintoandar.com.br

**Data Steward:**
- alexandre.gimenez@quintoandar.com.br

## Overview

Supply represents all channels and products QuintoAndar uses to acquire property owners and generate new listings on the platform, covering both for-rent and for-sale contexts. It tracks the owner journey from initial lead capture through a six-stage funnel to the creation of the first active listing.

> **Supply Revamp (WIP):** Rene Descartes is rolling out a contact-centric model (`contact_info`, `intent` — lake tables `lead_contact_info`, `lead_intent` today). That slice is documented separately in [`supply_revamp.md`](supply_revamp.md). **This file remains the source of truth for production funnel analysis** (`obt_supply`, `fact_supply_events`) — do not mix revamp clean tables with legacy funnel metrics until the full revamp DW is in prod.

The lifecycle has six stages:
1. **Lead** — owner contact is registered (`cd_funnel_step = 'lead'`)
2. **Prospect** — lead is validated and prospecting begins (`cd_funnel_step = 'prospect'`)
3. **Qualified** — property is evaluated and considered eligible (`cd_funnel_step = 'qualified'`)
4. **AV Qualified** — property availability is confirmed (`cd_funnel_step = 'av_qualified'`)
5. **Opportunity** — lead is ready for listing activation (`cd_funnel_step = 'opportunity'`)
6. **First Listing** — the first property listing is created (`cd_funnel_step = 'first_listing'`)

Not all leads follow every stage. Leads may be discarded at any step, reprocessed through recovery flows, or accelerated by operations. RENT and SALE flows are tracked separately under the same model via `nm_business_context`.

## Related Metric Entities

- [FL (First Listings)](../metric_entities/first_listings_1p.md) — first-time published inventory (FL, First Listings 1P/3P) by supply source and business context.
- [Supply Funnel Conversions](../metric_entities/funnel_conversions_supply.md) — official adjacent-stage conversion rates (L2P, P2Q, Q2O, O2L) and non-adjacent funnel transitions on `obt_supply`.
- [Isaias Conversions](../metric_entities/isaias_conversions.md) — official Isaias session→opportunity (D2O) and session→first-listing (D2L) conversion rates (Total / Autonomous) and % escalation to Inside Sales, on the session-supply ledger.

## Glossary and Synonyms

- **Supply**, **captação**, **aquisição de proprietários** → the supply entity; use `dw_growth.obt_supply`
- **Lead** → an owner who expressed interest; earliest funnel stage (`cd_funnel_step = 'lead'`)
- **Prospect** → a lead under active qualification (`cd_funnel_step = 'prospect'`)
- **Oportunidade** (opportunity) → a qualified lead ready to list (`cd_funnel_step = 'opportunity'`)
- **Primeira captação**, **first listing** → moment the first listing is created (`cd_funnel_step = 'first_listing'`)
- **Descarte**, **discard** → a lead dropped from the funnel; reason in `dim_supply_discards.cd_discard_reason`
- **Reprocessamento**, **recovery** → a discarded lead re-entered into the funnel (`dim_supply_recovery_flow.tp_reprocessing`)
- **Rede**, **3P** → third-party acquisition channel (`nm_supply_source = '3P'`; `acquisition_origin = 'rede'`)
- **1P** → first-party acquisition (QuintoAndar-owned channels; `nm_supply_source = '1P'`)
- **CIQ** → in-house broker agent channel (`nm_supply_source = 'CIQ'`; `acquisition_origin = 'ciq'`)
- **IS**, **Inside Sales** → inside sales team; split into IS Outbound, IS Inbound, IS Expert in `acquisition_origin` and `planning_operation`
- **Capta Aí** → AI-assisted outbound acquisition channel (visible in `planning_operation`)
- **PP Multi** → multi-property owner program (`obt_supply.is_pp_multi_active`; `acquisition_origin` contains pp_multi variants)
- **Indica Aí**, **afiliado**, **referral** → affiliate referral program (`acquisition_origin = 'referrals'`)
- **Isaías**, **bot do proprietário** → agentic WhatsApp chatbot that qualifies and converts property owners from lead to opportunity (later published as first listings), running **end-to-end for every session**. In-scope Isaias sessions are isolated in the preprocessed table `datalake_supply_flows.isaias_session_attribution` (one row per session) — the primary entry point for all Isaias analysis. Raw session data lives in `datalake_sauron_clean.session`; Langfuse (`datalake_langfuse_clean`, tag `isaias_react`) is retained for **ad-hoc session-behaviour analysis only, never for conversion metrics**.
- **Isaias host / bot** → `isaias_session_attribution.bot` identifies the host: the standalone **Isaias** number or **Isaias inside Wall-E / Mora** (QuintoAndar's main WhatsApp number). Segment by `bot` when host-level breakdowns are needed.
- **Isaias-created lead** → a lead whose acquisition origin was Isaias itself; precise filter: `obt_supply.tp_origin_acquisition = 'isaias'` (equivalently `isaias_session_attribution.lead_acquisition_type = 'created_in_session'`). Note: `acquisition_origin` maps this to `'operations'` (grouped with other ops channels) — use `tp_origin_acquisition` for Isaias-specific analysis.
- **Isaias-retrieved lead** → a lead that existed before and was re-engaged by Isaias in a session, regardless of its acquisition origin; identified by `isaias_session_attribution.lead_acquisition_type = 'retrieved_lead'` (the resolved lead is in `resolved_lead_id`). A retrieved lead can have any `tp_origin_acquisition` value, including `'isaias'` (a lead Isaias originally created and later retrieved again).
- **Isaias touchpoint lead** → the union of created and retrieved: any lead that Isaias either originated or engaged at any point. A created lead can also be retrieved in a later session; the `isaias_session_attribution` ledger resolves the created / retrieved / touchpoint distinction through `lead_acquisition_type`.
- **Isaias Autonomous Conversion** → a conversion (opportunity or first_listing) that Isaias completed end-to-end with no human involvement. Filter: `obt_supply.tp_origin_conversion = 'isaias'`; in the ledger, the supply-level flag `isaias_autonomous_conversion = TRUE`.
- **Isaias Human Conversion** → a conversion where Isaias handled the session but an inbound human analyst closed it within 24 h of the session start. Ledger pattern: `tp_origin_conversion <> 'isaias' AND planning_operation = 'Inbound'` and the OPPORTUNITY event falls in `[ts_session_start, ts_session_start + INTERVAL '24' HOUR)`; autonomous takes priority (a supply is Human only if it is not Autonomous). In the ledger, the supply-level flag `isaias_human_conversion = TRUE`.
- **Total Isaias Conversion** → the sum of Autonomous + Human conversions, reported for both the opportunity and first_listing steps.
- **Transbordo**, **escalation** → handoff of a session to a human queue. Derived from the `department` field (Sauron / support-services join to `isaias_session_attribution`): a session is **escalated** when `department IS NOT NULL`, and **escalated to Inside Sales** specifically when `LOWER(department) LIKE '%is%'`.
- **RENT / SALE**, **aluguel / venda** → `nm_business_context` values; always filter when the question is modality-specific
- **acquisition_origin** → classifies HOW the lead entered the funnel (channel/product). Built from `nm_supply_source` and the acquisition-side user path (`dim_supply_user_path`, `id_level = 1`). Use for top-of-funnel breakdowns. **Never use this field to identify Isaias leads** — `'operations'` groups Isaias with other ops channels; use `tp_origin_acquisition = 'isaias'` instead.

#### acquisition_origin values

| Value | When |
|---|---|
| `rede` | `nm_supply_source = '3P'` or `tp_origin = 'supplyprocessor'` — third-party broker network |
| `ciq` | `nm_supply_source = 'CIQ'` or `tp_origin = 'consultantpwa'` — QuintoAndar in-house broker agents |
| `referrals` | Affiliate user attached (`sk_user_affiliate > -1`, excluding CIQ/rede paths) or `tp_origin = 'app'` — Indica Aí referral program |
| `ownerlanding` | `tp_origin IN ('facebookleads','ownerpwa','landingproowners','landing','facebook','i24','ios')` — owner-facing landing pages |
| `homelanding` | `tp_origin = 'home'` — QuintoAndar home page owner entry point |
| `ownerpropertyregistration` | `tp_origin IN ('ownerpropertyregistration','ownerhomeloggedin')` — logged-in owner property registration flows |
| `operations` | `tp_origin IN ('inbound','ownerconversionpwa','isaias')` — IS team or Isaias bot originated the lead |
| `crawler` | `tp_origin = 'humancrawler'` — manual web crawler prospection |
| `pricesuggestion` | `tp_origin = 'pricesuggestion'` — rent price calculator (generic) |
| `pricesuggestionhome` | `tp_origin = 'pricesuggestionhome'` — rent price calculator accessed from home page |
| `pricesuggestionsale` | `tp_origin = 'pricesuggestionsale'` — sale price calculator |
| `test` | `tp_origin = 'whatsapp'` — WhatsApp test channel (non-production) |
| `notmapped-*` | Catch-all for unmapped `tp_origin` values |

- **conversion_origin** → classifies HOW the lead converted to opportunity or first listing. Built from the conversion-side user path (`dim_supply_user_path` joined via `sk_conversion_user_path`). Answers "which team or channel closed this lead?" Use in combination with `operation_channel` for finer attribution.

#### conversion_origin values

| Value | When |
|---|---|
| `ciq` | `tp_origin IN ('admin_confirmation','portfolio_manager','consultantpwa')` — CIQ agent performed the conversion |
| `rede` | `tp_origin = 'supplyprocessor'` — third-party broker network closed the listing |
| `operations` | `nm_agent IS NOT NULL` (ops team assigned), or `tp_origin IN ('prime','owner_conversion','isaias')` — IS team or Isaias bot completed the conversion |
| `ownerpwa` | `tp_origin IN ('full_self_service','referral','ios')` — owner converted via self-service PWA with no ops involvement |
| `notmapped-*` | Catch-all for unmapped `tp_origin` values |

Note: `conversion_origin = 'operations'` includes Isaias-closed conversions. Use `tp_origin_conversion = 'isaias'` to isolate Isaias autonomous conversions.

- **company_report_origin** → the canonical channel label used in management dashboards. A CASE expression over `acquisition_origin`, `conversion_origin`, `operation_channel`, and media attributes (`medium`, `behavior_type`, `source`). The primary signal switches by funnel depth: for lead/prospect (`funnel_order < 3`) it reads `acquisition_origin`; for qualified+ (`funnel_order > 2`) it reads `conversion_origin`. This is the right field for channel-level reporting — prefer it over `acquisition_origin` or `conversion_origin` alone. Use `planning_cluster` when finer sub-segmentation is needed.

#### company_report_origin values

| Value | Conditions (representative; full logic in the obt_supply.sql report_origin CTE) |
|---|---|
| `Rede` | Conversion or acquisition origin is `rede` |
| `CIQ` | Conversion or acquisition origin is `ciq`, or ops with `operation_channel = 'ciq'` |
| `Inbound` | Ops conversion/acquisition with `operation_channel = 'is_inbound'` |
| `IS Expert` | Ops with `operation_channel = 'is_expert'` |
| `Capta Aí` | Ops with `operation_channel = 'capta_ai'` |
| `PP Multi` | Ops with `operation_channel IN ('asp','account_manager_pp_multi')`, or organic owner PWA with active PP Multi flag |
| `Backend` | Operations fallback (no specific `operation_channel` matched) |
| `Reprocessamento` | `tp_reprocessing != '-1'` — lead was re-entered after discard |
| `Owner PWA - Organic` | `acquisition_origin IN ('homelanding','ownerlanding','ownerpropertyregistration')` + SEO non-branded or organic behavior |
| `Owner PWA - CRM/Notification` | Same origins + `source = 'braze'` |
| `Owner PWA - Paid` | Same origins + non-organic paid behavior |
| `Owner PWA - Not Mapped` | Same origins, no media signal matched |
| `Price Calculator` | `acquisition_origin IN ('pricesuggestion','pricesuggestionhome')` |
| `Price Calculator - Sale` | `acquisition_origin = 'pricesuggestionsale'` |
| `Indica Aí - Agents` | `acquisition_origin = 'referrals'` + `affiliate_type = 'agent'` |
| `Indica Aí - General` | `acquisition_origin = 'referrals'` (non-agent affiliates) |
| `Doorman/B2B` | `acquisition_origin = 'referrals'` + `affiliate_type IN ('doorman','B2B Partner')` |
| `Partners` | `acquisition_origin = 'referrals'` + `affiliate_type = 'partner'` |
| `Other` | Catch-all |

- **planning_cluster** → a finer sub-segmentation of `company_report_origin` that splits Indica Aí affiliates by volumetry tier and Owner PWA / Price Calculator leads by paid media sub-channel. Computed in the final `SELECT` of `obt_supply` by enriching `company_report_origin` with `affiliate_volumetry` (from `affiliates_clusters` / `affiliate_volumetry_cluster`) and the `medium` field. Use `planning_cluster` for granular planning and cost allocation; use `company_report_origin` for aggregate dashboards.

#### planning_cluster sub-splits

| company_report_origin value | Sub-split added by planning_cluster |
|---|---|
| `Indica Aí - General` / `Indica Aí - Agents` | `_Novo Afiliado`, `_Top Afiliados`, `_Afiliados_Alto_Volume`, `_Afiliados Risco Fraude`, `_Baixo Volume` (by `affiliate_volumetry` tier) |
| `Owner PWA - Paid` | `_Display`, `_SEM non-branded`, `_Performance_Max`, `_Other Paid` (by `medium`) |
| `Price Calculator` / `Price Calculator - Sale` | `_CRM/Notification`, `_Organic`, `_Display`, `_SEM non-branded`, `_Performance_Max`, `_Other Paid` |
| All other values | Identical to `company_report_origin` |

- **planning_operation** → operational team grouping used for capacity planning. Built from `full_conversion_origin` (the `LAST_VALUE` of `conversion_origin` across all funnel steps for the supply, so it always reflects the final converting team) combined with `operation_channel`. The IS team is split into three distinct values here (Inbound, Outbound, IS Expert). Use for detailed IS sub-team breakdowns.

#### planning_operation values

| Value | When |
|---|---|
| `Inbound` | `full_conversion_origin = 'operations'` + `operation_channel = 'is_inbound'`, or `acquisition_origin = 'operations'` + `operation_channel = 'is_inbound'` |
| `Outbound` | Reprocessamento (`tp_reprocessing != '-1'`), `operation_channel = 'is_outbound'`, `nm_assigned_partner IS NOT NULL`, or operations fallback |
| `IS Expert` | `operation_channel = 'is_expert'` |
| `Capta Aí` | `operation_channel = 'capta_ai'` |
| `PP Multi` | `operation_channel IN ('asp','prime','account_manager_pp_multi')`, or organic owner PWA with active PP Multi flag |
| `CIQ` | `operation_channel = 'ciq'`, `full_conversion_origin = 'ciq'`, or `acquisition_origin = 'ciq'` |
| `Rede` | `full_conversion_origin = 'rede'` or `acquisition_origin = 'rede'` |
| `FSS` | `full_conversion_origin = 'ownerpwa'` with no ops override — full self-service |
| `Mercado Primário BH` | `operation_channel = 'primary_market_bh'` |
| `Mensageria` | `nm_assigned_partner = 'mensageria'` |
| `Not Mapped` | Catch-all |

- **planning_conversion** → same operational grouping as `planning_operation` but collapses all IS sub-teams (Inbound, Outbound, IS Expert) and Reprocessamento into a single `'IS'` bucket. Use when you need IS as a whole team without sub-team breakdowns.

#### planning_conversion values

| Value | Difference from planning_operation |
|---|---|
| `IS` | Replaces `Inbound`, `Outbound`, `IS Expert`, and Reprocessamento |
| `Capta Aí` | Identical |
| `PP Multi` | Identical |
| `CIQ` | Identical |
| `Rede` | Identical |
| `FSS` | Identical |
| `Mercado Primário BH` | Identical |
| `Mensageria` | Identical |
| `Not Mapped` | Identical |

### Services and Systems in the QuintoAndar Supply Flow

The supply funnel is powered by a set of microservices, each responsible for a distinct stage. The DW supply model (`fact_supply_events`, `obt_supply`) aggregates events from all of them via the `datalake_supply_flows` orchestration schema.

- **Rene Descartes** *(a.k.a. Rene)* — lead management service for first-party (1P) leads. Rene registers the moment an owner expresses interest and stores all acquisition-side metadata: marketing attribution (UTM, origin, affiliate type), property address, and business context (RENT / SALE). It also records lead-level disqualifications that happen before the prospect stage. Schema: `datalake_rene_descartes_clean`. Funnel stage: **lead entry and lead → prospect transition**. Key tables:
  - `house_lead` — one row per 1P lead; `id`, `id_lead_ebdb`, `ts_created`, `id_address`, `id_referred_by`
  - `house_lead_aud` — audit log of status changes; used to derive the lead's status history
  - `acquisition_misc_data` — JSON blob with UTM fields, campaign origin, affiliate type, and house_info (forRent / forSale flags)
  - `lead_rejection` — discard events generated by Rene (origin != 'PROSPECT'); joined via `id_house_lead = id_lead`

- **Wololo** — prospect orchestration service. Once a 1P lead converts to prospect, Wololo takes ownership: it manages the outbound contact lifecycle by tracking each contact round (attempts, call channel, call output) and the ops company responsible (`sales_company`). When `sales_company = 'olos'`, the actual dialing is delegated to the OLOS dialer (see below). Wololo is also the source for prospect-level disqualification. Schema: `datalake_wololo_clean`. Funnel stage: **prospect**. Key tables:
  - `prospect` — one row per prospect; `id`, `id_reference` (= `id_lead_ebdb`), `id_external` (= Rene lead ID), `status`, `sales_company`, `ts_created`, `ts_updated`
  - `contact` — individual contact attempts per prospect; `channel`, `call_output`, `ts_contacted`
  - `round` — grouping of contact attempts into rounds; `round_number`, `round_max_tries`
  - Join to supply: `wololo.id_reference = id_lead_ebdb`

- **OLOS Dialer** — outbound telephony system used by the IS Outbound team. When Wololo assigns a prospect to `sales_company = 'olos'`, OLOS executes and logs the actual calls. In `obt_supply`, the first call timestamp from `outbound_contact_attempts` determines whether a lead has `status = 'started prospecting'`. Schema: `datalake_olos_dialer`. Funnel stage: **prospect** (outbound contact tracking). Key tables:
  - `outbound_contact_attempts` — one row per call attempt; `id_lead`, `ts_call_started`; joined via `id_lead = id_lead_ebdb`
  - `outbound_mailing` — mailing assignment; `id_lead`, `sales_company`, `ts_created`
  - `outbound_last_contact` — latest contact snapshot per lead

- **Bob (Bob o Construtor)** — house draft management service. During the qualification stage, the ops agent (or Isaias) fills in the property details — pricing, blueprint, availability, owner and administrator info — which are stored as a draft in Bob. The draft carries a reference back to the original lead (`id_original_lead`). The draft identifier can also appear with the name of `id_house_draft`. When the lead converts to opportunity, Bob's draft data is promoted to create the actual house record on the main platform, generating the `id_house` used throughout the supply model. Schema: `datalake_bob_clean`. Funnel stage: **qualified → opportunity**. Key tables:
  - `house_draft` — one row per draft; `id`, `id_client_side`, `id_original_lead`, pricing JSON (rent, sale, condo), blueprint JSON (bedrooms, bathrooms, area), `status`, `ts_created`, `ts_updated`
  - `house_draft_aud` — audit log of draft changes
  - Join to supply: `bob.id_original_lead = id_lead` (via `datalake_supply_flows.conversion_lookup`)
  - `attribution_progress` — tracks owner confirmation progress during Bob lead attribution. To identify houses with pending confirmation from the owner use `status= 'WAITING_CONFIRMATION'`.
  - `location` — location information of house drafts. A house's address usually consists of the fields `address`, `number` and `complement` combined. Additional fields are also available.
  - Join to supply: `bob.id_house_draft = sk_lead` (via `dw_growth.obt_supply`)

- **Photojob** *(Photographer Job)* — records the photography session that is the operational event converting a qualified lead into an opportunity. When a photojob is scheduled for a property, the supply event transitions from `qualified` to `opportunity`. The table tracks photographer assignment, scheduled date, session lifecycle (accepted → started → photos uploaded → completed), and cancellation or problem events. Tables are in `datalake_ebdb_clean`. Funnel stage: **qualified → opportunity**. Key tables:
  - `photographer_job` — current snapshot; `id`, `id_house`, `status`, `ts_scheduled`, `ts_session_started`, `ts_photos_uploaded`
  - `photographer_job_aud` — full audit trail with revision tracking (`rev`, `revtype`); used for status transition analysis
  - Join to supply: `photographer_job.id_house = fse.sk_house`

- **Listing** *(listing_business_context)* — records the publication of a property listing, completing the supply funnel (opportunity → first_listing). A listing is created per house × business context (RENT or SALE) and has a lifecycle of statuses: `EDITING`, `PUBLISHED`, `UNPUBLISHED`. The transition to `PUBLISHED` is what the supply funnel counts as `cd_funnel_step = 'first_listing'`. Tables are in `datalake_ebdb_clean`. Funnel stage: **first_listing**. Key tables:
  - `listing_business_context` — current listing state; `id_house`, `business_context`, `status`, `ts_first_listing`
  - `listing_business_context_aud` — audit log of status changes over time
  - Join to supply: `listing_business_context.id_house = fse.sk_house`

- **supply_flows** *(datalake_supply_flows)* — the central orchestration schema that acts as the glue layer between all source systems and the DW supply model. It normalises events from Rene, Wololo, Bob, and EBDB into a single canonical event log consumed by `fact_supply_events` and `obt_supply`. Key tables:
  - `supply_events_tracking` — canonical event log; one row per supply event; columns: `funnel_step`, `business_event`, `ops_objective`, `ops_agent`, `ops_partner`, `ops_contact_medium`, `ts_event_adjusted`. The OPPORTUNITY timestamp from this table anchors the Isaias human-conversion 24 h window (see Critical Rules).
  - `leads_sks` — surrogate key registry for all leads across sources (1P / CIQ / 3P); `sk_supply_lead`, `id_lead`, `source`
  - `conversion_lookup` — maps each lead to its conversion outcome; `id_lead`, `business_context`, `id_house`, `has_listing`, `has_draft`, `supply_source`
  - `leads_1p` — enriched 1P lead base derived from Rene Descartes; used as input to prospect and qualified event pipelines

### Date anchoring

- **Coincident date conversion** *(default for all analyses)* → conversion metric anchored on the **date the conversion event occurred**, regardless of when the lead or session was created. A single day's conversion count aggregates all conversions that happened on that day, even if the underlying leads were born on different days. This is QuintoAndar's standard method — use it unless cohort is explicitly requested.
  - *Regular leads*: filter `obt.date` to the analysis window on the conversion-step rows (`cd_funnel_step IN ('opportunity', 'first_listing')`). Lead creation dates are not constrained.
  - *Isaias demand conversions*: anchor on `event_date` (the day the conversion occurred) in the ledger (Query 2 / Query 3). Conversions are attributed to the day they happened, regardless of when the session started.

- **Cohort conversion** *(use only when explicitly requested)* → conversion metric anchored on the **date the lead (or session) was created**. For a given cohort date, counts how many leads/sessions born on that date eventually converted — irrespective of when the conversion happened.
  - *Regular leads*: anchor on `obt.date` filtered to `cd_funnel_step = 'lead'`; join each lead's conversion rows without constraining `obt.date` on the conversion side. Rate = conversions from that cohort ÷ leads created on that date.
  - *Isaias*: anchor on `session_date` (= `DATE(ts_session_start)`) in the ledger. For each session-creation date, count how many of those sessions produced a conversion (valid attribution = the last session each lead appears in). Rate = conversions ÷ sessions created on that date.

## Tables

| You need... | Use this table |
|-------------|----------------|
| End-to-end funnel analysis with all dimensions pre-joined | `dw_growth.obt_supply` (`obt`) — one row per lead × funnel step × business context. Start here for most analyses. Full refresh daily. |
| Grain-level events joined to raw dimensions | `dw_growth.fact_supply_events` (`fse`) — one row per supply event. Surrogate keys (`sk_*`) link to all dim tables. |
| Lead acquisition metadata (IDs, UTM attribution, lead type) | `dw_growth.dim_acquisition_lead` (`dal`) — one row per lead × source × business context, deduped to latest event. |
| Funnel step labels and type classification | `dw_growth.dim_funnel_step` (`dfs`) — lookup mapping `bk_funnel_step` to `cd_funnel_step`, `tp_business_event`, `funnel_order`. |
| Operations context (agent, partner, contact medium) | `dw_growth.dim_supply_operation_flow` (`dsof`) — deduped ops metadata per business key. |
| Discard reason descriptions | `dw_growth.dim_supply_discards` (`dsd`) — maps discard reason codes to human-readable descriptions. |
| Isaias in-scope sessions + attribution (primary entry point) | `datalake_supply_flows.isaias_session_attribution` (`isa`) — one preprocessed row per in-scope Isaias session (both hosts). Columns: `id_sauron_session`, `id_langfuse_session`, `id_sss_session`, `resolved_lead_id`, `lead_acquisition_type`, `bot`, `has_reschedule_event`, `ts_session_start`. Isolates all Isaias sessions and resolves lead attribution — **start here for every Isaias analysis**. Join to supply via `resolved_lead_id` and the `sk_chat_session` session path (see ledger, Query 2). |
| Isaias raw session data (source_environment, department) | `datalake_sauron_clean.session` (`sau`) — one row per Sauron session; source of `source_environment` (a descriptive attribute, not an Isaias identifier) and `department` (used for escalation). Join: `CAST(sau.id AS VARCHAR) = isa.id_sauron_session`. `datalake_chatbot.sessions` is an enriched view over the same session data; both work — prefer `isaias_session_attribution` as the backbone. |
| Isaias session behaviour (Langfuse — ad-hoc only) | `datalake_langfuse_clean.traces` (`t`) / `datalake_langfuse_clean.observations` (`o`) — session traces and node-level events. **Ad-hoc session-behaviour analysis only — never used for conversion, funnel, or escalation metrics.** Filter `CONTAINS(t.tags, 'isaias_react')` and `t.environment = 'prod'`; bridge to sessions via `isa.id_langfuse_session = t.id_session`. Observations have integer `year` / `month` partitions (always apply both). |

**Critical rules:**
- **`datalake_supply_flows.isaias_session_attribution` is the backbone for all Isaias metrics.** It is a preprocessed table (one row per in-scope session) that isolates every Isaias session across both hosts and resolves lead attribution — do not re-derive session scoping from `source_environment` or from Langfuse. `source_environment` (from `datalake_sauron_clean.session`) is now a descriptive attribute only, **not** an Isaias identifier; never filter Isaias sessions with a `source_environment` list or `LIKE '%isaias%'`.
- **Langfuse is ad-hoc only.** `datalake_langfuse_clean.traces` / `observations` are used for session-behaviour exploration only — **never for conversion, funnel, or escalation metrics**. There are no per-session feature flags to extract and no node-based step detection in the metric path. When exploring behaviour, filter `CONTAINS(t.tags, 'isaias_react')` (the current host tag) and `t.environment = 'prod'`, and always apply the integer `year` / `month` partitions on `observations`. Bridge to sessions via `isaias_session_attribution.id_langfuse_session = t.id_session`.
- **`sk_chat_session` in `obt_supply` is VARCHAR** (built from `COALESCE(id_chat_session, '-1')`); the sentinel `'-1'` means no session. The ledger links supply events to sessions by two keys, both resolved through `isaias_session_attribution`: the **session path** (`obt.sk_chat_session = isa.id_sauron_session`) and the **resolved-lead path** (`isa.resolved_lead_id`). Both are unioned before attribution.
- **Three Isaias lead populations — never conflate them.** They are resolved by `isaias_session_attribution.lead_acquisition_type`:
  - *Created*: `tp_origin_acquisition = 'isaias'` / `lead_acquisition_type = 'created_in_session'` (bot originated the lead). These also appear as `acquisition_origin = 'operations'` — that field is too broad for Isaias-specific queries.
  - *Retrieved*: `lead_acquisition_type = 'retrieved_lead'` (bot re-engaged a pre-existing lead, regardless of origin). For conversion-side attribution: `tp_origin_conversion = 'isaias'`.
  - *Touchpoint* (union): a lead is "touched" by Isaias if it was created **or** retrieved in a session. A created lead can be retrieved again later — the populations overlap.
- **Session-based metrics use the UNION ALL event-ledger pattern.** Queries that compute `sessions → conversions` rates union two event types per session: `session_start` (one row per session, the denominator) and `conversao` (one row per session × converted supply, the numerator). See Golden Query 2.
- **Valid attribution = the last session each lead appears in.** Build the lead → session candidate set from both attribution keys (`resolved_lead_id` and the `sk_chat_session` session path), then keep only the most recent session per lead via `ROW_NUMBER() OVER (PARTITION BY lead_id ORDER BY ts_session_start DESC) = 1`. This prevents a single conversion being credited across multiple sessions that touched the same lead.
- **Two conversion types — Autonomous and Human.** For each attributed supply at `opportunity` / `first_listing`:
  - *Autonomous*: `tp_origin_conversion = 'isaias'` → supply-level flag `isaias_autonomous_conversion`.
  - *Human*: `tp_origin_conversion <> 'isaias' AND planning_operation = 'Inbound'` and the OPPORTUNITY event falls within 24 h of the session start → supply-level flag `isaias_human_conversion`. Autonomous takes priority: a supply is Human only when it is not Autonomous (`BOOL_OR(is_human) AND NOT BOOL_OR(is_autonomous)`).
  - *Total* = Autonomous + Human.
- **The conversion-time anchor is the OPPORTUNITY event from `supply_events_tracking`, not `obt.ts_event`.** CTE: `SELECT id_lead_ebdb, business_context, MIN(ts_event_adjusted) FROM datalake_supply_flows.supply_events_tracking WHERE funnel_step = 'OPPORTUNITY' GROUP BY 1, 2`. Human-conversion window: `ct.ts_event_adjusted >= isa.ts_session_start AND ct.ts_event_adjusted < isa.ts_session_start + INTERVAL '24' HOUR`.
- **Escalation is derived from `department`.** Join `isaias_session_attribution` to `datalake_sauron_clean.session` (support-services routing) and read `department`: a session is escalated when `department IS NOT NULL`, and escalated **to Inside Sales** when `LOWER(department) LIKE '%is%'`.
- **`obt_supply.sk_lead` equals `id_lead_ebdb` in source systems.** When joining `obt_supply` to raw source tables (Wololo via `id_reference`, OLOS via `id_lead`, `supply_events_tracking` via `id_lead_ebdb`, Rene via `id_lead_ebdb`), use `sk_lead` as the equivalent of `id_lead_ebdb`. This equivalence is used explicitly in `conversion_time` joins: `ct.id_lead_ebdb = obt.sk_lead`.
- **Isaias conversion deduplication key is `(sk_supply, nm_business_context)` — never include `cd_funnel_step`.** A single supply can appear at both `opportunity` and `first_listing` funnel steps; including `cd_funnel_step` in a `COUNT(DISTINCT ...)` key double-counts it. Always use `CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)` as the composite key when counting converted supplies in Isaias ledger queries.
- `obt_supply` has no partition columns — filter on `obt.date` (a `DATE` column) for time-bounded queries (table is full-refresh daily). Use `DATE '...'` literals, e.g. `obt.date >= DATE '2026-01-01'`.

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) for **official** first-listing volume and supply-funnel conversion rates. The bullets below are **component** metrics for ad-hoc analysis on `obt_supply` and Isaias sessions.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| FL, First Listings 1P/3P | [FL (First Listings)](../metric_entities/first_listings_1p.md) |
| L2P, P2Q, Q2O, O2L and non-adjacent supply funnel conversions | [Supply Funnel Conversions](../metric_entities/funnel_conversions_supply.md) |
| Isaias D2O / D2L conversion rates (Total / Autonomous) and % escalation to IS | [Isaias Conversions](../metric_entities/isaias_conversions.md) |

### Component / exploratory metrics

- **Lead volume** (`COUNT(DISTINCT obt.sk_supply)` where `cd_funnel_step = 'lead'`, by `nm_business_context`)
- **Lead → Opportunity conversion rate** (`COUNT_IF(cd_funnel_step = 'opportunity') / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0)`)
- **Lead → First Listing conversion rate** (`COUNT_IF(cd_funnel_step = 'first_listing') / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0)`)
- **Active leads by channel** (grouped by `acquisition_origin` or `company_report_origin`)
- **Discard rate by funnel step** (rows with a discard key joined to `dim_supply_discards`, by `cd_funnel_step`)
- **Recovery volume** (`COUNT` of leads with non-sentinel `sk_recovery` in `fact_supply_events`)
- **Isaias-created lead volume** (`COUNT(DISTINCT sk_supply)` where `tp_origin_acquisition = 'isaias'` and `cd_funnel_step = 'lead'`)
- **Isaias-retrieved lead volume** (`COUNT(DISTINCT sk_supply)` for leads with `isaias_session_attribution.lead_acquisition_type = 'retrieved_lead'`, resolved via `resolved_lead_id`)
- **Isaias touchpoint lead volume** (union of created + retrieved; deduplicate on `sk_supply`)
- **Isaias Sessions Volume** — count of distinct in-scope Isaias sessions: `COUNT(DISTINCT id_langfuse_session)` over `session_start` events in the ledger. Every session is end-to-end. Segment by `bot` for host-level breakdowns.
- **Isaias Autonomous Conversion volume** — supplies Isaias converted end-to-end. Ledger: `event_type = 'conversao' AND isaias_autonomous_conversion` (i.e. `tp_origin_conversion = 'isaias'`), counting `opportunity` / `first_listing`; deduplicate on `CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)`.
- **Isaias Human Conversion volume** — supplies Isaias handled but an inbound analyst closed within 24 h. Ledger: `event_type = 'conversao' AND isaias_human_conversion` (i.e. `tp_origin_conversion <> 'isaias' AND planning_operation = 'Inbound'` and OPPORTUNITY within 24 h of session start, and not Autonomous); same dedup key.
- **Total Isaias Conversion volume** — Autonomous + Human, for both opportunity and first_listing.
- **Isaias Autonomous / Human / Total conversion rate** — the corresponding conversion volume ÷ Isaias Sessions Volume. Compute per `event_date` (coincident, default) — see Query 3.
- **Escalation to Inside Sales volume** (transbordo para IS) — sessions where `LOWER(department) LIKE '%is%'`.
- **Escalation to Inside Sales rate** (taxa de transbordo para IS) — Escalation to Inside Sales volume ÷ Isaias Sessions Volume.
- **Total Escalation volume / rate** (transbordo total) — sessions where `department IS NOT NULL`, ÷ Isaias Sessions Volume. See Query 4.

## Relationships with Other Entities

### Chatbot Sessions (N:1 — many supply events may share one Isaias session)

- Backbone: `datalake_supply_flows.isaias_session_attribution` (`isa`) — one row per in-scope Isaias session, already scoping both hosts and resolving lead attribution.
- Session path (leads created by Isaias): `obt_supply.sk_chat_session = isa.id_sauron_session` where `sk_chat_session != '-1'`
- Resolved-lead path (leads retrieved by Isaias): `isa.resolved_lead_id` with `isa.lead_acquisition_type = 'retrieved_lead'`
- Raw session attributes: join to `datalake_sauron_clean.session` via `CAST(sau.id AS VARCHAR) = isa.id_sauron_session` for `source_environment` (descriptive) and `department` (escalation)
- Langfuse (ad-hoc only): `isa.id_langfuse_session = t.id_session`, tag `isaias_react`

### 3P Supply (sub-funnel — drill-in for `acquisition_origin = 'rede'`)

- The `dw_3p_supply` schema is the granular model for the rede (third-party broker) channel — partner-submitted leads ingested via the BSP. See `business_entities/3p_supply.md`.
- Bridge via `obt_supply.sk_house = dw_3p_supply.fact_lead_3p_flows.sk_house` (filter `<> -1` on both sides).
- Use `obt_supply` for cross-channel funnel (1P / CIQ / 3P) and `dw_3p_supply` for partner / broker / BSP-reason analysis on rede leads.

### Region (N:1)

- `obt_supply.sk_region = dw_region.dim_region.sk_region`
- Geographic breakdown (city, neighborhood) of supply funnel

### House / Listing (N:1)

- `obt_supply.sk_house` links to the house entity; populated from QUALIFIED stage onward (`-1` before that)
- For house grain, listing versions, publication status, and first-listing filters, see [`business_entities/house_and_listing.md`](house_and_listing.md)
- For price changes during or after acquisition, see [`business_entities/pricing.md`](pricing.md)

## Dos and Don'ts

**Do:**
- **Default date horizon: current year to date.** When no date range is specified, always filter from `DATE '{{current_year}}-01-01'` to the current date (e.g. `obt.date >= DATE '2026-01-01'` for the year 2026). Only use a different horizon when the user explicitly provides a specific date, period, or range.
- **Default to coincident date for all conversion analyses** — both regular lead conversions and Isaias demand conversions. Only switch to cohort when the user explicitly asks for a cohort view.
- For **Isaias coincident date** conversions, anchor on `event_date` (the day the conversion occurred) in the ledger (Query 2 / Query 3). This is the standard date axis for Isaias session-level conversion reporting.
- For **Isaias cohort** conversions (only when explicitly requested), anchor on `session_date` (= `DATE(ts_session_start)`) instead, grouping sessions by creation date and measuring which of those sessions eventually produced a conversion — rather than attributing conversions to the day they occurred.
- For **regular lead coincident date** conversions, filter `obt.date` to the analysis window on conversion-step rows (`cd_funnel_step IN ('opportunity', 'first_listing')`), without constraining the lead creation date.
- For **regular lead cohort** conversions (only when explicitly requested), anchor on `obt.date` filtered to `cd_funnel_step = 'lead'` and join each lead's conversion rows without constraining `obt.date` on the conversion side.
- Use `dw_growth.obt_supply` as the primary table — it has all dimensions pre-joined and business logic computed (`acquisition_origin`, `conversion_origin`, `company_report_origin`, `planning_operation`)
- Always filter `nm_business_context` when the question is modality-specific (`'RENT'` or `'SALE'`)
- Use `company_report_origin` or `planning_operation` for channel/product breakdowns that match management dashboards — these are the canonical channel labels
- Use `funnel_order` (integer 1–6) to sort or compare funnel stages; do not rely on alphabetical ordering of `cd_funnel_step`
- Start every Isaias analysis from `datalake_supply_flows.isaias_session_attribution` — it already scopes in-scope sessions across both hosts and resolves lead attribution. Do not scope Isaias via `source_environment` or Langfuse.
- To measure Isaias as an **acquisition channel** (leads it created), filter `obt_supply.tp_origin_acquisition = 'isaias'` (equivalently `lead_acquisition_type = 'created_in_session'`)
- To measure Isaias **conversion attribution**, filter `obt_supply.tp_origin_conversion = 'isaias'` for autonomous conversions, or use `planning_operation = 'Inbound'` (within 24 h of session start) for human conversions
- To measure Isaias as a **re-engagement channel** (leads from other sources it recovered), use `isaias_session_attribution.lead_acquisition_type = 'retrieved_lead'` (resolved via `resolved_lead_id`)
- To measure **total Isaias influence** (touchpoint), union the created and retrieved populations and deduplicate on `sk_supply` before aggregating
- When computing session-to-conversion rates, use the UNION ALL event-ledger pattern (see Query 2); valid attribution is the last session each lead appears in — no lead is counted across multiple sessions
- Report Isaias conversion impact with the two conversion types: **Autonomous** (`tp_origin_conversion = 'isaias'`) and **Human** (`tp_origin_conversion <> 'isaias' AND planning_operation = 'Inbound'` within 24 h; not Autonomous), and their sum **Total** — for both opportunity and first_listing. See Query 3 for the full computation
- Use Langfuse (`datalake_langfuse_clean`, tag `isaias_react`) only for ad-hoc session-behaviour exploration — never for conversion, funnel, or escalation metrics

**Don't:**

- Don't classify a table as **just rent** or **just sale** unless the linked business entity **explicitly** documents that scope for that `schema.table` — do not infer from `dw_rent` / `dw_sale` / `nm_business_context` column names. Do not use **“RENT only” / “SALE only”** for table scope.
- Don't use cohort date anchoring unless the user explicitly asks for it — coincident date is the default for all supply conversion analyses (both regular leads and Isaias).
- Don't mix cohort and coincident anchors within the same analysis — doing so produces lead/conversion counts from different time bases that are not comparable.
- Don't conflate Isaias-created leads (`tp_origin_acquisition = 'isaias'`), Isaias-retrieved leads (`lead_acquisition_type = 'retrieved_lead'`), and Isaias touchpoint leads (union of both) — each answers a different question
- Don't use `acquisition_origin = 'operations'` to identify Isaias leads — it groups Isaias with other operations channels; use `tp_origin_acquisition = 'isaias'` for precision
- Don't confuse `acquisition_origin` (how the lead entered the funnel) with `conversion_origin` (how it converted) — they answer different questions
- Don't join on `sk_chat_session` without first excluding the `'-1'` sentinel — it will create false matches across all unmatched leads
- Don't use `QUALIFY` syntax in Trino — it is a Spark-only construct; rewrite deduplication as a subquery with `ROW_NUMBER()` in a CTE
- Don't join `fact_supply_events` rows directly to `obt_supply` rows without awareness of grain — `fact_supply_events` has one row per event while `obt_supply` is full-refresh and pre-aggregated; mixing them can fan out counts

## Golden Queries

### Query 1 — Funnel breakdown by channel and business context

**Date anchor: coincident date (default).** Filters `obt.date` to the analysis window on all funnel steps — a given day's counts reflect whatever events occurred on that day, regardless of when the lead was originally created. For cohort analysis (only when explicitly requested), filter `obt.date` only on the `cd_funnel_step = 'lead'` rows to define the cohort, then remove the date filter on conversion-step rows to capture all subsequent conversions for those leads.

```sql
SELECT
    obt.nm_business_context,
    obt.acquisition_origin,
    obt.cd_funnel_step,
    obt.funnel_order,
    COUNT(DISTINCT obt.sk_supply) AS total_leads
FROM dw_growth.obt_supply AS obt
WHERE
    obt.date >= DATE '{start_date}'
    AND obt.date < DATE {end_date}
GROUP BY
    obt.nm_business_context,
    obt.acquisition_origin,
    obt.cd_funnel_step,
    obt.funnel_order
ORDER BY
    obt.nm_business_context,
    obt.acquisition_origin,
    obt.funnel_order
```

### Query 2 — Isaias session-supply ledger (full construction)

**Date anchor: coincident date (default).** The ledger exposes two date axes: `event_date` — the day a conversion occurred (the coincident axis, default) — and `session_date = DATE(ts_session_start)` — the day the session started (the cohort axis). For coincident-date reporting, group by `event_date`. For cohort reporting (only when explicitly requested), group by `session_date` and count which sessions born on each day eventually converted.

This is a query pattern built on the preprocessed table `datalake_supply_flows.isaias_session_attribution`. The final UNION ALL produces two event types per session: `session_start` (one row per session, the denominator for rates) and `conversao` (one row per session × converted supply, the numerator). Valid attribution is the last session each lead appears in. Two supply-level conversion flags are emitted: `isaias_autonomous_conversion` (`tp_origin_conversion = 'isaias'`) and `isaias_human_conversion` (inbound human closed within 24 h of session start; only when not autonomous).

> `{start_date}` is the session-window start (e.g. `2026-08-01`). The `obt_supply` lower bound (`{obt_start_date}`) is set a few days earlier to capture leads created shortly before their attributing session. **`isaias_session_attribution` has no historical backfill — data begins in August 2026, so `{start_date}` cannot be earlier than `2026-08-01`.**

```sql
WITH
-- Step 1: One row per in-scope session + Sauron source_environment / department
session_dim AS (
    SELECT
        d.id_sauron_session,
        d.id_langfuse_session,
        d.id_sss_session,
        d.resolved_lead_id,
        COALESCE(d.lead_acquisition_type, 'no_lead') AS lead_acquisition_type,
        d.bot,
        d.has_reschedule_event,
        ss.source_environment,
        ss.department,
        d.ts_session_start
    FROM datalake_supply_flows.isaias_session_attribution d
    LEFT JOIN datalake_sauron_clean.session ss
        ON CAST(ss.id AS VARCHAR) = d.id_sauron_session
    WHERE d.id_sauron_session IS NOT NULL
        AND d.ts_session_start >= from_iso8601_timestamp('{start_date}T00:00:00Z')
),

-- Step 2: Every lead-to-session appearance, from BOTH attribution keys
lead_session_candidates AS (
    SELECT resolved_lead_id AS lead_id, id_sauron_session AS id_session, ts_session_start
    FROM session_dim
    WHERE resolved_lead_id IS NOT NULL

    UNION

    SELECT
        CAST(o.sk_lead AS VARCHAR) AS lead_id,
        s.id_sauron_session AS id_session,
        s.ts_session_start
    FROM dw_growth.obt_supply o
    JOIN session_dim s
        ON o.sk_chat_session = s.id_sauron_session
    WHERE o.sk_chat_session IS NOT NULL
        AND o.sk_lead IS NOT NULL
        AND o."date" >= DATE {obt_start_date}   -- a few days before {start_date}
),

-- Step 3: Valid attribution = the LAST session each lead appears in
valid_attribution AS (
    SELECT lead_id, id_session
    FROM (
        SELECT
            lead_id, id_session,
            ROW_NUMBER() OVER (PARTITION BY lead_id ORDER BY ts_session_start DESC) AS rn
        FROM lead_session_candidates
    )
    WHERE rn = 1
),

-- Step 4: Opportunity registration time per lead + business context
conversion_time AS (
    SELECT
        id_lead_ebdb,
        business_context,
        MIN(ts_event_adjusted) AS ts_event_adjusted
    FROM datalake_supply_flows.supply_events_tracking
    WHERE funnel_step = 'OPPORTUNITY'
        AND id_lead_ebdb IS NOT NULL
    GROUP BY 1, 2
),

-- Step 5: Attributed opportunity / first-listing rows (one per funnel step / context) + OBT attributes
conv_rows AS (
    SELECT
        sd.id_sauron_session, sd.id_langfuse_session, sd.id_sss_session,
        sd.lead_acquisition_type, sd.bot, sd.has_reschedule_event, sd.source_environment, sd.department, sd.ts_session_start,
        CAST(o.sk_lead AS VARCHAR) AS lead_id,
        o.sk_supply,
        o.nm_business_context,
        o.cd_funnel_step,
        o."date" AS event_date,
        o.city_group,
        o.cd_discard_reason,
        o.discard_funnel_step,
        o.operation_channel,
        o.company_report_origin,
        o.planning_cluster,
        o.tp_origin_acquisition,
        o.tp_origin_conversion,
        o.planning_operation,
        (o.tp_origin_conversion = 'isaias') AS is_autonomous,
        (
            o.tp_origin_conversion <> 'isaias'
            AND o.planning_operation = 'Inbound'
            AND ct.ts_event_adjusted >= sd.ts_session_start
            AND ct.ts_event_adjusted <  sd.ts_session_start + INTERVAL '24' HOUR
        ) AS is_human
    FROM dw_growth.obt_supply o
    JOIN valid_attribution va
        ON CAST(o.sk_lead AS VARCHAR) = va.lead_id
    JOIN session_dim sd
        ON va.id_session = sd.id_sauron_session
    LEFT JOIN conversion_time ct
        ON o.sk_lead = ct.id_lead_ebdb
        AND o.nm_business_context = ct.business_context
    WHERE o.cd_funnel_step IN ('opportunity', 'first_listing')
        AND o."date" >= DATE {obt_start_date}
),

-- Step 6: Supply-level validity: a supply is a valid conversion if any of its rows qualifies
valid_supply AS (
    SELECT
        id_sauron_session, sk_supply, nm_business_context,
        BOOL_OR(is_autonomous) AS supply_autonomous,
        (BOOL_OR(is_human) AND NOT BOOL_OR(is_autonomous)) AS supply_human
    FROM conv_rows
    GROUP BY id_sauron_session, sk_supply, nm_business_context
),

-- Step 7: Union the two event types
events AS (
    -- session_start: one per session (denominator)
    SELECT
        'session_start' AS event_type,
        CAST(ts_session_start AS DATE) AS event_date,
        id_sauron_session, id_langfuse_session, id_sss_session,
        CAST(ts_session_start AS DATE) AS session_date,
        source_environment,
        department,
        bot,
        has_reschedule_event,
        lead_acquisition_type,
        resolved_lead_id AS lead_id,
        CAST(NULL AS VARCHAR)  AS nm_business_context,
        CAST(NULL AS VARCHAR)  AS funnel_step,
        CAST(NULL AS VARCHAR)  AS sk_supply,
        CAST(NULL AS VARCHAR)  AS city_group,
        CAST(NULL AS VARCHAR)  AS cd_discard_reason,
        CAST(NULL AS VARCHAR)  AS discard_funnel_step,
        CAST(NULL AS VARCHAR)  AS operation_channel,
        CAST(NULL AS VARCHAR)  AS company_report_origin,
        CAST(NULL AS VARCHAR)  AS planning_cluster,
        CAST(NULL AS VARCHAR)  AS tp_origin_acquisition,
        CAST(NULL AS VARCHAR)  AS tp_origin_conversion,
        CAST(NULL AS VARCHAR)  AS planning_operation,
        CAST(NULL AS BOOLEAN)  AS isaias_autonomous_conversion,
        CAST(NULL AS BOOLEAN)  AS isaias_human_conversion
    FROM session_dim

    UNION ALL

    -- conversao: one per opportunity / first listing of a valid conversion (numerator)
    SELECT
        'conversao' AS event_type,
        cr.event_date,
        cr.id_sauron_session, cr.id_langfuse_session, cr.id_sss_session,
        CAST(cr.ts_session_start AS DATE) AS session_date,
        cr.source_environment,
        cr.department,
        cr.bot,
        cr.has_reschedule_event,
        cr.lead_acquisition_type,
        cr.lead_id,
        cr.nm_business_context,
        cr.cd_funnel_step AS funnel_step,
        cr.sk_supply,
        cr.city_group,
        cr.cd_discard_reason,
        cr.discard_funnel_step,
        cr.operation_channel,
        cr.company_report_origin,
        cr.planning_cluster,
        cr.tp_origin_acquisition,
        cr.tp_origin_conversion,
        cr.planning_operation,
        vs.supply_autonomous AS isaias_autonomous_conversion,
        vs.supply_human       AS isaias_human_conversion
    FROM conv_rows cr
    JOIN valid_supply vs
        ON cr.id_sauron_session = vs.id_sauron_session
        AND cr.sk_supply = vs.sk_supply
        AND cr.nm_business_context = vs.nm_business_context
    WHERE vs.supply_autonomous OR vs.supply_human
)

SELECT *
FROM events
```

**Key columns in the ledger:**
- **`event_type`**: `'session_start'` (one per in-scope session — the rate denominator) or `'conversao'` (one per session × valid converted supply — the numerator).
- **`lead_acquisition_type`**: `'created_in_session'`, `'retrieved_lead'`, or `'no_lead'` — resolved by `isaias_session_attribution`.
- **`bot`**: host (standalone Isaias vs Isaias inside Wall-E / Mora).
- **`isaias_autonomous_conversion`** / **`isaias_human_conversion`**: supply-level conversion flags (autonomous takes priority — a supply is Human only if not Autonomous).
- **`event_date`** vs **`session_date`**: conversion day vs session-start day. Coincident-date reporting (default) groups by `event_date`; cohort reporting groups by `session_date`.

### Query 3 — Isaias conversion types by day (Autonomous / Human / Total)

**Date anchor: coincident date (default).** Groups by `event_date` — each row aggregates conversions that occurred on that day. For cohort reporting (only when explicitly requested), group by `session_date` instead. Build all CTEs from Query 2 through `events`, then aggregate. Rates use the in-scope session count (all sessions are end-to-end).

```sql
-- (Include all CTEs from Query 2 through `events`, then:)

SELECT
    event_date AS data_referencia,   -- coincident (default); use session_date for cohort
    COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END) AS total_sessions,

    -- Autonomous: Isaias completed the conversion end-to-end (tp_origin_conversion = 'isaias')
    COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND isaias_autonomous_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)
    END) AS autonomous_conversions,

    -- Human: inbound analyst closed within 24 h of session start (not autonomous)
    COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND isaias_human_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)
    END) AS human_conversions,

    -- Total = autonomous + human
    COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)
    END) AS total_conversions,

    ROUND(CAST(COUNT(DISTINCT CASE WHEN event_type = 'conversao' AND isaias_autonomous_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS autonomous_rate,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN event_type = 'conversao' AND isaias_human_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS human_rate,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN event_type = 'conversao' AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS total_rate
FROM events
GROUP BY event_date
ORDER BY data_referencia DESC
```

> Filter the `conversao` branch by `funnel_step` (`'opportunity'` or `'first_listing'`) for step-specific conversion counts, or by `bot` for host-level breakdowns.

### Query 4 — Isaias escalation (transbordos) by day

**Escalation is derived from the `department` field**, joining `isaias_session_attribution` to `datalake_sauron_clean.session` (support-services routing). A session is escalated when `department IS NOT NULL`, and escalated **to Inside Sales** when `LOWER(department) LIKE '%is%'`. Denominator is total in-scope sessions.

```sql
SELECT
    DATE(isa.ts_session_start) AS data_referencia,
    isa.bot,
    COUNT(DISTINCT isa.id_langfuse_session) AS total_sessions,
    COUNT(DISTINCT CASE WHEN ss.department IS NOT NULL THEN isa.id_langfuse_session END)          AS escalated_sessions,
    COUNT(DISTINCT CASE WHEN LOWER(ss.department) LIKE '%is%' THEN isa.id_langfuse_session END)   AS escalated_inside_sales,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN ss.department IS NOT NULL THEN isa.id_langfuse_session END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT isa.id_langfuse_session), 0), 4)                                  AS escalation_rate,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN LOWER(ss.department) LIKE '%is%' THEN isa.id_langfuse_session END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT isa.id_langfuse_session), 0), 4)                                  AS escalation_is_rate
FROM datalake_supply_flows.isaias_session_attribution isa
LEFT JOIN datalake_sauron_clean.session ss
    ON CAST(ss.id AS VARCHAR) = isa.id_sauron_session
WHERE isa.ts_session_start >= from_iso8601_timestamp('{start_date}T00:00:00Z')
GROUP BY 1, 2
ORDER BY 1 DESC
```

