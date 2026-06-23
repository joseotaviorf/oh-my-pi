# Supply

## Overview

Supply represents all channels and products QuintoAndar uses to acquire property owners and generate new listings on the platform, covering both for-rent and for-sale contexts. It tracks the owner journey from initial lead capture through a six-stage funnel to the creation of the first active listing.

The lifecycle has six stages:
1. **Lead** — owner contact is registered (`cd_funnel_step = 'lead'`)
2. **Prospect** — lead is validated and prospecting begins (`cd_funnel_step = 'prospect'`)
3. **Qualified** — property is evaluated and considered eligible (`cd_funnel_step = 'qualified'`)
4. **AV Qualified** — property availability is confirmed (`cd_funnel_step = 'av_qualified'`)
5. **Opportunity** — lead is ready for listing activation (`cd_funnel_step = 'opportunity'`)
6. **First Listing** — the first property listing is created (`cd_funnel_step = 'first_listing'`)

Not all leads follow every stage. Leads may be discarded at any step, reprocessed through recovery flows, or accelerated by operations. RENT and SALE flows are tracked separately under the same model via `nm_business_context`.

## Related Metric Entities

- FL (First Listings)
- Supply Funnel Conversions

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
- **Isaías**, **bot do proprietário** → agentic WhatsApp chatbot for qualifying and converting property owners into first listings; sessions in `datalake_sauron_clean.session` (filter `source_environment` with the explicit list in Critical Rules — never use LIKE); qualification flags in `datalake_chatbot.isaias_conversational_flow`. There are three distinct Isaias lead populations:
- **Isaias-created lead** → a lead whose acquisition origin was Isaias itself; precise filter: `obt_supply.tp_origin_acquisition = 'isaias'`. Note: `acquisition_origin` maps this to `'operations'` (grouped with other ops channels) — use `tp_origin_acquisition` for Isaias-specific analysis.
- **Isaias-retrieved lead** → any lead that Isaias re-engaged in a session, regardless of its acquisition origin; identified by a matching row in `datalake_chatbot.isaias_conversational_flow` (`icf.id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)`). A retrieved lead can have any `tp_origin_acquisition` value, including `'isaias'` (a lead Isaias originally created and later retrieved again). Queries that specifically measure cross-channel re-engagement add the filter `tp_origin_acquisition != 'isaias'` explicitly to exclude Isaias's own prior leads.
- **Isaias touchpoint lead** → the union of created and retrieved: any lead that Isaias either originated or engaged at any point. A created lead can also be retrieved in a later session. Use `tp_origin_acquisition = 'isaias' OR EXISTS (ICF join)` for this broadest measure of Isaias influence.
- **Isaias SDR** (qualification-only mode) → Isaias qualifies the lead through the end of the prospect stage, then hands off to a human analyst who completes property data collection, pricing, and photo scheduling. Identified by `is_full_process = FALSE OR NULL` derived from the Langfuse `orchestrator_init` observation (see Critical Rules).
- **Isaias Full Process** (end-to-end mode) → Isaias autonomously manages the entire flow from lead to opportunity: collects property details, defines pricing, and schedules the photo session. Human handoff occurs only on error or explicit user request. Identified by `is_full_process = TRUE` derived from the Langfuse `orchestrator_init` observation.
- **Isaias-only conversion** (FP Only) → a subset of Full Process conversions where Isaias completed the entire flow autonomously, including photo scheduling and draft submission, with no human analyst involvement. Identified in `obt_supply` by `tp_origin_conversion = 'isaias'`, or in the ledger by `is_full_process = TRUE AND tp_origin_conversion = 'isaias' AND is_valid_attribution = TRUE`. Always a Full Process session — SDR sessions never produce `tp_origin_conversion = 'isaias'`.
- **Isaias Full Process + Escalation conversion** → the total conversion volume from Full Process sessions, encompassing both the Isaias-only (autonomous) subset and conversions completed by an inbound human analyst after escalation. Isaias-only is a strict subset: every Isaias-only conversion is also counted in FP+Escalation. Ledger pattern: `is_full_process = TRUE AND is_valid_attribution = TRUE AND (tp_origin_conversion = 'isaias' OR (is_converted_within_24h = TRUE AND planning_operation = 'Inbound'))`.
- **Isaias SDR conversion** → a conversion where Isaias SDR qualified the lead and the final conversion was completed by the inbound human analysts team within 24 h after the session. The conversion origin is always human (Inbound), never Isaias itself. Requires the ledger pattern: `is_full_process = FALSE AND is_converted_within_24h = TRUE AND is_valid_attribution = TRUE AND planning_operation = 'Inbound'`.
- **Transbordo**, **escalation** → handoff of a session to a human queue when Isaias cannot or should not continue autonomously. Two distinct types: (1) **transbordo para Inside Sales** (`escalate_when_qualified` node visited — Isaias determined the lead is qualified and hands off to Inbound analysts) and (2) **transbordo para outras filas** (`escalation_node` visited — non-IS queues such as support). Never conflate the two: each has its own volume and rate metric.
- **Sessão ociosa**, **idle session** → a Full Process session that reached no terminal state: no successful submission, no escalation (IS or other), and no disqualification. Computed as: `NOT has_successful_submission AND NOT has_inside_sales_esc AND NOT has_other_esc AND NOT has_disqualification`.
- **Disqualification** → a session where Isaias determined the lead or property does not meet eligibility criteria, triggering a `%.disqualification` Langfuse observation. The prefix varies per qualification step; always filter with `o.name LIKE '%.disqualification'` — the only Isaias Langfuse filter that requires LIKE rather than an exact match.
- **Successful Submission** → a Full Process session where Isaias autonomously completed the entire conversational flow and booked a photo session; confirmed by `Submission.post_clarification` observation with `json_extract_scalar(o.output, '$.photo_session_successfully_scheduled') = 'true'`.
- **RENT / SALE**, **aluguel / venda** → `nm_business_context` values; always filter when the question is modality-specific
- **acquisition_origin** → classifies HOW the lead entered the funnel (channel/product). Built from `nm_supply_source` and the acquisition-side user path (`dim_supply_user_path`, `id_level = 1`). Use for top-of-funnel breakdowns. **Never use this field to identify Isaias leads** — `'operations'` groups Isaias with other ops channels; use `tp_origin_acquisition = 'isaias'` instead.

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

  | Value | When |
  |---|---|
  | `ciq` | `tp_origin IN ('admin_confirmation','portfolio_manager','consultantpwa')` — CIQ agent performed the conversion |
  | `rede` | `tp_origin = 'supplyprocessor'` — third-party broker network closed the listing |
  | `operations` | `nm_agent IS NOT NULL` (ops team assigned), or `tp_origin IN ('prime','owner_conversion','isaias')` — IS team or Isaias bot completed the conversion |
  | `ownerpwa` | `tp_origin IN ('full_self_service','referral','ios')` — owner converted via self-service PWA with no ops involvement |
  | `notmapped-*` | Catch-all for unmapped `tp_origin` values |

  Note: `conversion_origin = 'operations'` includes Isaias-closed conversions. Use `tp_origin_conversion = 'isaias'` to isolate Isaias-only conversions.

- **company_report_origin** → the canonical channel label used in management dashboards. A CASE expression over `acquisition_origin`, `conversion_origin`, `operation_channel`, and media attributes (`medium`, `behavior_type`, `source`). The primary signal switches by funnel depth: for lead/prospect (`funnel_order < 3`) it reads `acquisition_origin`; for qualified+ (`funnel_order > 2`) it reads `conversion_origin`. This is the right field for channel-level reporting — prefer it over `acquisition_origin` or `conversion_origin` alone. Use `planning_cluster` when finer sub-segmentation is needed.

  | Value | Conditions (representative; full logic in `obt_supply.sql` `report_origin` CTE) |
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

  Key sub-splits added on top of `company_report_origin`:

  | `company_report_origin` | Sub-split added by `planning_cluster` |
  |---|---|
  | `Indica Aí - General` / `Indica Aí - Agents` | `_Novo Afiliado`, `_Top Afiliados`, `_Afiliados_Alto_Volume`, `_Afiliados Risco Fraude`, `_Baixo Volume` (by `affiliate_volumetry` tier) |
  | `Owner PWA - Paid` | `_Display`, `_SEM non-branded`, `_Performance_Max`, `_Other Paid` (by `medium`) |
  | `Price Calculator` / `Price Calculator - Sale` | `_CRM/Notification`, `_Organic`, `_Display`, `_SEM non-branded`, `_Performance_Max`, `_Other Paid` |
  | All other values | Identical to `company_report_origin` |

- **planning_operation** → operational team grouping used for capacity planning. Built from `full_conversion_origin` (the `LAST_VALUE` of `conversion_origin` across all funnel steps for the supply, so it always reflects the final converting team) combined with `operation_channel`. The IS team is split into three distinct values here (Inbound, Outbound, IS Expert). Use for detailed IS sub-team breakdowns.

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

  | Value | Difference from `planning_operation` |
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
- **Services and Systems in the QuintoAndar Supply Flow**

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

  - **Bob (Bob o Construtor)** — house draft management service. During the qualification stage, the ops agent (or Isaias, in Full Process mode) fills in the property details — pricing, blueprint, availability, owner and administrator info — which are stored as a draft in Bob. The draft carries a reference back to the original lead (`id_original_lead`). When the lead converts to opportunity, Bob's draft data is promoted to create the actual house record on the main platform, generating the `id_house` used throughout the supply model. Schema: `datalake_bob_clean`. Funnel stage: **qualified → opportunity**. Key tables:
    - `house_draft` — one row per draft; `id`, `id_client_side`, `id_original_lead`, pricing JSON (rent, sale, condo), blueprint JSON (bedrooms, bathrooms, area), `status`, `ts_created`, `ts_updated`
    - `house_draft_aud` — audit log of draft changes
    - Join to supply: `bob.id_original_lead = id_lead` (via `datalake_supply_flows.conversion_lookup`)

  - **Photojob** *(Photographer Job)* — records the photography session that is the operational event converting a qualified lead into an opportunity. When a photojob is scheduled for a property, the supply event transitions from `qualified` to `opportunity`. The table tracks photographer assignment, scheduled date, session lifecycle (accepted → started → photos uploaded → completed), and cancellation or problem events. Tables are in `datalake_ebdb_clean`. Funnel stage: **qualified → opportunity**. Key tables:
    - `photographer_job` — current snapshot; `id`, `id_house`, `status`, `ts_scheduled`, `ts_session_started`, `ts_photos_uploaded`
    - `photographer_job_aud` — full audit trail with revision tracking (`rev`, `revtype`); used for status transition analysis
    - Join to supply: `photographer_job.id_house = fse.sk_house`

  - **Listing** *(listing_business_context)* — records the publication of a property listing, completing the supply funnel (opportunity → first_listing). A listing is created per house × business context (RENT or SALE) and has a lifecycle of statuses: `EDITING`, `PUBLISHED`, `UNPUBLISHED`. The transition to `PUBLISHED` is what the supply funnel counts as `cd_funnel_step = 'first_listing'`. Tables are in `datalake_ebdb_clean`. Funnel stage: **first_listing**. Key tables:
    - `listing_business_context` — current listing state; `id_house`, `business_context`, `status`, `ts_first_listing`
    - `listing_business_context_aud` — audit log of status changes over time
    - Join to supply: `listing_business_context.id_house = fse.sk_house`

  - **supply_flows** *(datalake_supply_flows)* — the central orchestration schema that acts as the glue layer between all source systems and the DW supply model. It normalises events from Rene, Wololo, Bob, and EBDB into a single canonical event log consumed by `fact_supply_events` and `obt_supply`. Key tables:
    - `supply_events_tracking` — canonical event log; one row per supply event; columns: `funnel_step`, `business_event`, `ops_objective`, `ops_agent`, `ops_partner`, `ops_contact_medium`, `ts_event_adjusted`. The QUALIFIED timestamp from this table is the authoritative source for `is_converted_within_24h` (see Critical Rules).
    - `leads_sks` — surrogate key registry for all leads across sources (1P / CIQ / 3P); `sk_supply_lead`, `id_lead`, `source`
    - `conversion_lookup` — maps each lead to its conversion outcome; `id_lead`, `business_context`, `id_house`, `has_listing`, `has_draft`, `supply_source`
    - `leads_1p` — enriched 1P lead base derived from Rene Descartes; used as input to prospect and qualified event pipelines

- **Coincident date conversion** *(default for all analyses)* → conversion metric anchored on the **date the conversion event occurred**, regardless of when the lead or session was created. A single day's conversion count aggregates all conversions that happened on that day, even if the underlying leads were born on different days. This is QuintoAndar's standard method — use it unless cohort is explicitly requested.
  - *Regular leads*: filter `obt.date` to the analysis window on the conversion-step rows (`cd_funnel_step IN ('opportunity', 'first_listing')`). Lead creation dates are not constrained.
  - *Isaias demand conversions*: anchor on `data_referencia` (= `DATE(ts_created_session)`) in the ledger query (Query 7 / Query 8). Each session's conversions are attributed to the day the session started.

- **Cohort conversion** *(use only when explicitly requested)* → conversion metric anchored on the **date the lead (or session) was created**. For a given cohort date, counts how many leads/sessions born on that date eventually converted — irrespective of when the conversion happened.
  - *Regular leads*: anchor on `obt.date` filtered to `cd_funnel_step = 'lead'`; join each lead's conversion rows without constraining `obt.date` on the conversion side. Rate = conversions from that cohort ÷ leads created on that date.
  - *Isaias*: anchor on `DATE(ts_created_session)` in the ledger query. For each session-creation date, count how many of those sessions produced a conversion (apply `is_valid_attribution = TRUE`). Rate = conversions ÷ sessions created on that date.

## Tables

| You need... | Use this table |
|-------------|----------------|
| End-to-end funnel analysis with all dimensions pre-joined | `dw_growth.obt_supply` (`obt`) — one row per lead × funnel step × business context. Start here for most analyses. Full refresh daily. |
| Grain-level events joined to raw dimensions | `dw_growth.fact_supply_events` (`fse`) — one row per supply event. Surrogate keys (`sk_*`) link to all dim tables. |
| Lead acquisition metadata (IDs, UTM attribution, lead type) | `dw_growth.dim_acquisition_lead` (`dal`) — one row per lead × source × business context, deduped to latest event. |
| Funnel step labels and type classification | `dw_growth.dim_funnel_step` (`dfs`) — lookup mapping `bk_funnel_step` to `cd_funnel_step`, `tp_business_event`, `funnel_order`. |
| Operations context (agent, partner, contact medium) | `dw_growth.dim_supply_operation_flow` (`dsof`) — deduped ops metadata per business key. |
| Discard reason descriptions | `dw_growth.dim_supply_discards` (`dsd`) — maps discard reason codes to human-readable descriptions. |
| Isaias session-level data (contact, status, timestamps) | `datalake_sauron_clean.session` (`sau`) — one row per Sauron session. Filter on explicit `source_environment` values (see Critical Rules). Join to supply via `sk_chat_session` (session path) or via ICF (lead path). |
| Copilot Service session bridge | `datalake_copilot_service_clean.session` (`cs`) — links `id_sauron_session` (VARCHAR) to `id_external` (Langfuse session ID). Required to connect Sauron sessions to Langfuse traces and ICF rows. Join: `cs.id_sauron_session = CAST(sau.id AS VARCHAR)` and `cs.id_external = icf.id_langfuse_session`. |
| Isaias funnel qualification flags | `datalake_chatbot.isaias_conversational_flow` (`icf`) — one row per Langfuse session with boolean `has_*` flags per qualification step. Join to supply (retrieved path): `icf.id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)`. |
| Isaias session traces (Langfuse) | `datalake_langfuse_clean.traces` (`t`) — one row per Langfuse session; join to observations via `o.id_trace = t.id_trace`. Always filter `CONTAINS(t.tags, 'isaias')` and `t.environment = 'prod'`. Bridge to Sauron/supply via `datalake_copilot_service_clean.session` (`cs.id_external = t.id_session`). |
| Isaias node-level events, feature flags, escalations (transbordos), disqualifications (Langfuse) | `datalake_langfuse_clean.observations` (`o`) — one row per observation event; integer partitions `year` and `month` (always apply both). Extract feature flags from `orchestrator_init` output JSON via `json_extract_scalar(o.output, '$.flag_name')`; detect node visits via `BOOL_OR(o.name = '...')`; detect IS escalation (transbordo para IS) via `o.name = 'escalate_when_qualified'`; detect other-queue escalation via `o.name = 'escalation_node'`; detect disqualification via `o.name LIKE '%.disqualification'`. Always pair the LIKE with an explicit `o.name IN (...)` whitelist to prevent full table scans. |

**Critical rules:**
- `sk_chat_session` in `obt_supply` is **VARCHAR** (built from `COALESCE(id_chat_session, '-1')`). The sentinel `'-1'` means no session. The ledger uses two paths to link supply events to sessions: **session path** (`obt_session_filtered` where `sk_chat_session IS NOT NULL AND sk_chat_session != '-1'`, joined to the session directly) and **lead path** (`obt_lead_filtered` where `sk_lead IS NOT NULL AND sk_lead != '-1'`, joined via ICF). Both paths are UNION ALL'd in `unified_supply_events` before being joined to `base_sessions`.
- **`source_environment` filter — use explicit values, not LIKE.** The correct Isaias environments are: `'isaias_inbound'`, `'isaias_inbound_main'`, `'isaias_inbound_c2wa_acq_1'`, `'isaias_inbound_c2wa_acq_2'`, `'isaias_inbound_c2wa_retarg_1'`, `'isaias_inbound_c2wa_retarg_2'`, `'isaias_inbound_owner_landing'`, `'isaias_home'`, `'isaias_opr'`, `'isaias_calculadora'`, `'isaias_inbound_c2wa_camp_1'`, `'isaias_inbound_c2wa_camp_2'`, `'isaias_inbound_c2wa_camp_3'`, `'isaias_inbound_c2wa_camp_4'`.
- **Three Isaias lead populations — never conflate them:**
  - *Created*: `tp_origin_acquisition = 'isaias'` (bot originated the lead). These also appear as `acquisition_origin = 'operations'` — that field is too broad for Isaias-specific queries.
  - *Retrieved*: any lead present in `isaias_conversational_flow.id_lead_retrieved` (bot re-engaged a lead, regardless of its origin). To isolate cross-channel re-engagement (leads Isaias did not create), add `tp_origin_acquisition != 'isaias'`. For conversion-side attribution: `tp_origin_conversion = 'isaias'`.
  - *Touchpoint* (union): a lead is "touched" by Isaias if it was created by it **or** retrieved in a session. A created lead can be retrieved again later — the populations overlap.
- **Session-based metrics require the UNION ALL event-ledger pattern.** Queries that compute `sessions → conversions` rates use a `UNION ALL` of two event types per session: `inicio_sessao` (always present) and `conversao` (only when a lead/supply is linked). The denominator is always session count (`tipo_evento = 'inicio_sessao'`); the numerator counts distinct converted supply IDs (`tipo_evento = 'conversao'`). The `is_valid_attribution` flag must be `TRUE` in the numerator to avoid crediting multiple sessions for the same lead (only the most recent session touching a lead is valid). See Golden Query 7.
- **`is_full_process` must be derived from Langfuse, not from `icf`.** `isaias_conversational_flow.is_full_process` is incomplete for sessions before the field was consistently populated. The authoritative source is the `orchestrator_init` observation in Langfuse. Always compute it with this CTE and join via `cs.id_external = fps.id_session` (where `cs` is `datalake_copilot_service_clean.session`):
  > Set `{start_year}` and `{start_month}` to integer values from your analysis start date. Keep the Langfuse window short (days to a few weeks) — wide scans are expensive.
  ```sql
  full_process_sessions AS (
      SELECT
          t.id_session,
          COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process
      FROM datalake_langfuse_clean.observations o
      LEFT JOIN datalake_langfuse_clean.traces t ON o.id_trace = t.id_trace
      WHERE o.year = {start_year}
          AND o.month >= {start_month}
          AND CONTAINS(t.tags, 'isaias')
          AND t.environment = 'prod'
          AND o.name IN ('orchestrator_init')
      GROUP BY 1
  )
  ```
  `TRUE` = Full Process (end-to-end). `FALSE` or `NULL` = SDR mode. Always segment by this flag — SDR and Full Process have different expected funnel depths.
- **Querying flags and observations in Langfuse — three patterns.** All Isaias session behavior and feature flags live in `datalake_langfuse_clean.observations` (integer partitions: `year`, `month`) joined to `datalake_langfuse_clean.traces`. Always apply `o.year`, `o.month` partition filters and base trace filters `CONTAINS(t.tags, 'isaias')` and `t.environment = 'prod'`.
  1. **Feature flags from `orchestrator_init`** — scalar flags in the JSON `output` of the `orchestrator_init` observation. Extract with `json_extract_scalar(o.output, '$.flag_name')` and aggregate per session with `BOOL_OR(... = 'true')`. Known flags:
     - `is_draft_enabled` → Full Process mode (`TRUE` = FP, `FALSE`/`NULL` = SDR) — authoritative source for `is_full_process`
     - `is_pricing_negotiator_enabled` → new pricing negotiator agent active in session
     - `is_property_details_agent_enabled` → new property details agent active in session
  2. **Node presence / step detection** — whether a graph node was visited in the session. Use `BOOL_OR(o.name = 'NodeName.event_type')` aggregated by session. Always include a full `o.name IN (...)` whitelist to prevent full table scans. See Query 9 for the complete node list and their funnel step mappings.
  3. **Bridge to Sauron and supply** — `datalake_copilot_service_clean.session` is the required bridge: join `cs.id_external = t.id_session` (Langfuse side) and `cs.id_sauron_session = CAST(sau.id AS VARCHAR)` (Sauron side). For scoping by session window, pre-filter `datalake_copilot_service_clean.session` by `ts_created` and join to Langfuse traces via `t.id_session = cs.id_external`.
- **`is_valid_attribution` uses `last_session_retrieved`, not ROW_NUMBER.** For the session path (lead created in session): `TRUE` when `lsr.last_session IS NULL` (no retrieval ever recorded, so the originating session is always valid) OR when `lsr.last_session = id_sauron_session_varchar`. For the lead path (retrieved lead): `TRUE` only when `lsr.last_session = id_sauron_session_varchar`. The `last_session_retrieved` CTE is: `SELECT id_lead_retrieved, MAX(id_sauron_session) AS last_session FROM isaias_conversational_flow LEFT JOIN datalake_copilot_service_clean.session ON id_external = id_langfuse_session GROUP BY 1`.
- **`is_converted_within_24h` uses the QUALIFIED event timestamp from `supply_events_tracking`, not `obt.ts_event`.** CTE: `SELECT id_lead_ebdb, business_context, MIN(ts_event_adjusted) FROM datalake_supply_flows.supply_events_tracking WHERE funnel_step = 'QUALIFIED' GROUP BY 1, 2`. Compare: `ct.ts_event_adjusted <= bs.ts_created_session + INTERVAL '24' HOUR`.
- `id_lead_retrieved` in `isaias_conversational_flow` is NULL when Isaias didn't retrieve a lead. Use LEFT JOIN to keep all supply rows and INNER JOIN only when requiring a matched lead.
- **`obt_supply.sk_lead` equals `id_lead_ebdb` in source systems.** When joining `obt_supply` to raw source tables (Wololo via `id_reference`, OLOS via `id_lead`, `supply_events_tracking` via `id_lead_ebdb`, Rene via `id_lead_ebdb`), use `sk_lead` as the equivalent of `id_lead_ebdb`. This equivalence is used explicitly in `conversion_time` joins: `ct.id_lead_ebdb = obt.sk_lead`.
- **`datalake_copilot_service_clean.session` is the only bridge between Sauron and Langfuse.** `id_sauron_session` (VARCHAR) in that table equals `CAST(datalake_sauron_clean.session.id AS VARCHAR)`; `id_external` equals `datalake_langfuse_clean.traces.id_session`. There is no direct join path between the two systems — always route through `copilot_service_clean.session`. Standard join pattern: `cs.id_sauron_session = CAST(sau.id AS VARCHAR)` (Sauron side) and `cs.id_external = t.id_session` (Langfuse side).
- **Disqualification node pattern requires LIKE.** Disqualification events in Langfuse use the pattern `o.name LIKE '%.disqualification'` because the node name prefix varies per qualification step. This is the only Isaias Langfuse observation filter that cannot use exact `IN` matching. Always combine it with an explicit `o.name IN (...)` whitelist for all other nodes in the same query to avoid full table scans (see Query 10 for the correct `AND (o.name IN (...) OR o.name LIKE '%.disqualification')` pattern).
- **Escalation node semantics (transbordos).** Two distinct escalation observations: `escalate_when_qualified` = transbordo para Inside Sales (Isaias hands off a qualified lead to Inbound analysts); `escalation_node` = transbordo para outras filas (non-IS queues). Never aggregate them without distinguishing the type. Both must be listed explicitly in the `o.name IN (...)` whitelist.
- **Isaias conversion deduplication key is `(sk_supply, nm_business_context)` — never include `cd_funnel_step`.** A single supply can appear at both `opportunity` and `first_listing` funnel steps; including `cd_funnel_step` in a `COUNT(DISTINCT ...)` key double-counts it. Always use `CAST(sk_supply AS VARCHAR) || '_' || nm_business_context` as the composite key when counting converted supplies in Isaias ledger queries.
- `obt_supply` has no partition columns — filter on `obt.date` (a `DATE` column) for time-bounded queries (table is full-refresh daily). Use `DATE '...'` literals, e.g. `obt.date >= DATE '2026-01-01'`.
- For enriched Isaias session metadata (bot persona, escalation, queue), prefer `datalake_chatbot.sessions` over raw `datalake_sauron_clean.session`: join via `sessions.id_sauron_session = obt.sk_chat_session`.

## Key Metrics

- **Lead volume** (`COUNT(DISTINCT obt.sk_supply)` where `cd_funnel_step = 'lead'`, by `nm_business_context`)
- **Lead → Opportunity conversion rate** (`COUNT_IF(cd_funnel_step = 'opportunity') / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0)`)
- **Lead → First Listing conversion rate** (`COUNT_IF(cd_funnel_step = 'first_listing') / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0)`)
- **Active leads by channel** (grouped by `acquisition_origin` or `company_report_origin`)
- **Discard rate by funnel step** (rows with a discard key joined to `dim_supply_discards`, by `cd_funnel_step`)
- **Recovery volume** (`COUNT` of leads with non-sentinel `sk_recovery` in `fact_supply_events`)
- **Isaias-created lead volume** (`COUNT(DISTINCT sk_supply)` where `tp_origin_acquisition = 'isaias'` and `cd_funnel_step = 'lead'`)
- **Isaias-retrieved lead volume** (`COUNT(DISTINCT sk_supply)` joined to `isaias_conversational_flow` on `id_lead_retrieved`; no origin filter = all retrieved leads; add `tp_origin_acquisition != 'isaias'` to isolate cross-channel re-engagement only; add `tp_origin_acquisition = 'isaias'` to isolate Isaias re-engaging its own past leads)
- **Isaias touchpoint lead volume** (union of created + retrieved; deduplicate on `sk_supply`)
- **Isaias-acquired conversion** (leads with `tp_origin_acquisition = 'isaias'` that reached opportunity or first_listing)
- **Isaias-retrieved conversion** (leads from ICF join, that reached opportunity or first_listing; filter `tp_origin_conversion = 'isaias'` for conversion-attributed subset)
- **Isaias touchpoint conversion** (any Isaias-created or retrieved lead that converted — broadest Isaias impact measure)
- **Session → opportunity rate** (`COUNT(DISTINCT converted supply IDs where is_valid_attribution AND cd_funnel_step = 'opportunity') / COUNT(DISTINCT session IDs)` — requires UNION ALL event-ledger approach, see Query 7)
- **Session → first listing rate** (same pattern, filter `cd_funnel_step = 'first_listing'`)
- **Full Process Sessions Volume** — count of distinct Isaias sessions with `is_full_process = TRUE`. `is_full_process` is NOT a column in `datalake_sauron_clean.session`; it must be derived from Langfuse via the `full_process_sessions` CTE (see Critical Rules) joined through `datalake_copilot_service_clean.session`. In ledger queries, count as `COUNT(DISTINCT CASE WHEN is_full_process = TRUE THEN id_sauron_session END)`.
- **SDR Sessions Volume** — count of distinct Isaias sessions with `is_full_process = FALSE OR is_full_process IS NULL`. Same derivation requirement — must come from Langfuse, not from `datalake_sauron_clean.session` directly. In ledger queries, count as `COUNT(DISTINCT CASE WHEN (is_full_process = FALSE OR is_full_process IS NULL) THEN id_sauron_session END)`.
- **Isaias-only conversion volume** (FP Only — subset of FP+Escalation; ledger: `is_full_process = TRUE AND tp_origin_conversion = 'isaias' AND is_valid_attribution = TRUE`; deduplicate on `CAST(sk_supply AS VARCHAR) || '_' || nm_business_context` — never include `cd_funnel_step` in the key, as a supply can appear at both opportunity and first_listing)
- **Full Process + Escalation conversion volume** (total FP conversions = FP Only + human-closed after escalation; ledger: `is_full_process = TRUE AND is_valid_attribution = TRUE AND (tp_origin_conversion = 'isaias' OR (is_converted_within_24h = TRUE AND planning_operation = 'Inbound'))`; deduplicate on `CAST(sk_supply AS VARCHAR) || '_' || nm_business_context`)
- **SDR conversion volume** (ledger: `(is_full_process = FALSE OR is_full_process IS NULL) AND is_converted_within_24h = TRUE AND is_valid_attribution = TRUE AND planning_operation = 'Inbound'` — Inbound only, never `tp_origin_conversion = 'isaias'`; deduplicate on `CAST(sk_supply AS VARCHAR) || '_' || nm_business_context`)
- **Isaias-only conversion rate** (Isaias-only conversion volume divided by Full Process Sessions Volume)
- **Full Process + Escalation conversion rate** (Full Process + Escalation conversion volume divided by Full Process Sessions Volume)
- **SDR conversion rate** (SDR conversion volume divided by SDR Sessions Volume)
- **Isaias lead retrieval rate** (`COUNT_IF(icf.has_retrieved_lead) / NULLIF(COUNT(*), 0)`)
- **Successful Submission volume** — count of Full Process sessions where Isaias completed photo scheduling: `BOOL_OR(o.name = 'Submission.post_clarification' AND json_extract_scalar(o.output, '$.photo_session_successfully_scheduled') = 'true') = TRUE`. Denominator for rate: Full Process Sessions Volume.
- **Successful Submission rate** — Successful Submission volume / Full Process Sessions Volume
- **Escalation to Inside Sales volume** (transbordo para IS) — Full Process sessions with `escalate_when_qualified` node visited (`has_inside_sales_esc = TRUE`)
- **Escalation to Inside Sales rate** (taxa de transbordo para IS) — Escalation to Inside Sales volume / Full Process Sessions Volume
- **Escalation to Other Queues volume** (transbordo para outras filas) — Full Process sessions with `escalation_node` visited (`has_other_esc = TRUE`)
- **Escalation to Other Queues rate** (taxa de transbordo para outras filas) — Escalation to Other Queues volume / Full Process Sessions Volume
- **Total Escalation rate** (taxa total de transbordo) — (IS escalations + other escalations) / Full Process Sessions Volume
- **Disqualification volume** — Full Process sessions where any `%.disqualification` node was visited (`has_disqualification = TRUE`)
- **Disqualification rate** — Disqualification volume / Full Process Sessions Volume
- **Idle Session volume** (sessões ociosas) — Full Process sessions with no terminal state: `NOT has_successful_submission AND NOT has_inside_sales_esc AND NOT has_other_esc AND NOT has_disqualification`
- **Idle Session rate** — Idle Session volume / Full Process Sessions Volume
- **Funnel Progression per step** — for each conversational step N (1 = Address … 10 = Entry Model), `SUM(sessions with last_step >= N) / SUM(total Full Process sessions)`. Reports what fraction of all sessions reached at least step N.
- **Step Progression (step-to-step rate)** — for step N, `SUM(sessions with last_step >= N+1) / SUM(sessions with last_step >= N)`. Reports what fraction of sessions that reached step N advanced to the next step. Compute via `LEAD()` window function ordered by step within the same time period (see Query 11).

## Relationships with Other Entities

### Chatbot Sessions (N:1 — many supply events may share one Isaias session)

- Session path (leads created by Isaias): `CAST(sau.id AS VARCHAR) = obt_supply.sk_chat_session` where `sk_chat_session != '-1'`
- Lead path (leads retrieved by Isaias): `icf.id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)` via `datalake_chatbot.isaias_conversational_flow`
- Langfuse/mode bridge: `datalake_copilot_service_clean.session` — join `cs.id_sauron_session = CAST(sau.id AS VARCHAR)` to get `cs.id_external` (Langfuse session ID)
- Filter `source_environment` with the explicit list in Critical Rules (not LIKE)

### Isaias Conversational Flow (1:1 per retrieved lead)

- `datalake_chatbot.isaias_conversational_flow.id_lead_retrieved = CAST(obt_supply.sk_lead AS VARCHAR)`
- NULL `id_lead_retrieved` means Isaias didn't surface a supply lead during that session

### 3P Supply (sub-funnel — drill-in for `acquisition_origin = 'rede'`)

- The `dw_3p_supply` schema is the granular model for the rede (third-party broker) channel — partner-submitted leads ingested via the BSP. See `business_entities/3p_supply.md`.
- Bridge via `obt_supply.sk_house = dw_3p_supply.fact_lead_3p_flows.sk_house` (filter `<> -1` on both sides).
- Use `obt_supply` for cross-channel funnel (1P / CIQ / 3P) and `dw_3p_supply` for partner / broker / BSP-reason analysis on rede leads.

### Region (N:1)

- `obt_supply.sk_region = dw_region.dim_region.sk_region`
- Geographic breakdown (city, neighborhood) of supply funnel

### Listing / Property (N:1)

- `obt_supply.sk_house` links to `datalake_ebdb_listing.house`
- Populated from QUALIFIED stage onward; value is `-1` before that

## Dos and Don'ts

**Do:**
- **Default date horizon: current year to date.** When no date range is specified, always filter from `DATE '{{current_year}}-01-01'` to the current date (e.g. `obt.date >= DATE '2026-01-01'` for the year 2026). Only use a different horizon when the user explicitly provides a specific date, period, or range.
- **Default to coincident date for all conversion analyses** — both regular lead conversions and Isaias demand conversions. Only switch to cohort when the user explicitly asks for a cohort view.
- For **Isaias coincident date** conversions, anchor on `data_referencia` (= `DATE(ts_created_session)`) in the ledger query (Query 7 / Query 8). This is the standard date axis for Isaias session-level conversion reporting.
- For **Isaias cohort** conversions (only when explicitly requested), anchor on `DATE(ts_created_session)` as well, but group sessions by creation date and measure which of those sessions eventually produced a conversion — rather than attributing conversions to the day they occurred.
- For **regular lead coincident date** conversions, filter `obt.date` to the analysis window on conversion-step rows (`cd_funnel_step IN ('opportunity', 'first_listing')`), without constraining the lead creation date.
- For **regular lead cohort** conversions (only when explicitly requested), anchor on `obt.date` filtered to `cd_funnel_step = 'lead'` and join each lead's conversion rows without constraining `obt.date` on the conversion side.
- Use `dw_growth.obt_supply` as the primary table — it has all dimensions pre-joined and business logic computed (`acquisition_origin`, `conversion_origin`, `company_report_origin`, `planning_operation`)
- Always filter `nm_business_context` when the question is modality-specific (`'RENT'` or `'SALE'`)
- Use `company_report_origin` or `planning_operation` for channel/product breakdowns that match management dashboards — these are the canonical channel labels
- Use `funnel_order` (integer 1–6) to sort or compare funnel stages; do not rely on alphabetical ordering of `cd_funnel_step`
- When joining Isaias data from `datalake_sauron_clean.session`, always filter `source_environment` using the explicit list in Critical Rules — never use `LIKE '%isaias%'` (may match unrelated environments)
- To measure Isaias as an **acquisition channel** (leads it created), filter `obt_supply.tp_origin_acquisition = 'isaias'` — no join to `isaias_conversational_flow` needed
- To measure Isaias **conversion attribution**, filter `obt_supply.tp_origin_conversion = 'isaias'` for leads where Isaias was the converting touch, or use `planning_operation = 'Inbound'` as the operational grouping
- To measure Isaias as a **re-engagement channel** (leads from other sources it recovered), join `isaias_conversational_flow` on `id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)` and exclude `tp_origin_acquisition = 'isaias'` to avoid double-counting
- To measure **total Isaias influence** (touchpoint), union the two populations and deduplicate on `sk_supply` before aggregating
- When computing session-to-conversion rates, use the UNION ALL event-ledger pattern (see Query 7) and always apply `is_valid_attribution = TRUE` in the numerator to prevent one lead being counted across multiple sessions
- Always segment Isaias analyses by `is_full_process` — SDR (`false/null`) and Full Process (`true`) have different expected funnel depths, so aggregating them produces misleading rates. Derive `is_full_process` from the `full_process_sessions` CTE (see Critical Rules), not from `icf.is_full_process`
- When reporting on Isaias conversion impact, use the three conversion type definitions: **Isaias-only** (FP Only — `is_full_process = TRUE AND tp_origin_conversion = 'isaias'`), **Full Process + Escalation** (superset of FP Only — `is_full_process = TRUE AND (tp_origin_conversion = 'isaias' OR (within_24h AND Inbound))`), and **SDR** (`is_full_process = FALSE/NULL AND within_24h AND Inbound`) — see Query 8 for the full computation

**Don't:**
- Don't use cohort date anchoring unless the user explicitly asks for it — coincident date is the default for all supply conversion analyses (both regular leads and Isaias).
- Don't mix cohort and coincident anchors within the same analysis — doing so produces lead/conversion counts from different time bases that are not comparable.
- Don't conflate Isaias-created leads (`tp_origin_acquisition = 'isaias'`), Isaias-retrieved leads (ICF join), and Isaias touchpoint leads (union of both) — each answers a different question
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
    AND obt.date < DATE '{end_date}'
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

### Query 2 — Lead to first listing conversion rate by reporting channel

**Date anchor: coincident date (default).** Both lead and conversion counts are filtered to the same `obt.date` window — the denominator (leads) and numerator (first listings) both count events that occurred within the window, mixing leads of different ages. For cohort analysis (only when explicitly requested), fix the lead population to those created in the window (`cd_funnel_step = 'lead'`) and remove the `obt.date` constraint from the first-listing rows so all eventual conversions from that cohort are counted.

```sql
SELECT
    obt.nm_business_context,
    obt.company_report_origin,
    COUNT_IF(obt.cd_funnel_step = 'lead')         AS total_leads,
    COUNT_IF(obt.cd_funnel_step = 'prospect')      AS total_prospects,
    COUNT_IF(obt.cd_funnel_step = 'opportunity')   AS total_opportunities,
    COUNT_IF(obt.cd_funnel_step = 'first_listing') AS total_first_listings,
    ROUND(
        CAST(COUNT_IF(obt.cd_funnel_step = 'first_listing') AS DOUBLE)
        / NULLIF(COUNT_IF(obt.cd_funnel_step = 'lead'), 0),
    4) AS lead_to_first_listing_rate
FROM dw_growth.obt_supply AS obt
WHERE
    obt.date >= DATE '{start_date}'
    AND obt.date < DATE '{end_date}'
GROUP BY
    obt.nm_business_context,
    obt.company_report_origin
ORDER BY
    obt.nm_business_context,
    total_leads DESC
```

### Query 3 — Isaias qualification funnel by day

Step-by-step conversion through Isaias's conversational flow, split by operating mode. `is_full_process` is derived from Langfuse (authoritative) rather than from `icf` directly.

```sql
-- Set {start_year} and {start_month} to integer values from your analysis start date. Keep the window short.
WITH full_process_sessions AS (
    SELECT
        t.id_session,
        COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process
    FROM datalake_langfuse_clean.observations AS o
    LEFT JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
    WHERE o.year = {start_year}
        AND o.month >= {start_month}
        AND CONTAINS(t.tags, 'isaias')
        AND t.environment = 'prod'
        AND o.name IN ('orchestrator_init')
    GROUP BY t.id_session
)
SELECT
    DATE(icf.ts_session)                 AS dt_session,
    fps.is_full_process,
    COUNT(*)                              AS total_sessions,
    COUNT_IF(icf.has_user_name)           AS reached_name,
    COUNT_IF(icf.has_business_context)    AS reached_context,
    COUNT_IF(icf.has_pricing_information) AS reached_pricing,
    COUNT_IF(icf.has_photo_selected)      AS reached_photo,
    COUNT_IF(icf.has_submission)          AS completed_submission,
    COUNT_IF(icf.has_retrieved_lead)      AS retrieved_lead,
    ROUND(
        CAST(COUNT_IF(icf.has_submission) AS DOUBLE) / NULLIF(COUNT(*), 0),
    4) AS submission_rate
FROM datalake_chatbot.isaias_conversational_flow AS icf
LEFT JOIN full_process_sessions AS fps
    ON icf.id_langfuse_session = fps.id_session
WHERE
    icf.ts_session >= TIMESTAMP '{start_date}'
    AND icf.ts_session < TIMESTAMP '{end_date}'
GROUP BY DATE(icf.ts_session), fps.is_full_process
ORDER BY dt_session DESC
```

### Query 4 — Isaias-created leads: funnel conversion

Leads where Isaias was the acquisition source (`tp_origin_acquisition = 'isaias'`), showing funnel progression.

```sql
SELECT
    obt.nm_business_context,
    obt.cd_funnel_step,
    obt.funnel_order,
    COUNT(DISTINCT obt.sk_supply) AS total_leads
FROM dw_growth.obt_supply AS obt
WHERE
    obt.tp_origin_acquisition = 'isaias'
    AND obt.date >= DATE '{start_date}'
    AND obt.date < DATE '{end_date}'
GROUP BY
    obt.nm_business_context,
    obt.cd_funnel_step,
    obt.funnel_order
ORDER BY
    obt.nm_business_context,
    obt.funnel_order
```

### Query 5 — Isaias-retrieved leads: re-engagement performance

Leads from other acquisition channels that Isaias re-engaged in a session, with qualification funnel progress.

```sql
-- Set {start_year} and {start_month} to integer values from your analysis start date. Keep the window short.
WITH full_process_sessions AS (
    SELECT
        t.id_session,
        COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process
    FROM datalake_langfuse_clean.observations AS o
    LEFT JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
    WHERE o.year = {start_year}
        AND o.month >= {start_month}
        AND CONTAINS(t.tags, 'isaias')
        AND t.environment = 'prod'
        AND o.name IN ('orchestrator_init')
    GROUP BY t.id_session
)
SELECT
    obt.nm_business_context,
    obt.tp_origin_acquisition     AS original_channel,
    obt.cd_funnel_step,
    obt.funnel_order,
    fps.is_full_process,
    COUNT(DISTINCT obt.sk_supply) AS total_retrieved_leads,
    COUNT_IF(icf.has_submission)  AS isaias_submission
FROM dw_growth.obt_supply AS obt
INNER JOIN datalake_chatbot.isaias_conversational_flow AS icf
    ON icf.id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)
LEFT JOIN full_process_sessions AS fps
    ON icf.id_langfuse_session = fps.id_session
WHERE
    obt.tp_origin_acquisition != 'isaias'
    AND obt.date >= DATE '{start_date}'
    AND obt.date < DATE '{end_date}'
GROUP BY
    obt.nm_business_context,
    obt.tp_origin_acquisition,
    obt.cd_funnel_step,
    obt.funnel_order,
    fps.is_full_process
ORDER BY
    obt.nm_business_context,
    total_retrieved_leads DESC
```

### Query 6 — Three-way Isaias conversion comparison

Compares conversion rates at opportunity and first_listing across the three Isaias populations: created, retrieved, and any touchpoint. The touchpoint CTE deduplicates leads that appear in both.

```sql
WITH
created AS (
    SELECT DISTINCT
        obt.sk_supply,
        obt.nm_business_context,
        obt.cd_funnel_step,
        'created' AS isaias_population
    FROM dw_growth.obt_supply AS obt
    WHERE
        obt.tp_origin_acquisition = 'isaias'
        AND obt.date >= DATE '{start_date}'
        AND obt.date < DATE '{end_date}'
),
retrieved AS (
    SELECT DISTINCT
        obt.sk_supply,
        obt.nm_business_context,
        obt.cd_funnel_step,
        'retrieved' AS isaias_population
    FROM dw_growth.obt_supply AS obt
    INNER JOIN datalake_chatbot.isaias_conversational_flow AS icf
        ON icf.id_lead_retrieved = CAST(obt.sk_lead AS VARCHAR)
    WHERE
        obt.tp_origin_acquisition != 'isaias'
        AND obt.date >= DATE '{start_date}'
        AND obt.date < DATE '{end_date}'
),
touchpoint AS (
    SELECT sk_supply, nm_business_context, cd_funnel_step FROM created
    UNION
    SELECT sk_supply, nm_business_context, cd_funnel_step FROM retrieved
),
all_populations AS (
    SELECT * FROM created
    UNION ALL
    SELECT * FROM retrieved
    UNION ALL
    SELECT sk_supply, nm_business_context, cd_funnel_step, 'touchpoint' FROM touchpoint
)
SELECT
    nm_business_context,
    isaias_population,
    COUNT_IF(cd_funnel_step = 'lead')                    AS total_leads,
    COUNT_IF(cd_funnel_step = 'opportunity')             AS total_opportunities,
    COUNT_IF(cd_funnel_step = 'first_listing')           AS total_first_listings,
    ROUND(
        CAST(COUNT_IF(cd_funnel_step = 'opportunity') AS DOUBLE)
        / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0), 4
    ) AS lead_to_opp_rate,
    ROUND(
        CAST(COUNT_IF(cd_funnel_step = 'first_listing') AS DOUBLE)
        / NULLIF(COUNT_IF(cd_funnel_step = 'lead'), 0), 4
    ) AS lead_to_first_listing_rate
FROM all_populations
GROUP BY nm_business_context, isaias_population
ORDER BY nm_business_context, isaias_population
```

### Query 7 — Isaias session-supply ledger (full construction)

**Date anchor: coincident date (default).** The ledger exposes `data_referencia = DATE(ts_created_session)` — the day the session started — as the standard time axis. For coincident date reporting, group by `data_referencia` and count conversions that fall on each day, regardless of when the underlying lead was created. For cohort reporting (only when explicitly requested), also group by `data_referencia` but treat it as the cohort date: for sessions born on a given day, count what fraction eventually converted — remove the `data_referencia` filter on the conversion side and accumulate across all future dates.

This is a query pattern — not a stored table. Build it each time from the five sources below. The final UNION ALL produces two event types per session: `inicio_sessao` (one row per session, the denominator for rates) and `conversao` (one row per session × supply event, the numerator). `fct_session_supply_base` is the shared base for both branches and also the foundation for Query 8.

Two paths connect sessions to supply events:
- **Session path** (`source_path = 'created_in_session'`): lead linked via `obt.sk_chat_session` — lead was created by Isaias in this session
- **Lead path** (`source_path = 'retrieved_lead'`): lead linked via `icf.id_lead_retrieved` → `cs.id_sauron_session` — lead existed before and was retrieved by Isaias

```sql
-- Set {start_year} and {start_month} to integer values from your analysis start date. Keep the window short.
WITH full_process_sessions AS (
    SELECT 
        t.id_session,
        COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process
    FROM datalake_langfuse_clean.observations o
    LEFT JOIN datalake_langfuse_clean.traces t ON o.id_trace = t.id_trace
    WHERE o.year = {start_year}
        AND o.month >= {start_month}
        AND CONTAINS(t.tags, 'isaias')
        AND t.environment = 'prod'
        AND o.name IN ('orchestrator_init')
    GROUP BY 1
),
last_session_retrieved AS (
    SELECT 
        id_lead_retrieved,
        MAX(id_sauron_session) AS last_session 
    FROM datalake_chatbot.isaias_conversational_flow icf
    LEFT JOIN datalake_copilot_service_clean.session s 
        ON s.id_external = icf.id_langfuse_session
    GROUP BY 1
),
conversion_time AS (
    SELECT 
        id_lead_ebdb,
        business_context,
        MIN(ts_event_adjusted) AS ts_event_adjusted
    FROM datalake_supply_flows.supply_events_tracking
    WHERE funnel_step = 'QUALIFIED'
    GROUP BY 1, 2
),
base_sessions AS (
    SELECT 
        s.id AS id_sauron_session,
        CAST(s.id AS VARCHAR) AS id_sauron_session_varchar,
        s.source_environment,
        s.ts_created AS ts_created_session,
        s.department,
        s.source,
        JSON_EXTRACT_SCALAR(s.metadata, '$.extra_params.referral_source_type') AS referral_source_type
    FROM datalake_sauron_clean.session s
    WHERE s.source_environment IN (
        'isaias_inbound', 'isaias_inbound_main', 'isaias_inbound_c2wa_acq_1', 'isaias_inbound_c2wa_acq_2', 
        'isaias_inbound_c2wa_retarg_1', 'isaias_inbound_c2wa_retarg_2', 'isaias_inbound_owner_landing', 
        'isaias_home', 'isaias_opr', 'isaias_calculadora', 'isaias_inbound_c2wa_camp_3', 
        'isaias_inbound_c2wa_camp_1', 'isaias_inbound_c2wa_camp_2', 'isaias_inbound_c2wa_camp_4'
    )
    AND s.year >= {start_year}
),
obt_session_filtered AS (
    SELECT date, city_group, cd_discard_reason, discard_funnel_step, operation_channel,
           company_report_origin, planning_cluster, sk_lead, sk_supply, nm_business_context,
           sk_chat_session, cd_funnel_step, tp_origin_acquisition, tp_origin_conversion, planning_operation
    FROM dw_growth.obt_supply
    WHERE sk_chat_session IS NOT NULL AND CAST(sk_chat_session AS VARCHAR) != '-1' 
),
obt_lead_filtered AS (
    SELECT date, city_group, cd_discard_reason, discard_funnel_step, operation_channel,
           company_report_origin, planning_cluster, sk_lead, sk_supply, nm_business_context,
           sk_chat_session, cd_funnel_step, tp_origin_acquisition, tp_origin_conversion, planning_operation
    FROM dw_growth.obt_supply
    WHERE sk_lead IS NOT NULL AND CAST(sk_lead AS VARCHAR) != '-1'
),
unified_supply_events AS (
    -- Session path: lead was created in the Isaias session (linked via sk_chat_session)
    SELECT 
        'session' AS source_path, 
        CAST(o.sk_chat_session AS VARCHAR) AS join_session_id,
        o.date, o.city_group, o.cd_discard_reason, o.discard_funnel_step, o.operation_channel,
        o.company_report_origin, o.planning_cluster, o.sk_lead, o.sk_supply, o.nm_business_context,
        o.cd_funnel_step, o.tp_origin_acquisition, o.tp_origin_conversion, o.planning_operation,
        ct.ts_event_adjusted
    FROM obt_session_filtered o
    LEFT JOIN conversion_time ct ON ct.id_lead_ebdb = o.sk_lead AND ct.business_context = o.nm_business_context
    UNION ALL
    -- Lead path: lead was retrieved by Isaias in this session (linked via ICF)
    SELECT 
        'lead' AS source_path,
        cs_u.id_sauron_session AS join_session_id,
        o2.date, o2.city_group, o2.cd_discard_reason, o2.discard_funnel_step, o2.operation_channel,
        o2.company_report_origin, o2.planning_cluster, o2.sk_lead, o2.sk_supply, o2.nm_business_context,
        o2.cd_funnel_step, o2.tp_origin_acquisition, o2.tp_origin_conversion, o2.planning_operation,
        ct2.ts_event_adjusted
    FROM obt_lead_filtered o2
    JOIN datalake_chatbot.isaias_conversational_flow icf_u 
        ON icf_u.id_lead_retrieved = CAST(o2.sk_lead AS VARCHAR)
    JOIN datalake_copilot_service_clean.session cs_u 
        ON cs_u.id_external = icf_u.id_langfuse_session
    LEFT JOIN conversion_time ct2 ON ct2.id_lead_ebdb = o2.sk_lead AND ct2.business_context = o2.nm_business_context
),
fct_session_supply_base AS (
    SELECT 
        bs.id_sauron_session,
        bs.ts_created_session,
        bs.source_environment,
        bs.department,
        bs.source,
        fps.is_full_process,
        bs.referral_source_type,
        u.date,
        u.sk_lead,
        u.sk_supply,
        u.nm_business_context,
        u.cd_funnel_step,
        u.tp_origin_acquisition,
        u.tp_origin_conversion,
        u.planning_operation,
        u.city_group,
        u.cd_discard_reason,
        u.discard_funnel_step,
        u.operation_channel,
        u.company_report_origin,
        u.planning_cluster,
        CASE 
            WHEN u.sk_lead IS NULL THEN 'no_lead'
            WHEN u.source_path = 'session' THEN 'created_in_session'
            WHEN u.source_path = 'lead' THEN 'retrieved_lead'
        END AS lead_acquisition_type,
        CASE 
            WHEN u.source_path = 'session' AND lsr.last_session IS NULL THEN TRUE
            WHEN lsr.last_session = bs.id_sauron_session_varchar THEN TRUE
            ELSE FALSE 
        END AS is_valid_attribution,
        CASE 
            WHEN u.ts_event_adjusted <= bs.ts_created_session + INTERVAL '24' HOUR THEN TRUE 
            ELSE FALSE 
        END AS is_converted_within_24h
    FROM base_sessions bs
    LEFT JOIN datalake_copilot_service_clean.session cs 
        ON cs.id_sauron_session = bs.id_sauron_session_varchar
    LEFT JOIN full_process_sessions fps 
        ON fps.id_session = cs.id_external
    LEFT JOIN unified_supply_events u 
        ON u.join_session_id = bs.id_sauron_session_varchar
    LEFT JOIN last_session_retrieved lsr  
        ON lsr.id_lead_retrieved = CAST(u.sk_lead AS VARCHAR)
)
-- inicio_sessao: one deduplicated row per session (denominator)
SELECT 
    DATE(ts_created_session) AS data_referencia,
    'inicio_sessao'          AS tipo_evento,
    id_sauron_session, ts_created_session, source_environment, department, source,
    is_full_process, referral_source_type,
    CAST(NULL AS DATE)    AS date_event,
    CAST(NULL AS VARCHAR) AS sk_lead,
    CAST(NULL AS VARCHAR) AS sk_supply,
    CAST(NULL AS VARCHAR) AS nm_business_context,
    CAST(NULL AS VARCHAR) AS cd_funnel_step,
    CAST(NULL AS VARCHAR) AS tp_origin_acquisition,
    CAST(NULL AS VARCHAR) AS tp_origin_conversion,
    CAST(NULL AS VARCHAR) AS planning_operation,
    CAST(NULL AS VARCHAR) AS city_group,
    CAST(NULL AS VARCHAR) AS cd_discard_reason,
    CAST(NULL AS VARCHAR) AS discard_funnel_step,
    CAST(NULL AS VARCHAR) AS operation_channel,
    CAST(NULL AS VARCHAR) AS company_report_origin,
    CAST(NULL AS VARCHAR) AS planning_cluster,
    CAST(NULL AS VARCHAR) AS lead_acquisition_type,
    CAST(NULL AS BOOLEAN) AS is_valid_attribution,
    CAST(NULL AS BOOLEAN) AS is_converted_within_24h
FROM fct_session_supply_base
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9

UNION ALL

-- conversao: one row per session × supply event (numerator)
SELECT 
    date                     AS data_referencia,
    'conversao'              AS tipo_evento,
    id_sauron_session, ts_created_session, source_environment, department, source,
    is_full_process, referral_source_type,
    date                          AS date_event,
    CAST(sk_lead AS VARCHAR)      AS sk_lead,
    CAST(sk_supply AS VARCHAR)    AS sk_supply,
    nm_business_context, cd_funnel_step, tp_origin_acquisition, tp_origin_conversion, planning_operation,
    city_group, cd_discard_reason, discard_funnel_step, operation_channel, company_report_origin,
    planning_cluster, lead_acquisition_type, is_valid_attribution, is_converted_within_24h
FROM fct_session_supply_base
WHERE date IS NOT NULL
```

**Key flags in `fct_session_supply_base`:**
- **`lead_acquisition_type`**: `'created_in_session'` (session path via `sk_chat_session`), `'retrieved_lead'` (lead path via ICF), or `'no_lead'` (session with no linked supply event).
- **`is_valid_attribution`**: `TRUE` for session path when no retrieval exists (`lsr.last_session IS NULL`) or when this is the most recent retrieving session (`lsr.last_session = id_sauron_session_varchar`). Prevents one conversion being credited across multiple sessions that touched the same lead.
- **`is_converted_within_24h`**: `TRUE` when the QUALIFIED event in `supply_events_tracking` falls within 24 h of session creation.

### Query 8 — Three Isaias conversion types by day

**Date anchor: coincident date (default).** Groups by `DATE(ts_created_session)` as `data_referencia` — each row represents all conversions whose session started on that day, not when the lead was created. For cohort reporting (only when explicitly requested), interpret `data_referencia` as the session creation cohort and accumulate conversions across all subsequent dates without constraining `date IS NOT NULL` to a window.

Build all CTEs from Query 7 through `fct_session_supply_base`, then replace the final UNION ALL SELECT with this aggregation. It works directly on `fct_session_supply_base` — `date IS NOT NULL` acts as the conversion event filter. Each conversion rate uses its own mode-specific session denominator: Isaias-only and FP+Escalation rates are divided by Full Process sessions; SDR rate is divided by SDR sessions.

```sql
-- (Include all CTEs from Query 7 through fct_session_supply_base, then:)

SELECT
    DATE(ts_created_session) AS data_referencia,
    COUNT(DISTINCT id_sauron_session) AS total_sessions,
    COUNT(DISTINCT CASE WHEN is_full_process = TRUE THEN id_sauron_session END) AS total_fp_sessions,
    COUNT(DISTINCT CASE WHEN (is_full_process = FALSE OR is_full_process IS NULL) THEN id_sauron_session END) AS total_sdr_sessions,

    -- Type 1: Isaias-only (FP Only) — bot completed entire flow autonomously; strict subset of FP+Escalation
    COUNT(DISTINCT CASE
        WHEN date IS NOT NULL
         AND cd_funnel_step IN ('opportunity', 'first_listing')
         AND is_full_process = TRUE
         AND is_valid_attribution = TRUE
         AND tp_origin_conversion = 'isaias'
        THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
    END) AS isaias_only_conversions,

    -- Type 2: Full Process + Escalation — total FP conversions: FP-only (autonomous) + escalated to Inbound within 24h
    COUNT(DISTINCT CASE
        WHEN date IS NOT NULL
         AND cd_funnel_step IN ('opportunity', 'first_listing')
         AND is_full_process = TRUE
         AND is_valid_attribution = TRUE
         AND (tp_origin_conversion = 'isaias' OR (is_converted_within_24h = TRUE AND planning_operation = 'Inbound'))
        THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
    END) AS fp_plus_escalation_conversions,

    -- Type 3: SDR conversion — SDR session, Inbound analysts closed within 24h (Inbound only)
    COUNT(DISTINCT CASE
        WHEN date IS NOT NULL
         AND cd_funnel_step IN ('opportunity', 'first_listing')
         AND (is_full_process = FALSE OR is_full_process IS NULL)
         AND is_valid_attribution = TRUE
         AND is_converted_within_24h = TRUE
         AND planning_operation = 'Inbound'
        THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
    END) AS sdr_conversions,

    -- Rates: FP-type conversions / FP sessions; SDR conversions / SDR sessions
    ROUND(
        CAST(COUNT(DISTINCT CASE
            WHEN date IS NOT NULL AND cd_funnel_step IN ('opportunity', 'first_listing')
             AND is_full_process = TRUE AND is_valid_attribution = TRUE
             AND tp_origin_conversion = 'isaias'
            THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
        END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_full_process = TRUE THEN id_sauron_session END), 0),
    4) AS isaias_only_rate,
    ROUND(
        CAST(COUNT(DISTINCT CASE
            WHEN date IS NOT NULL AND cd_funnel_step IN ('opportunity', 'first_listing')
             AND is_full_process = TRUE AND is_valid_attribution = TRUE
             AND (tp_origin_conversion = 'isaias' OR (is_converted_within_24h = TRUE AND planning_operation = 'Inbound'))
            THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
        END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN is_full_process = TRUE THEN id_sauron_session END), 0),
    4) AS fp_plus_escalation_rate,
    ROUND(
        CAST(COUNT(DISTINCT CASE
            WHEN date IS NOT NULL AND cd_funnel_step IN ('opportunity', 'first_listing')
             AND (is_full_process = FALSE OR is_full_process IS NULL)
             AND is_valid_attribution = TRUE AND is_converted_within_24h = TRUE
             AND planning_operation = 'Inbound'
            THEN CAST(sk_supply AS VARCHAR) || '_' || nm_business_context
        END) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT CASE WHEN (is_full_process = FALSE OR is_full_process IS NULL) THEN id_sauron_session END), 0),
    4) AS sdr_rate
FROM fct_session_supply_base
GROUP BY DATE(ts_created_session)
ORDER BY data_referencia DESC
```

### Query 9 — Full Isaias session extraction from Langfuse traces

> **Heavy query — keep the window short (days to a few weeks, not months).** Scanning `datalake_langfuse_clean.observations` is expensive; wide windows will time out or queue for a long time.

Produces one row per Langfuse session with: feature flags extracted from `orchestrator_init`, boolean step-detection flags for every funnel node, supply funnel context from `obt_supply`, and chat metrics from `fact_chat_metrics`. Demonstrates: (1) extracting flags from `orchestrator_init` output; (2) detecting node visits via `BOOL_OR(o.name = '...')`; (3) splitting `obt_supply` into two separate CTEs (`obt_agg_chat` / `obt_agg_lead`) to prevent Cartesian fan-out when `sk_chat_session` and `sk_lead` are not in a strict 1:1 relationship; (4) the full join chain `copilot_service → Langfuse → Sauron → obt_supply → fact_chat_metrics`.

Set `{start_year}` and `{start_month}` to the integer year and month of `{start_date}`.

```sql
WITH
filtered_session AS (
  SELECT
    id_external,
    id_sauron_session,
    ts_created
  FROM datalake_copilot_service_clean.session
  WHERE ts_created >= DATE '{start_date}'
),

-- Split into two CTEs: grouping by both sk_chat_session and sk_lead in the same CTE
-- risks a fan-out Cartesian product if they are not perfectly 1:1.
obt_agg_chat AS (
  SELECT
    CAST(sk_chat_session AS VARCHAR) AS sk_chat_session,
    MAX(CAST(sk_lead AS VARCHAR)) AS sk_lead,
    MAX(funnel_order) AS max_funnel_step,
    BOOL_OR(
      (discard_funnel_step = 'lead' OR discard_funnel_step = 'prospect')
      AND discard_opp_user = -1
    ) AS disqualified
  FROM dw_growth.obt_supply
  WHERE sk_chat_session IS NOT NULL
    AND CAST(sk_chat_session AS VARCHAR) != '-1'
  GROUP BY 1
),

obt_agg_lead AS (
  SELECT
    CAST(sk_lead AS VARCHAR) AS sk_lead,
    MAX(funnel_order) AS max_funnel_step,
    BOOL_OR(
      (discard_funnel_step = 'lead' OR discard_funnel_step = 'prospect')
      AND discard_opp_user = -1
    ) AS disqualified
  FROM dw_growth.obt_supply
  WHERE sk_lead IS NOT NULL
    AND CAST(sk_lead AS VARCHAR) != '-1'
  GROUP BY 1
),

-- Pre-cast Sauron session IDs to avoid repeated casting during joins.
sauron_sessions AS (
  SELECT
    CAST(id AS VARCHAR) AS id_varchar,
    source_environment
  FROM datalake_sauron_clean.session
),

sessions AS (
  SELECT
    t.id_session,
    -- Feature flags from orchestrator_init output (pattern 1)
    COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE)                   AS is_full_process,
    COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_pricing_negotiator_enabled') = 'true'), FALSE)      AS is_new_pricing_agent,
    COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_property_details_agent_enabled') = 'true'), FALSE)  AS is_new_draft_agent,
    -- Node presence / step detection (pattern 2)
    BOOL_OR(o.name = 'UserNameQualification.post_clarification'  AND json_extract_scalar(o.output, '$.user_name_verified') = 'true')          AS user_name_step,
    BOOL_OR(o.name = 'LeadCreation.pre_clarification')                                                                                        AS address_step,
    BOOL_OR(o.name = 'PropertySubtype.post_clarification'        AND json_extract_scalar(o.output, '$.property_subtype') IS NOT NULL)          AS property_type_step,
    BOOL_OR(o.name = 'DraftConfirmation.post_clarification'      AND json_extract_scalar(o.output, '$.DraftConfirmation_confirmation') = 'true') AS draft_step,
    BOOL_OR(o.name = 'RentPricingSuggestion.post_clarification'  AND json_extract_scalar(o.output, '$.pricing.chosen_rent_price') IS NOT NULL)  AS pricing_rent_step,
    BOOL_OR(o.name = 'SalePricingSuggestion.post_clarification'  AND json_extract_scalar(o.output, '$.pricing.chosen_sale_price') IS NOT NULL)  AS pricing_sale_step,
    BOOL_OR(o.name = 'ListAvailablePhotoTimeNode.post_clarification' AND json_extract_scalar(o.output, '$.photo_schedule_date') IS NOT NULL)    AS photo_step,
    BOOL_OR(o.name = 'Submission.post_clarification'             AND json_extract_scalar(o.output, '$.photo_session_successfully_scheduled') = 'true') AS submission_step,
    BOOL_OR(o.name = 'escalate_when_qualified')                  AS escalated_qualified,
    BOOL_OR(o.name = 'PropertyDetailsAgent.pre_clarification')   AS new_draft_agent,
    BOOL_OR(o.name = 'PricingNegotiatorAgent.pre_clarification') AS new_pricing_agent,
    BOOL_OR(o.name = 'FAQAgentInputState')                       AS has_faq_agent_interaction,
    BOOL_OR(o.name = 'escalation_node')                          AS escalated_non_qualified,
    MAX(json_extract_scalar(o.output, '$.lead_id'))                                              AS lead_retrieved,
    MAX(json_extract_scalar(o.output, '$.additional_kwargs.parsed.reason'))                      AS reason_escalated,
    MAX(json_extract_scalar(o.output, '$.last_bot_message.metadata.escalation_reason'))          AS reason_escalated_detail,
    MAX(CASE WHEN o.name = 'Submission.post_clarification' THEN json_extract_scalar(o.output, '$.property_dedup_action') END)  AS property_dedup_action,
    MAX(CASE WHEN o.name = 'Submission.post_clarification' THEN json_extract_scalar(o.output, '$.property_dedup_reason') END)  AS property_dedup_reason,
    MAX(CASE WHEN o.name = 'Submission.clarification'      THEN json_extract_scalar(o.output, '$.early_exit.answer') END)      AS property_submission_error,
    -- Last node reached (integer rank → decoded in data_modeled)
    MAX(CASE
      WHEN o.name = 'AddressCollectorAgent.pre_clarification' THEN 1
      WHEN o.name IN ('ListingType.pre_clarification', 'PropertyAvailability.pre_clarification') THEN 2
      WHEN o.name = 'PropertySubtype.pre_clarification' THEN 3
      WHEN o.name = 'PropertyVacancy.pre_clarification' THEN 4
      WHEN o.name IN ('PropertyDetailsNode.pre_clarification', 'PropertyDetailsAgent.pre_clarification') THEN 5
      WHEN o.name = 'DraftConfirmation.pre_clarification' THEN 6
      WHEN o.name IN ('SalePricingSuggestion.pre_clarification', 'RentPricingSuggestion.pre_clarification', 'PricingNegotiatorAgent.pre_clarification') THEN 7
      WHEN o.name = 'ListAvailablePhotoTimeNode.pre_clarification' THEN 8
      WHEN o.name = 'PhotoSessionSchedulingAuth.pre_clarification' THEN 9
      WHEN o.name = 'EntryAccessModelNode.pre_clarification' THEN 10
      ELSE 0
    END) AS last_step
  FROM datalake_langfuse_clean.observations o
  INNER JOIN datalake_langfuse_clean.traces t ON o.id_trace = t.id_trace
  INNER JOIN filtered_session fs              ON t.id_session = fs.id_external
  WHERE o.year = {start_year}          -- integer partition; must match {start_date}
    AND o.month >= {start_month}       -- integer partition; must match {start_date}
    AND o.id_trace IS NOT NULL
    AND t.id_session IS NOT NULL
    AND t.environment = 'prod'
    AND CONTAINS(t.tags, 'isaias')
    AND o.name IN (
      'orchestrator_init',
      'PropertyAvailability.pre_clarification', 'ChatOpenAI', 'LeadCreation.pre_clarification',
      'FAQAgentInputState', 'Submission.pre_clarification', 'Submission.clarification',
      'RetrieveProspect.pre_clarification', 'escalation_node', 'escalate_when_qualified',
      'Submission.post_clarification', 'ListAvailablePhotoTimeNode.post_clarification',
      'RentPricingSuggestion.post_clarification', 'DraftConfirmation.post_clarification',
      'UserNameQualification.post_clarification', 'AddressCollectorAgent.post_clarification',
      'PropertySubtype.post_clarification', 'AddressCollectorAgent.pre_clarification',
      'ListingType.pre_clarification', 'PropertySubtype.pre_clarification',
      'PropertyVacancy.pre_clarification', 'SalePricingSuggestion.post_clarification',
      'PropertyDetailsNode.pre_clarification', 'DraftConfirmation.pre_clarification',
      'SalePricingSuggestion.pre_clarification', 'RentPricingSuggestion.pre_clarification',
      'ListAvailablePhotoTimeNode.pre_clarification', 'PhotoSessionSchedulingAuth.pre_clarification',
      'EntryAccessModelNode.pre_clarification', 'PropertyDetailsAgent.pre_clarification',
      'PricingNegotiatorAgent.pre_clarification'
    )
  GROUP BY t.id_session
),

data_modeled AS (
  SELECT
    s.*,
    fcm.*,
    ss.source_environment,
    cs.ts_created AS ts_session,
    COALESCE(obt_chat.disqualified, obt_lead.disqualified) AS disqualified,
    COALESCE(obt_chat.max_funnel_step, obt_lead.max_funnel_step, 0) AS max_funnel_step,
    COALESCE(obt_chat.sk_lead, obt_lead.sk_lead, s.lead_retrieved, s.id_session) AS id_lead,
    CASE
      WHEN s.submission_step                           THEN 'SUBMISSION'
      WHEN s.photo_step                                THEN 'PHOTO'
      WHEN s.pricing_rent_step OR s.pricing_sale_step  THEN 'PRICING'
      WHEN s.draft_step                                THEN 'DRAFT'
      WHEN s.property_type_step                        THEN 'PROPERTY TYPE'
      WHEN s.address_step                              THEN 'ADDRESS'
      WHEN s.user_name_step                            THEN 'NAME'
      ELSE 'NO INTERACTION'
    END AS user_max_step,
    CASE COALESCE(obt_chat.max_funnel_step, obt_lead.max_funnel_step, 0)
      WHEN 1 THEN 'LEAD'
      WHEN 2 THEN 'PROSPECT'
      WHEN 3 THEN 'QUALIFIED'
      WHEN 4 THEN 'AV QUALIFIED'
      WHEN 5 THEN 'OPPORTUNITY'
      WHEN 6 THEN 'FIRST LISTING'
    END AS max_step_supply,
    CASE s.last_step
      WHEN 0  THEN 'NAME'
      WHEN 1  THEN 'ADDRESS'
      WHEN 2  THEN 'BUSINESS CONTEXT'
      WHEN 3  THEN 'PROPERTY TYPE'
      WHEN 4  THEN 'PROPERTY VACANCY'
      WHEN 5  THEN 'PROPERTY DETAILS'
      WHEN 6  THEN 'PROPERTY DETAILS CONFIRMATION'
      WHEN 7  THEN 'PRICING'
      WHEN 8  THEN 'PHOTO'
      WHEN 9  THEN 'AUTH'
      WHEN 10 THEN 'ENTRY MODEL'
    END AS last_step_name
  FROM sessions s
  INNER JOIN filtered_session cs ON s.id_session = cs.id_external
  LEFT JOIN sauron_sessions ss
    ON ss.id_varchar = cs.id_sauron_session
  LEFT JOIN dw_customer_support.fact_chat_metrics fcm
    ON fcm.sk_session = cs.id_sauron_session
   AND cs.id_sauron_session IS NOT NULL
  LEFT JOIN obt_agg_chat obt_chat
    ON obt_chat.sk_chat_session = cs.id_sauron_session
   AND cs.id_sauron_session IS NOT NULL
  LEFT JOIN obt_agg_lead obt_lead
    ON obt_lead.sk_lead = s.lead_retrieved
   AND s.lead_retrieved IS NOT NULL
   AND obt_chat.sk_chat_session IS NULL  -- avoid double-counting when both paths match
)

SELECT * FROM data_modeled
```

**`last_step` node-to-label mapping:**

| `last_step` | Node(s) reached | `last_step_name` |
|---|---|---|
| 0 | (no node matched) | NAME |
| 1 | `AddressCollectorAgent.pre_clarification` | ADDRESS |
| 2 | `ListingType.pre_clarification` / `PropertyAvailability.pre_clarification` | BUSINESS CONTEXT |
| 3 | `PropertySubtype.pre_clarification` | PROPERTY TYPE |
| 4 | `PropertyVacancy.pre_clarification` | PROPERTY VACANCY |
| 5 | `PropertyDetailsNode.pre_clarification` / `PropertyDetailsAgent.pre_clarification` | PROPERTY DETAILS |
| 6 | `DraftConfirmation.pre_clarification` | PROPERTY DETAILS CONFIRMATION |
| 7 | `RentPricingSuggestion.pre_clarification` / `SalePricingSuggestion.pre_clarification` / `PricingNegotiatorAgent.pre_clarification` | PRICING |
| 8 | `ListAvailablePhotoTimeNode.pre_clarification` | PHOTO |
| 9 | `PhotoSessionSchedulingAuth.pre_clarification` | AUTH |
| 10 | `EntryAccessModelNode.pre_clarification` | ENTRY MODEL |

> **Schema version note — two `last_step` scales exist.** The table above documents **Query 9's scale (0–10)**, which includes `DraftConfirmation.pre_clarification` at step 6 and is required for analysing older sessions where that node was part of the flow. **Queries 10 and 11 use a different scale (1–10)** that reflects the current flow after DraftConfirmation was removed: Pricing = 6, Photo = 7, Auth = 8, Successful Submission = 9, Entry Model = 10. Never cross-reference step numbers between Q9 and Q10/11 — the same integer means different things in each scale.

### Query 10 — Isaias Full Process session terminal states (escalações/transbordos, idle, disqualifications, successful submissions)

> **Scoped to Full Process sessions only** (`is_full_process = TRUE`). Terminal state flags are derived from Langfuse observation node names. The LIKE pattern for disqualification is intentional — node name prefixes vary per qualification step; it is paired with an `IN` whitelist to prevent full table scans.

```sql
WITH
filtered_session AS (
    SELECT id_external, id_sauron_session, ts_created
    FROM datalake_copilot_service_clean.session
    WHERE ts_created >= CURRENT_DATE - INTERVAL '42' DAY
),
sessions AS (
    SELECT
        t.id_session,
        COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process,
        -- Transbordo para Inside Sales
        COALESCE(BOOL_OR(o.name = 'escalate_when_qualified'), FALSE)       AS has_inside_sales_esc,
        -- Transbordo para outras filas
        COALESCE(BOOL_OR(o.name = 'escalation_node'), FALSE)               AS has_other_esc,
        COALESCE(BOOL_OR(o.name LIKE '%.disqualification'), FALSE)         AS has_disqualification,
        COALESCE(BOOL_OR(
            o.name = 'Submission.post_clarification'
            AND json_extract_scalar(o.output, '$.photo_session_successfully_scheduled') = 'true'
        ), FALSE) AS has_successful_submission
    FROM datalake_langfuse_clean.observations AS o
    INNER JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
    INNER JOIN filtered_session AS fs ON t.id_session = fs.id_external
    WHERE o.id_trace IS NOT NULL
      AND CAST(o.year AS VARCHAR) || LPAD(CAST(o.month AS VARCHAR), 2, '0') >= DATE_FORMAT(CURRENT_DATE - INTERVAL '42' DAY, '%Y%m')
      AND t.id_session IS NOT NULL
      AND t.environment = 'prod'
      AND CONTAINS(t.tags, 'isaias')
      AND (
          o.name IN (
              'orchestrator_init',
              'AddressCollectorAgent.pre_clarification',
              'ListingType.pre_clarification', 'PropertyAvailability.pre_clarification',
              'PropertySubtype.pre_clarification',
              'PropertyVacancy.pre_clarification',
              'PropertyDetailsNode.pre_clarification', 'PropertyDetailsAgent.pre_clarification',
              'SalePricingSuggestion.pre_clarification', 'RentPricingSuggestion.pre_clarification',
              'PricingNegotiatorAgent.pre_clarification',
              'ListAvailablePhotoTimeNode.pre_clarification',
              'PhotoSessionSchedulingAuth.pre_clarification',
              'Submission.post_clarification',
              'EntryAccessModelNode.pre_clarification',
              'escalate_when_qualified',
              'escalation_node'
          )
          OR o.name LIKE '%.disqualification'
      )
    GROUP BY t.id_session
)
SELECT
    DATE(DATE_TRUNC('week', cs.ts_created))                              AS dt_week,
    COUNT(*)                                                             AS total_sessions,
    COUNT_IF(s.has_successful_submission)                                AS successful_submissions,
    COUNT_IF(s.has_disqualification)                                     AS disqualified_sessions,
    COUNT_IF(s.has_inside_sales_esc)                                     AS escalations_inside_sales,
    COUNT_IF(s.has_other_esc)                                            AS escalations_other,
    COUNT_IF(
        NOT s.has_successful_submission
        AND NOT s.has_inside_sales_esc
        AND NOT s.has_other_esc
        AND NOT s.has_disqualification
    )                                                                    AS idled_sessions,
    ROUND(CAST(COUNT_IF(s.has_successful_submission) AS DOUBLE)          / NULLIF(COUNT(*), 0), 4) AS successful_submission_rate,
    ROUND(CAST(COUNT_IF(s.has_inside_sales_esc) AS DOUBLE)               / NULLIF(COUNT(*), 0), 4) AS escalation_is_rate,
    ROUND(CAST(COUNT_IF(s.has_other_esc) AS DOUBLE)                      / NULLIF(COUNT(*), 0), 4) AS escalation_other_rate,
    ROUND(CAST(COUNT_IF(s.has_disqualification) AS DOUBLE)               / NULLIF(COUNT(*), 0), 4) AS disqualification_rate,
    ROUND(CAST(COUNT_IF(
        NOT s.has_successful_submission AND NOT s.has_inside_sales_esc
        AND NOT s.has_other_esc AND NOT s.has_disqualification
    ) AS DOUBLE) / NULLIF(COUNT(*), 0), 4)                               AS idle_rate
FROM sessions AS s
INNER JOIN filtered_session AS cs ON s.id_session = cs.id_external
WHERE s.is_full_process = TRUE
GROUP BY 1
ORDER BY dt_week DESC
```

### Query 11 — Isaias conversational funnel progression (step reach and step-to-step rates)

> **Scoped to Full Process sessions only.** `last_step` ranks node visits to find the furthest step reached per session. **Funnel Progression** for step N = `SUM(sessions reaching step N) / SUM(total sessions)`; **Step Progression** for step N = `SUM(advanced_to_next_step) / SUM(total_step)`. Both aggregations apply after unnesting.

```sql
WITH
filtered_session AS (
    SELECT id_external, id_sauron_session, ts_created
    FROM datalake_copilot_service_clean.session
    WHERE ts_created >= CURRENT_DATE - INTERVAL '42' DAY
),
sessions AS (
    SELECT
        t.id_session,
        COALESCE(BOOL_OR(json_extract_scalar(o.output, '$.is_draft_enabled') = 'true'), FALSE) AS is_full_process,
        COALESCE(BOOL_OR(o.name = 'escalate_when_qualified'), FALSE) AS has_inside_sales_esc,
        COALESCE(BOOL_OR(o.name = 'escalation_node'), FALSE)         AS has_other_esc,
        MAX(CASE
            WHEN o.name = 'AddressCollectorAgent.pre_clarification'                                                                          THEN 1
            WHEN o.name IN ('ListingType.pre_clarification', 'PropertyAvailability.pre_clarification')                                       THEN 2
            WHEN o.name = 'PropertySubtype.pre_clarification'                                                                                THEN 3
            WHEN o.name = 'PropertyVacancy.pre_clarification'                                                                                THEN 4
            WHEN o.name IN ('PropertyDetailsNode.pre_clarification', 'PropertyDetailsAgent.pre_clarification')                               THEN 5
            WHEN o.name IN ('SalePricingSuggestion.pre_clarification', 'RentPricingSuggestion.pre_clarification',
                            'PricingNegotiatorAgent.pre_clarification')                                                                      THEN 6
            WHEN o.name = 'ListAvailablePhotoTimeNode.pre_clarification'                                                                     THEN 7
            WHEN o.name = 'PhotoSessionSchedulingAuth.pre_clarification'                                                                     THEN 8
            WHEN o.name = 'Submission.post_clarification'
                 AND json_extract_scalar(o.output, '$.photo_session_successfully_scheduled') = 'true'                                        THEN 9
            WHEN o.name = 'EntryAccessModelNode.pre_clarification'                                                                           THEN 10
            ELSE 0
        END) AS last_step
    FROM datalake_langfuse_clean.observations AS o
    INNER JOIN datalake_langfuse_clean.traces AS t ON o.id_trace = t.id_trace
    INNER JOIN filtered_session AS fs ON t.id_session = fs.id_external
    WHERE o.id_trace IS NOT NULL
      AND CAST(o.year AS VARCHAR) || LPAD(CAST(o.month AS VARCHAR), 2, '0') >= DATE_FORMAT(CURRENT_DATE - INTERVAL '42' DAY, '%Y%m')
      AND t.id_session IS NOT NULL
      AND t.environment = 'prod'
      AND CONTAINS(t.tags, 'isaias')
      AND o.name IN (
          'orchestrator_init',
          'AddressCollectorAgent.pre_clarification',
          'ListingType.pre_clarification', 'PropertyAvailability.pre_clarification',
          'PropertySubtype.pre_clarification',
          'PropertyVacancy.pre_clarification',
          'PropertyDetailsNode.pre_clarification', 'PropertyDetailsAgent.pre_clarification',
          'SalePricingSuggestion.pre_clarification', 'RentPricingSuggestion.pre_clarification',
          'PricingNegotiatorAgent.pre_clarification',
          'ListAvailablePhotoTimeNode.pre_clarification',
          'PhotoSessionSchedulingAuth.pre_clarification',
          'Submission.post_clarification',
          'EntryAccessModelNode.pre_clarification',
          'escalate_when_qualified',
          'escalation_node'
      )
    GROUP BY t.id_session
),
data_modeled AS (
    SELECT s.*, cs.ts_created AS ts_session
    FROM sessions AS s
    INNER JOIN filtered_session AS cs ON s.id_session = cs.id_external
),
weekly_base AS (
    SELECT
        DATE(DATE_TRUNC('week', ts_session)) AS dt_week,
        COUNT(*)                             AS total_sessoes,
        COUNT_IF(last_step >= 1)             AS n_1,
        COUNT_IF(last_step >= 2)             AS n_2,
        COUNT_IF(last_step >= 3)             AS n_3,
        COUNT_IF(last_step >= 4)             AS n_4,
        COUNT_IF(last_step >= 5)             AS n_5,
        COUNT_IF(last_step >= 6)             AS n_6,
        COUNT_IF(last_step >= 7)             AS n_7,
        COUNT_IF(last_step >= 8)             AS n_8,
        COUNT_IF(last_step >= 9)             AS n_9,
        COUNT_IF(last_step >= 10)            AS n_10,
        COUNT_IF(last_step = 1  AND has_inside_sales_esc) AS is_esc_1,
        COUNT_IF(last_step = 2  AND has_inside_sales_esc) AS is_esc_2,
        COUNT_IF(last_step = 3  AND has_inside_sales_esc) AS is_esc_3,
        COUNT_IF(last_step = 4  AND has_inside_sales_esc) AS is_esc_4,
        COUNT_IF(last_step = 5  AND has_inside_sales_esc) AS is_esc_5,
        COUNT_IF(last_step = 6  AND has_inside_sales_esc) AS is_esc_6,
        COUNT_IF(last_step = 7  AND has_inside_sales_esc) AS is_esc_7,
        COUNT_IF(last_step = 8  AND has_inside_sales_esc) AS is_esc_8,
        COUNT_IF(last_step = 9  AND has_inside_sales_esc) AS is_esc_9,
        COUNT_IF(last_step = 10 AND has_inside_sales_esc) AS is_esc_10,
        COUNT_IF(last_step = 1  AND has_other_esc)        AS oth_esc_1,
        COUNT_IF(last_step = 2  AND has_other_esc)        AS oth_esc_2,
        COUNT_IF(last_step = 3  AND has_other_esc)        AS oth_esc_3,
        COUNT_IF(last_step = 4  AND has_other_esc)        AS oth_esc_4,
        COUNT_IF(last_step = 5  AND has_other_esc)        AS oth_esc_5,
        COUNT_IF(last_step = 6  AND has_other_esc)        AS oth_esc_6,
        COUNT_IF(last_step = 7  AND has_other_esc)        AS oth_esc_7,
        COUNT_IF(last_step = 8  AND has_other_esc)        AS oth_esc_8,
        COUNT_IF(last_step = 9  AND has_other_esc)        AS oth_esc_9,
        COUNT_IF(last_step = 10 AND has_other_esc)        AS oth_esc_10
    FROM data_modeled
    WHERE is_full_process = TRUE
    GROUP BY 1
)
SELECT
    wb.dt_week,
    u.step,
    wb.total_sessoes,
    u.cnt                                                              AS total_step,
    u.is_esc_cnt                                                       AS escalation_to_inside_sales,
    u.oth_esc_cnt                                                      AS other_escalations,
    LEAD(u.cnt) OVER (PARTITION BY wb.dt_week ORDER BY u.step_order)   AS advanced_to_next_step,
    ROUND(
        CAST(LEAD(u.cnt) OVER (PARTITION BY wb.dt_week ORDER BY u.step_order) AS DOUBLE)
        / NULLIF(u.cnt, 0) * 100, 2
    )                                                                  AS step_progression_pct
FROM weekly_base wb
CROSS JOIN UNNEST(
    ARRAY['#1 Address', '#2 Business Context', '#3 Property Type', '#4 Property Vacancy',
          '#5 Property Details', '#6 Pricing', '#7 Photo', '#8 Auth',
          '#9 Successful Submission', '#10 Entry Model'],
    ARRAY[n_1, n_2, n_3, n_4, n_5, n_6, n_7, n_8, n_9, n_10],
    ARRAY[is_esc_1, is_esc_2, is_esc_3, is_esc_4, is_esc_5, is_esc_6, is_esc_7, is_esc_8, is_esc_9, is_esc_10],
    ARRAY[oth_esc_1, oth_esc_2, oth_esc_3, oth_esc_4, oth_esc_5, oth_esc_6, oth_esc_7, oth_esc_8, oth_esc_9, oth_esc_10]
) WITH ORDINALITY AS u(step, cnt, is_esc_cnt, oth_esc_cnt, step_order)
ORDER BY u.step_order, wb.dt_week

-- Aggregated metrics (apply as outer query or compute separately):
-- Funnel Progression for step N:  SUM(CAST(total_step AS DOUBLE)) / SUM(total_sessoes)
-- Step Progression for step N:    SUM(CAST(advanced_to_next_step AS DOUBLE)) / SUM(total_step)
```
