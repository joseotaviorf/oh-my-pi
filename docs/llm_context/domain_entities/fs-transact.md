# FS Transact

## Ownership

**Data Owner:**
- helder.rodrigues@quintoandar.com.br

**Data Steward:**
- helder.rodrigues@quintoandar.com.br

---

## Overview

- **Objective:** FS Transact tracks QuintoAndar's For Sale (residential purchase-and-sale) transaction funnel — from the buyer's first offer through key handover and property registration at the notary office (cartório).
- **Asset status / lifecycle:** An offer moves through Offer Submitted (OS) → Offer Accepted (OA) → Sale Agreement Created (SAC) → **Sale Agreement Signed (CCV)** → **Closed Deal (CD)** → post-closing obligations (Due Diligence, financing, deed, registration, key handover). The EoF/EoP split and stage-by-stage detail follow below in this section.
- **Typical actions / events:** offer negotiation, CCV drafting and signing, credit analysis (Mortgage track), due diligence, deed execution (Cash track), property registration (CRI), key handover.
- **Common metrics:** `# CCV`, `# CD` (Finance's official revenue metric), `OS2OA` / `OS2CCV` / `CCV2CD` conversion rates, EoF/EoP lead times, NPS/DSAT by payment track. Full formulas and benchmarks in [Key Metrics](#key-metrics) ([EoF Metrics](#eof-metrics) and [EoP Metrics](#eop-metrics)).
- **Source systems:** SalesFlow (`datalake_sales_flow_clean`), Atta — financing/Corban (`dw_atta`), Salesforce Legal Ops CDC events (see [Salesforce CDC Tables](#salesforce-cdc-tables-datalake_salesforce_clean) in Tables), LegoContract (`datalake_legalops_clean`).
- **Related entities:** For the equivalent For Rent funnel, see [`fr_transact.md`](fr_transact.md); for the cross-domain "signed contracts" question, see [`closing.md`](closing.md). Full cross-links in [Relationships with Other Entities](#relationships-with-other-entities).

**FS Transact** is the transaction funnel for QuintoAndar's For Sale (Venda) business — from the first offer submitted by the buyer through key handover and property registration at the notary office (cartório).

The funnel has two major blocks:

| Block | Scope | Revenue relevance |
|-------|--------|-----------------------|
| **EoF — End of Funnel** | Offer Submitted (OS) → Closed Deal (CD) | CD = the Finance team's official revenue event |
| **EoP — End of Process** | Signed CCV → Keys + CRI | Post-closing obligations |

> ⚠️ **Scope: 1P transactions exclusively.** 3P transactions (`payment_model = 'CLOSING_3P'`) follow a completely different flow. **Never mix 1P and 3P in the same analysis.** Always apply the filters from [Shared building blocks](#shared-building-blocks).

> ⚠️ **CCV ≠ CD (critical):**
> - **CCV** (`fact_offers.ts_sale_agreement_signed`) = signed contract. Commercial/pipeline milestone.
> - **CD** (`fact_closing_flows.sk_legal_analysis_ended_date`) = a CCV that completed DD + Termo de Corretagem (brokerage agreement). **The Finance team's official sales metric.** Use CD for any financial/revenue analysis; use CCV for pipeline and conversion analyses.

All EoF events are sourced from `dw_sale.fact_offers` (1 row per offer):

| Stage | Abbrev | Source | Notes |
|---------|-------|-------|-------|
| Offer Submitted | OS | `fact_offers.ts_offer_submitted` | FS Transact entry point |
| Offer Accepted | OA | `fact_offers.ts_offer_accepted` | Owner accepts |
| Offer Rejected / Dismissed | OR | `fact_offers.ts_offer_dismissed` | Before acceptance |
| Offer Cancelled | — | `fact_offers.ts_offer_canceled` | Before or after acceptance |
| Offer Rescued | — | `fact_offers.ts_offer_rescued` | `dim_offer.is_a_rescued_offer = TRUE` |
| Sale Agreement Created | SAC | `fact_offers.ts_sale_agreement_created` | Pipeline milestone — NOT revenue |
| Sale Agreement Drafted | CCVe | `fact_offers.ts_sale_agreement_drafted` | CCV draft in progress |
| **Sale Agreement Signed** | **CCV** | **`fact_offers.ts_sale_agreement_signed`** | **Commercial milestone. NOT CD.** |
| Sale Agreement Cancelled | — | `fact_offers.ts_sale_agreement_canceled` | `dim_sale_agreement.is_ccv_canceled = TRUE` |
| CCV Rescued | — | `dim_sale_agreement.is_a_rescued_ccv = TRUE` | — |
| **Closed Deal** | **CD** | **`fact_closing_flows.sk_legal_analysis_ended_date`** | **CCV + DD approved + TC. Finance's official sales metric.** |

**OS → OA (Offer Negotiation)**
The EN mediates price negotiation between buyer and seller. The lowest-conversion stage (~60% OS→OA). Drop drivers: price misalignment, deep discounts, seller urgency, EN capacity/skill. QA product involvement is minimal — almost all of the interaction happens through the EN.

**OA → CCV (Contract)**
Legal Ops runs this: document collection, cross-validation, CCV generation, digital signature. ~25% of CCVs go through contractual adjustments. Credit analysis for financed cases runs in parallel here.

**CCV → CD (Due Diligence + Termo de Corretagem)**
CD = a CCV that has completed:
1. **Due Diligence (DD)** — legal review of the seller and the property (~9 days on average; ~80% of cases are "No Flag" or "Low Risk")
2. OR **Termo de Corretagem (TC)** — when the parties proceed with their own CCV, without QuintoAndar's services, they sign a brokerage agreement (termo de corretagem) that guarantees payment of QuintoAndar's brokerage fee. These cases may still have a DD, but a simplified one.

CD is the Finance team's revenue event. The product-side source is `fact_closing_flows.sk_legal_analysis_ended_date`. The source that contains all CDs, including brokerage-agreement-only deals and operations outside the product, is `datalake_gsheets_clean.closed_deals`.

### Payment Tracks (EoP)

**Always** segment by `dim_sale_agreement.payment_method`. LT and NPS distributions vary drastically across tracks.

| Track | % of CCVs | Characteristic |
|-------|-----------|----------------|
| **Mortgage (Financiamento)** | ~70% | Longer and more complex; bank-dependent |
| **Cash (À Vista)** | ~30% | Simpler; notary-office-dependent |
| **Consortium (Consórcio)** | ~2% | Operated with partner Bamaq |
| **Hybrid** | ~4% | Buyer and seller transacting simultaneously on QA |

Within Mortgage:
- **Internal Corban** (~14%): loan correspondent operated by QA. Best NPS (29.6 vs 36.6) and lowest LT (100d vs 127d). Identify via `franchise_name LIKE '%Quinto Andar%'` through `dw_atta.fact_pre_analysis_proposal_flow`.
- **Partner Corban** (~86%): external correspondents.

Within Cash:
- **CRN Parceiro** (~82%): NPS 62.1, LT 75.5d
- **CRN Não-parceiro** (~18%): NPS 2.8, LT 121.9d — a 60-point NPS gap and 46-day LT gap. Always flag in Cash analyses.

### Steps common to Cash and Mortgage

**Onboarding** — The first post-CCV touchpoint; handover from the EN to the SPOC. Cash goal: conversion to CRN parceiro (~89% attach). Mortgage goal: conversion to Internal Corban (measured when the buyer selects a proposal, not at authorization). Currently 100% manual; AI (Vandinha) rolling out for Cash in H1 2026.

**Sinal (Earnest Payment)** — ~6% of the sale price, held by QA. The seller receives nothing at this point — the main source of seller frustration.

**Regularização** — Registry updates and legal adjustments (averbações, fiduciary liens, addenda, rescissions). Executed by Legal Ops. On Mortgage: cancellation of existing fiduciary liens must happen before the bank's legal analysis.

### Track-specific steps

**Cash:**
```
CCV Assinado → Onboarding → Sinal → Regularização
→ Escritura (CRN): more intensive; deed, signatures, full payment, ITBI
  Partner CRN: ~40d. With averbação: +23d.
→ Entrega de Chaves (usually on the same day as the deed)
→ Registro (CRI): ~25.7d after the deed
```
Total Cash LT: partner without averbação ~72d; with averbação ~98d; without partner ~122d.

**Mortgage:**
```
[Análise de Crédito] — often before the CCV
  Caixa Econômica Federal = highest volume, no third-party API;
  85% of buyers wait for the Caixa result before moving forward.
  LT: ~18d (IC) / ~13d (Partners)
→ CCV Assinado
→ Onboarding → Sinal → Regularização
→ Bank Selection + Data Input: errors here restart the process
→ Vistoria and Legal Analysis (parallel): ~80% of the financing-stage LT
→ Financing Contract + Down Payment: IQ, managerial interview, signature
  Financing-stage LT: ~50d (IC) / ~59d (Partners)
→ Registro (CRI) + Payment by the bank + Entrega de Chaves
```
Total Mortgage LT: IC ~100d; Partners ~127d.

**Consortium:** Operated with Bamaq. Doc review → Vistoria → Contract → ITBI + CRI → Bamaq releases funds within 2 business days → 10% cashback to the buyer.

**Hybrid:** ~4% of CCVs. Individual processes identical to the other tracks, but buy-side and sell-side timings need to be coordinated.

**ROFR (Direito de Preferência):** The tenant has 30 days to exercise it; an end-user buyer gets a 90-day vacate period (can add 120+ days to EoP). Blocked until the matrícula is delivered. Cases with an external tenant are outside ops' control.

### Buyer Prospect

**Buyer Prospect (BP)** = a buyer with a booked visit (VISIT_BOOKED) on For Sale.

**Correct source: `dw_sale.fact_sale_demand_event` + `dw_sale.dim_sale_event_type`**

```sql
-- Monthly # Buyer Prospect (1P, excluding 3P)
SELECT
    DATE_FORMAT(dd.month_start, '%Y-%m')   AS month,
    COUNT(DISTINCT fde.sk_buyer)            AS buyer_prospects
FROM dw_sale.fact_sale_demand_event AS fde
JOIN dw_sale.dim_sale_event_type    AS det ON fde.sk_event_type = det.sk_event_type
JOIN dw_public.dim_date             AS dd  ON fde.sk_event_date = dd.sk_date
WHERE det.event_name      = 'VISIT_BOOKED'
  AND fde.is_3p_demand    = false
  AND fde.is_3p_supply    = false
GROUP BY 1
ORDER BY 1
```
> See [Golden Queries](#golden-queries) for the full monthly NBP/RBP breakdown query.

Validation: ~90% adherence to Fibonacci (26.8k vs 29.8k — Mar/26, 5 cities). Residual ~10% gap due to differences in the prospect activation window.

> ⚠️ **`fact_buyer_prospects` is NOT the correct source for `# BP`** — it only captures the buyer's first-ever historical booking (~50% of the total). It is useful only for lifetime per-buyer journey analyses.

| Type | Description | Share |
|------|-----------|-------|
| **NBP** (New Buyer Prospect) | The buyer's first-ever visit on the platform | ~70% of monthly BP |
| **RBP** (Recovery Buyer Prospect) | Buyer returning after a period of inactivity | ~30% of monthly BP |

Segment via `dim_buyer_prospect_type` (join on `fact_sale_demand_event.sk_buyer_prospect_type`). The dimension is time-windowed: `ts_activation` → `ts_activation_end`.

Fibonacci (Mar/26, 5 cities): NBP = 20,715, RBP = 9,138, Total = 29,853.

*Last updated 2026-06-30 via Superset metadata (TARS session x7k2m9). The numbers in this document represent a rough estimate based on observations at the time this file was last updated. Use them as a reference, not as a definitive answer for users.*

---

## Related Metric Entities

- [Listing Demand Funnel Conversions](../metric_entities/listing_demand_funnel_conversions.md) — official **listing-cohort** conversions for For Sale: **L2VB** (Listing → Visit Booked), **L2VC** (Listing → Visit Completed), **L2OS** (Listing → Offer Submitted), and **L2CCV** (Listing → CCV / Sale Agreement Signed), all anchored to `sk_house` via `fact_visits` / `fact_offers` / `dim_sale_agreement`. Use this source when the question asks for an **official** conversion rate by listing cohort — these take precedence over the coincident/offer-cohort ratios in [EoF Metrics](#eof-metrics) (`OS2OA`, `CCV2CD`, etc.), which are computed over a different base (offers, not listings).

---

## Glossary and Synonyms

| Term | Meaning | Data source |
|-------|-------------|----------------|
| **FS / For Sale / Venda** | QuintoAndar's residential purchase-and-sale business | — |
| **FS Transact / Sale Transaction** | The full OS → Key Handover journey | — |
| **EoF / End of Funnel** | OS → OA → SAC → CD sub-funnel. Revenue-recognition block. | — |
| **EoP / End of Process** | CD → Registration → Keys sub-funnel. Post-closing obligations. | — |
| **OS / Offer Submitted / Proposta Enviada** | Buyer submits a purchase offer | `fact_offers.ts_offer_submitted` |
| **Offer by Agent / Oferta por Agente / Submissão por Corretor** | Feature that allows a broker (agent) to submit a purchase offer on the buyer's behalf. Identified by `actor_type = 'AGENT'` and `uuid_actor IS NOT NULL` on `datalake_sales_flow_clean.offer`. When both are `NULL`, the offer was submitted directly by the buyer. There is currently no dedicated flag on `dw_sale.fact_offers` — to segment, join `datalake_sales_flow_clean.offer` via `id` (equivalent to `id_sales_flow`). | `datalake_sales_flow_clean.offer.uuid_actor`, `datalake_sales_flow_clean.offer.actor_type` |
| **OA / Offer Accepted / Proposta Aceita** | Owner accepts the offer | `fact_offers.ts_offer_accepted` |
| **OR / Offer Rejected / Dismissed / Proposta Recusada** | Offer dismissed before acceptance | `fact_offers.ts_offer_dismissed` |
| **SAC / Sale Agreement Created / CCV Criado** | CCV draft created — pipeline milestone, NOT revenue | `fact_offers.ts_sale_agreement_created` |
| **CCVe / CCV esboçado** | CCV draft in progress | `fact_offers.ts_sale_agreement_drafted` |
| **CCV / Compromisso de Compra e Venda / Sale Agreement Signed** | Signed contract. Commercial milestone. **Not CD.** | `fact_offers.ts_sale_agreement_signed` |
| **CD / Closed Deal / Venda / Fechamento** | A CCV that went through DD + Termo de Corretagem. **Finance's official sales metric.** | `fact_closing_flows.sk_legal_analysis_ended_date` |
| **BP / Buyer Prospect** | Buyer with a booked visit (VISIT_BOOKED) on For Sale. **Correct source: `fact_sale_demand_event`.** | `fact_sale_demand_event` WHERE `event_name = 'VISIT_BOOKED'` |
| **NBP / New Buyer Prospect** | The buyer's first-ever visit on the platform (~70% of monthly BP) | `dim_buyer_prospect_type.buyer_prospect_type = 'NBP'` |
| **RBP / Recovery Buyer Prospect** | A buyer returning after inactivity (~30% of monthly BP) | `dim_buyer_prospect_type.buyer_prospect_type = 'RBP'` |
| **BP2CCV** | BP → CCV conversion. M0+M1 cohort in Fibonacci. | `sandbox.summary_table` (official); approximate via `fact_sale_demand_event` + `fact_offers` |
| **Diligência / Due Diligence** | Post-CCV legal review (house, seller, report) | `dim_sale_agreement.*_dilligence_status` |
| **Escritura** | Drawing up the deed at the Cartório de Notas (Cash track) | — |
| **Registro / CRI** | Formal registration of ownership at the Cartório de Registro de Imóveis | `fact_closing_flows.sk_house_registry_ended_date` |
| **Entrega de Chaves** | Physical key handover to the buyer | `fact_closing_flows.sk_sale_key_delivered_date` |
| **Sinal / Earnest Payment** | ~6% of the sale price, held by QuintoAndar | — |
| **Regularização** | Registry updates and legal adjustments (Legal Ops) | — |
| **ROFR / Direito de Preferência** | Right-of-first-refusal clause for tenants | — |
| **Averbação** | Registry annotation; adds ~23 days to Cash LT when present | — |
| **Matrícula** | Property registry certificate; mandatory in ROFR cases | — |
| **ITBI** | Municipal property-transfer tax | — |
| **FGTS** | Employee severance guarantee fund; can be used to top up payment | — |
| **EN / Negotiation Executive** | Internal agent who mediates offer negotiation | `fact_offers.sk_closing_specialist` (filter `<> -1`) |
| **SPOC** | Single Point of Contact — the ops agent who supports the customer during EoP | Salesforce; not mapped in the DW |
| **Corban** | Loan correspondent who intermediates financing. **Internal Corban** (~14% of financing cases) or **Partner Corban** (~86%). | `dw_atta.fact_pre_analysis_proposal_flow` → `franchise_name LIKE '%Quinto Andar%'` = Internal Corban |
| **CRN / Cartório de Notas** | Notary office that executes the deed on the Cash track | — |
| **IQ / Interveniente Quitante** | Payoff to the prior lender on the Mortgage track | — |
| **Credit Model** | Financing model | `dim_sale_agreement.credit_model` |
| **Payment Method** | Payment method of the transaction | `dim_sale_agreement.payment_method` |
| **Domi / Vandinha** | Conversational AI agent under development to support EoP | — |
| **TIC / Termo de Intermediação Compartilhada** | Mandatory contractual document on FS Marketplace transactions mediated by partner real-estate agencies (`payment_model = 'CLOSING_3P'` — TSC and CQA programs). Formalizes the agency's role as intermediary responsible for due diligence, CCV, and after-sale. Generated via contract-filler and signed by the parties. Creation and upload can be done by the agency in the CDI (Central da Imobiliária) or, in the legacy flow, by an expert in Vendas. **Exclusive to 3P offers** — never appears in 1P transactions (`CCV_ASSISTANCE_CASH` or `CCV_ASSISTANCE_FINANCED`). | `datalake_sales_flow_clean.tic`, `datalake_sales_flow_raw.tic` |
| **TIC\_CLOSING\_CASH / TIC\_CLOSING\_FINANCED** | ClosingTypes created for 3P offers with `payment_model = CLOSING_3P`. Determine that the TIC step is mandatory in the sales flow status list. `TIC_CLOSING_CASH` for cash payment; `TIC_CLOSING_FINANCED` for financed. | `datalake_sales_flow_clean.sales_flow` (`closing_type`) |
| **CDI / Central da Imobiliária** | App used by partner agencies to manage leads, visits, and offers. Main channel for creating/uploading the TIC in the new 3P flow. Counterpart to Vendas (internal). | — |
| **Lego Contract** | Automated CCV validation and generation system (Legal Ops). Receives data from the SalesFlow form (property, buyers, sellers) and documents submitted by the EN, extracts information from the documents via API, and compares it against the form data. The result of each validation (assessment) is shown in the SalesFlow Copilot/Drawer for analyst review. | `datalake_legalops_clean.contract_analysis_request`, `datalake_legalops_clean.lego_analysis_results` |
| **Contract Analysis** | The process by which LegoContract automatically analyzes contract data. Every contract has at least one mandatory analysis; analysts can trigger additional analyses on demand. Each run returns a JSON result with assessments per section (house, buyers, sellers). | `datalake_legalops_clean.contract_analysis_request` |
| **Lego Assessment** | Atomic unit of validation within a contract analysis. Each assessment checks a specific rule (e.g. `house_address_number`, `seller_is_house_holder`) and returns a `validation_id` (e.g. H05, SL01, B01), an `assessment_status`, and an `assessment_consolidated_status`. | `datalake_legalops_clean.lego_analysis_results` |
| **Legaut** | Internal system for Due Diligence automations and crawlers | — |

> **CCV cancellation reasons** — `dim_sale_agreement.sale_agreement_cancellation_reason`:
> - Buyer Desistiu
> - Seller Desistiu
> - Reprovado Crédito
> - Reprovado Diligência
> - Modelo QA
> - COVID
> - Não se Aplica

---

## Tables

### Main Tables

| Table | Schema | Grain | Use |
|--------|--------|-------|-----|
| `fact_offers` | `dw_sale` | 1 row per offer | All EoF events (timestamps), brokerage_fee, sale_price_agreed, 3P flags |
| `dim_offer` | `dw_sale` | 1 row per offer | offer_status (17 states), drop_reason, drop_reason_responsible, offer_flow, is_a_rescued_offer, **`tags_from_salesflow`** (legacy Casa Mineira flow filters — this column lives **here**, not on `dim_sale_agreement`) |
| `dim_sale_agreement` | `dw_sale` | 1 row per offer that reached the agreement stage | CCV attributes: payment_method, credit_model, is_ccv_canceled, cancellation_reason, *_dilligence_status, payment_model (1P filter) |
| `offer_specialists` | `datalake_sale_offer_flows` | 1 row per offer (`id_offer`) | **Source of truth for specialist assignment** across the funnel (Deal Maker/consultant, team lead, PRE/POST/CREDIT/MORTGAGE_START-FUP-END/CRN/CRI/LEGAL_RISK/AGENT/POST_DD), always with the most recent specialist per type. No DW equivalent with comparable usage (`dim_sale_offer_user*` has residual use) — use this table for team assignment and performance. |
| `sale_offer_status` | `datalake_sale_offer_flows` | 1 row per (`id_sales_flow`, `id_status`) | Tracks the macro/micro-status position and closing_type of each offer's closing funnel, sourced from the SalesFlow `status`/`status_record`/`status_order`/`closing_type` tables. Use to measure time spent at each stage. `macro_status_name`/`last_micro_status_name` come from a business-configurable reference table, not a fixed code enum. |
| `fact_closing_flows` | `dw_sale` | 1 row per closing flow | **Primary EoP source.** CD event (`sk_legal_analysis_ended_date`), all pre-computed lead times, EoP stage dates |
| `fact_sale_demand_event` | `dw_sale` | 1 row per event per buyer | **Correct source for # BP.** Filter `event_name = 'VISIT_BOOKED'`, `is_3p_demand = false` |
| `sale_demand_events` | `datalake_sale_demand_events` | 1 row per key event per buyer/house | ⚠️ **Do not confuse with `dw_sale.fact_sale_demand_event` above — they are parallel pipelines, not the same source.** This enrich table is built from `datalake_sale_visit.sale_visit` + `datalake_sale_offer.sale_offer` (a schema distinct from the main Sales Flow); the DW `fact_sale_demand_event` comes from `dw_sale.fact_visits`/`fact_offers`. Same event taxonomy (8 types via `sk_event_type`/`event_name`), but **do not join the two tables directly** assuming they are the same thing. |
| `dim_sale_event_type` | `dw_sale` | Reference | event_name catalog (8 types). Join via `sk_event_type`. |
| `dim_buyer_prospect_type` | `dw_sale` | BP dimension | NBP / RBP, city_group, price_segment. Time-windowed via `ts_activation`/`ts_activation_end`. |
| `fact_buyer_prospects` | `dw_sale` | 1 row per buyer | Lifetime OBT per buyer. Columns: `offers_submitted`, `offers_accepted`, `sale_agreements_signed`, pre-computed `days_*`. ⚠️ Do NOT use for `# BP`. |
| `fact_visits` | `dw_sale` | 1 row per visit | Bridge via `sk_booking` (1:N with `fact_offers`). ⚠️ `fact_visits.sk_offer` = only the first offer per booking — do not use it to enumerate offers. |
| `fact_sale_flows` | `dw_sale` | 1 row per buyer-house pair (`sk_sale_flow`) | **Pre-offer** discovery journey (visit, talk-to-agent, booking) per buyer/house pair, with marketing attribution (UTM, app, channel). Complements `fact_offers`/`fact_visits` for demand-funnel analyses upstream of offer submission. |
| `fact_pre_analysis_proposal_flow` | `dw_atta` | 1 row per proposal (join: `sk_offer`) | Internal Corban identification: `franchise_name LIKE '%Quinto Andar%'`. Use the most recent record: `ROW_NUMBER() OVER (PARTITION BY sk_offer ORDER BY ts_last_updated DESC) = 1`. |
| `dim_franchise_atta` | `dw_atta` | Franchise dimension | Join via `sk_franchise` from `fact_pre_analysis_proposal_flow`. |
| `dim_proposal_atta` | `dw_atta` | 1 row per proposal (`sk_proposal`) | Atta financing-proposal dimension: bank, product, credit/legal analyst, current status/situation, declared and appraised property values, sales channel. Referenced by `fact_pre_analysis_proposal_flow` via `sk_proposal`. |
| `fact_nps_dispatches` | `dw_customer_satisfaction` | 1 row per NPS dispatch | Join `dim_nps_answer` via `sk_nps_answer`. Key columns: `sk_offer`, `sk_nps_campaign`. |
| `dim_nps_answer` | `dw_customer_satisfaction` | 1 row per NPS answer | `score_category` (promoter/detractor/neutral), `ts_answered`, `is_answered`, `metric_group`. |
| `fact_closing_offer_partners` | `dw_sale` | Partner attribution | Used in the Attach Rate dataset (18841). |
| `dim_closing_offer_partner` | `dw_sale` | 1 row per `sk_offer` with an Atta proposal | Snapshot of the most advanced financing proposal and the ("Corban") partner per offer — same Internal/Partner Corban logic as the glossary (see [Glossary and Synonyms](#glossary-and-synonyms)). `sk_offer` shared with `fact_offers`/`fact_closing_flows`; `sk_pre_analysis` links to `fact_pre_analysis_proposal_flow`. Pairs with `fact_closing_offer_partners` above for attach rate/partner attribution. |
| `dim_region` | `dw_public` | Region dimension | neighborhood, city, UF. Join via `sk_region`. |
| `dim_date` | `dw_public` | Date dimension | `sk_date`, `month_start`, `year`. For EoP time slices, join on the `sk_*` of the stage of interest (e.g. CRI → `sk_house_registry_ended_date = dd.sk_date`) and filter `dd.year`. |
| `fact_tickets` | `dw_customer_support` | Zendesk tickets | Join via `sk_sale_offer`. `group_name` = queue (classifies division). |
| `dim_ticket` | `dw_customer_support` | Ticket attributes | `group_name`, `subject`. |
| `closing_flow` | `datalake_sale_closing_flows` | Raw EoP (datalake layer) | Prefer `dw_sale.fact_closing_flows` for DW analyses. |
| `contract_analysis_request` | `datalake_legalops_clean` | 1 row per analysis run | Raw source of LegoContract analyses. Contains the full `contract_analysis_result` JSON with all nested assessments. Use `status = 'DONE'` to filter completed analyses. |
| `lego_analysis_results` | `datalake_legalops_clean` | 1 row per assessment per id_sales_flow per analysis run | **Custom clean table** produced by the `dags/for_sale/legalops_custom` DAG. Reads directly from `datalake_legalops_raw.contract_analysis_request` and explodes the `full_analysis` JSON into one row per assessment. Primary source for LegoContract performance metrics (reliability, failure rate, evolution by validation_id). Join with EoF tables via `id_sales_flow`. |
| `ai_legal_analysis_lego_contract_execution` | `datalake_sales_flow_clean` | 1 row per Lego Contract execution | Bridge table between the change log and the sales flow. Contains `id` (PK), `id_legocontract_execution`, and `id_sales_flow` (FK to the sales flow / offer). Use to obtain `id_sales_flow` from change-log records. |
| `ai_legal_analysis_lego_contract_execution_change_log` | `datalake_sales_flow_clean` | 1 row per autonomous field replacement | Records replacements made by **Lego Contract Autonomous Mode**: a row is generated when the value submitted by the analyst in Vendas (or left blank) differs from the value generated by the AI — **only for high-confidence assessments**. ⚠️ Manual edits made directly by analysts in Vendas are **not** captured here. Each row records `type` (section, e.g. `HOUSE_ANALYSIS`), `field`, `old_value` (the analyst's value/blank) and `new_value` (the value substituted by the AI). Join: `id_legocontract_execution → datalake_sales_flow_clean.ai_legal_analysis_lego_contract_execution.id` to obtain `id_sales_flow`. Known `HOUSE_ANALYSIS` fields: `house_acquisition_type`, `house_has_fiduciary_lien`, `house_was_fgts_used`, `house_property_lien`, `house_social_housing`, among others. |
| `tic` | `datalake_sales_flow_clean` | 1 row per TIC per sales flow | **Exclusive to 3P offers** (`payment_model = 'CLOSING_3P'`, closing types `TIC_CLOSING_CASH` / `TIC_CLOSING_FINANCED` — TSC and CQA programs). Each row represents the lifecycle of a Termo de Intermediação Compartilhada: generation via contract-filler, review by the agency in the CDI, and final upload alongside the CCV. Main columns: `id_sales_flow` (FK → `datalake_sales_flow_clean.sales_flow`), `uuid_signed_document_reference` and `uuid_unsigned_document_reference` (BlobVault objectIds in the `sales-flow-tic` bucket), `status` (`CREATED` → `SIGNED`), `signed_document_origin` (`CDI` = direct upload by the agency in the CDI; `VENDAS` = upload via the internal Vendas backoffice, either through the legacy expert flow or at the agency's request via support channels), `template_version`. Aligns with the `TIC` macrostatus and `TIC_CREATED` / `TIC_SIGNED` microstatuses of the sales flow. For change history, use `datalake_sales_flow_clean.tic_aud`. |
| `tic_aud` | `datalake_sales_flow_clean` | 1 row per Envers revision of the TIC | Hibernate Envers audit history of the TIC entity. Each row is a revision of a `tic` record, tracking `status` transitions (CREATED → SIGNED), changes to document references, and upload origin. Join `rev` → `datalake_sales_flow_clean.revinfo.id` to obtain the revision timestamp and author. `mod_*` columns indicate whether the field changed in that revision. Use for point-in-time analysis of the TIC document lifecycle. |
| `offer` | `datalake_sales_flow_clean` | 1 row per offer | CDC replica of the Sales Flow database's `offer` table. Use `uuid_actor` and `actor_type` to identify whether the offer was submitted directly by the buyer (`NULL`) or by a broker via the **Offer by Agent** feature (`actor_type = 'AGENT'`, `uuid_actor` = the broker's UUID). Prefer `dw_sale.fact_offers` for EoF analyses; query this table directly only for the `uuid_actor`/`actor_type` fields while they are not surfaced in the DW. Join with `fact_offers` via `id` → `id_sales_flow`. |
| `offer_aud` | `datalake_sales_flow_clean` | 1 row per Envers revision of the offer | Hibernate Envers audit history of the `offer` entity. Each row is a revision of an `offer` record, tracking changes to status, prices, and actors. `mod_*` columns indicate whether the field changed in that revision. Use `uuid_actor`/`actor_type` and `mod_uuid_actor`/`mod_actor_type` to track changes to the offer's actor. Join `rev` → `datalake_sales_flow_clean.rev_info.id` to obtain the revision timestamp. |

> ⚠️ `dim_sale_agreement` only has rows for offers that **reached the agreement stage**. Always LEFT JOIN from `fact_offers`.

### Key columns on `fact_offers`

| Column | Type | Description |
|--------|------|-----------|
| `ts_offer_submitted` | timestamp | OS event |
| `ts_offer_accepted` | timestamp | OA event |
| `ts_offer_dismissed` | timestamp | OR event |
| `ts_offer_canceled` | timestamp | Offer cancellation |
| `ts_sale_agreement_drafted` | timestamp | CCVe |
| `ts_sale_agreement_created` | timestamp | SAC event |
| `ts_sale_agreement_signed` | timestamp | **CCV — commercial milestone** |
| `ts_sale_agreement_canceled` | timestamp | Post-signature cancellation |
| `brokerage_fee` | numeric | Brokerage fee |
| `sale_price_agreed` | numeric | Agreed sale price |
| `days_offer_submitted_to_offer_accepted` | integer | Pre-computed LT OS→OA |
| `days_offer_accepted_to_sale_agreement_signed` | integer | Pre-computed LT OA→CCV |
| `is_buyer_first_offer` | boolean | Buyer's first offer |
| `is_house_first_offer` | boolean | Property's first offer |
| `has_completed_visit_before_offer` | boolean | Visited before offering |
| `is_3p_demand` / `is_3p_lead_gen` / `is_3p_supply` | boolean | 3P attribution flags |
| `sk_buyer` | bigint | FK → `dw_public.dim_user` |
| `sk_house` | bigint | FK → `dw_house.dim_house` |
| `sk_booking` | bigint | FK → `dw_sale.fact_visits` |
| `sk_broker_demand` | bigint | The broker who brought the buyer. See `broker_xp.md`. |
| `sk_broker_supply` | bigint | The broker who owns the listing. See `broker_xp.md`. |
| `sk_region` | bigint | FK → `dw_public.dim_region` |
| `sk_closing_specialist` | bigint | EN — filter `<> -1` for assigned |

### Pre-computed columns on `fact_closing_flows`

Use these to avoid manual date-difference calculations:

| Column | Meaning |
|--------|-------------|
| `sk_legal_analysis_ended_date` | **CD event** — the date the Closed Deal was reached (DD + TC). Primary anchor for the CD metric. |
| `sk_house_registry_ended_date` | CRI date (ownership transfer). Primary anchor for EoP LT. |
| `sk_sale_agreement_signed_date` | CCV signature date. |
| `sk_credit_analysis_ended_date` | Credit approval date. |
| `sk_financing_ended_date` | Financing contract signature date. |
| `days_sale_agreement_signed_to_house_registry_ended` | **LT CCV→CRI** (total EoP LT). Pre-computed in days. |
| `days_sale_agreement_signed_to_credit_analysis_ended` | LT CCV→credit approved. |
| `days_credit_analysis_ended_to_financing_started` | LT between credit approval and financing start. |
| `days_financing_started_to_financing_ended` | LT of the financing stage. |
| `days_financing_ended_to_house_registry_ended` | LT from financing end to CRI. |
| `days_sale_agreement_signed_to_legal_analysis_ended` | LT CCV→CD. |

### Columns in `lego_analysis_results` (`datalake_legalops_clean`)

Grain: 1 row per assessment per `id_sales_flow` per `analysis_date`. The same `id_sales_flow` can have multiple rows per day if more than one analysis was run (on-demand analyst analyses generate new records).

| Column | Type | Description |
|--------|------|-----------|
| `id_sales_flow` | string | FK to the sales flow (contract). Join with `fact_offers` and other EoF tables via this field. |
| `analysis_date` | date | Analysis creation date (`DATE(ts_created)` from `contract_analysis_request`). |
| `validation_id` | string | Validation-rule ID (e.g. `H05`, `SL01`, `B01`). Identifies which check was run. |
| `assessment_name` | string | Descriptive assessment name (e.g. `house_address_number`, `seller_is_house_holder`, `is_non_residential_suspicion`). |
| `assessment_status` | string | Granular status returned by LegoContract (e.g. `MATCH`, `CHECK_PASS`, `CHECK_WARNING`, `DIFFERENT`). |
| `assessment_consolidated_status` | string | Consolidated assessment status: `OK`, `ACTION_NEEDED`, or `UNAVAILABLE`. Main quality metric. `UNAVAILABLE` indicates the assessment could not produce a conclusive result — typical causes: (1) **Out of scope** (rules B00/SL00/NG00 excluded the validation; dependent rules emit `BLOCKED`, also `UNAVAILABLE`); (2) **Missing inputs** (`MISSING_SALES_FLOW_VALUE` — form data not filled in; `MISSING_EXTRACTION_VALUE` — document value missing); (3) **Extraction issues** (`LOW_QUALITY_EXTRACTION`, `CONTENT_FILTER_REFUSED`; `NOT_EXTRACTED` maps to `ACTION_NEEDED`, not `UNAVAILABLE`); (4) **Execution failures** (`BLOCKED` due to a blocking dependency, `ERROR` due to an unhandled exception); (5) **CCV ambiguity** (`TOO_MANY_CLAUSES` — more than one matching CCV clause for the same subject). |
| `assessment_confidence` | string | Validation confidence level: `HIGH`, `MEDIUM`, or `LOW`. |

**Assessment sections:** the table aggregates assessments from 5 sections of the LegoContract JSON:
- `house` — property validations
- `buyers.section_assessments` — buyer-section validations (aggregate level)
- `sellers.section_assessments` — seller-section validations (aggregate level)
- `buyers.parties[*].assessments` — validations per individual buyer
- `sellers.parties[*].assessments` — validations per individual seller

**Join with EoF:** `id_sales_flow` is the join key. To obtain the `id_offer` key from `id_sales_flow`, the `datalake_sale_offer.sale_offer` table can be used. In `fact_offers`, the corresponding column can be derived via `dim_sale_agreement` (which has id_offer) or salesflow tables. Confirm the correct join column before crossing with the DW.

> ⚠️ **Important grain note:** an `id_sales_flow` with on-demand analyses will have multiple rows per `analysis_date` and per `assessment_name`. For "latest analysis" metrics, filter by the maximum `analysis_date` per `id_sales_flow`.

### Event names in `dim_sale_event_type`

| sk_event_type | event_name |
|---------------|-----------|
| 1 | VISIT_BOOKED |
| 2 | VISIT_COMPLETED |
| 3 | OFFER_SUBMITTED |
| 4 | OFFER_ACCEPTED |
| 5 | SALE_AGREEMENT_CREATED |
| 6 | SALE_AGREEMENT_SIGNED |
| 7 | VISIT_CANCELLED |
| 8 | OFFER_REJECTED |

### Seller Discount — Correct Fields

The discount represents the difference between the **listing price** (the price asked by the owner) and the **price agreed in the CCV** after negotiation.

#### ⚠️ `dw_sale.dim_listing.price` is NOT the contract price

`dim_listing.price` reflects the listing's current publication price, sourced via CDC from the `imovel.salePrice` field in EBDB (~30 min delay). **It is not updated when an offer is accepted or the CCV is signed.** Using it directly against `sale_price_agreed` produces incorrect comparisons because it captures different points in time.

#### Correct fields for discount analysis

| Field | Table | Description |
|-------|--------|-----------|
| `sale_price` | `dw_sale.dim_offer` | Listing price captured at the moment of the offer (snapshot) |
| `sale_price_agreed` | `dw_sale.dim_sale_agreement` | Final price agreed in the CCV |
| `first_price_offered_by_buyer` | `dw_sale.fact_offers` | Buyer's first proposal |
| `last_price_offered_by_buyer` | `dw_sale.fact_offers` | Buyer's last proposal |
| `first_discount_proposed` | `dw_sale.fact_offers` | `(sale_price - first_price_offered_by_buyer) / sale_price` |
| `last_discount_proposed` | `dw_sale.fact_offers` | `(sale_price - last_price_offered_by_buyer) / sale_price` — for accepted offers, equivalent to the effective discount granted |
| `max_discount_proposed` | `dw_sale.fact_sale_flows` | Largest discount proposed across the whole flow — includes rejected offers; not the effective discount of closed deals |

### Salesforce CDC Tables (`datalake_salesforce_clean`)

Four Change Data Capture (CDC) tables from Salesforce feed the EoF operational context. Each row represents **one change event** on a Salesforce record — not the record's current state.

#### ⚠️ CDC Behavior — Read Before Querying

**Default behavior (Sparse CDC):** on UPDATE events, only the fields that changed are populated — all others remain NULL. On CREATE events, all fields are populated. To reconstruct a record's current state, all events must be aggregated per `id_record` ordered by `id_replay`.

**Exception:** `events_incident` sends the full state on every event (it is not sparse).

**`commit_ts`** is always an epoch timestamp in **milliseconds** (e.g. `1781127243000`). Use `TIMESTAMP_MILLIS(commit_ts)` or divide by 1000 to convert. `committed_at` is already derived and formatted as `YYYY-MM-DD HH:MM:SS` UTC.

**`id_replay`** is the monotonic cursor used to order CDC events. Use `ORDER BY id_replay` to sequence events for the same record.

#### `events_pendency` — Requests (Pendency__c)

**Grain:** 1 row per CDC event of a Pendency__c record.

**What it is:** Communication between ENs (Negotiation Executives) and CRN partners during the purchase-and-sale journey. Created manually by the EN or automatically by the system.

| Column | Type / Values | Note |
|--------|----------------|------------|
| `id_record` | string (`a0G...`) | Pendency__c record ID |
| `id_replay` | bigint | CDC cursor — use to order events |
| `event_type` | string | `CREATE` (all fields populated, `status__c='Nova'`); `UPDATE` (sparse, only changed fields) |
| `commit_ts` | bigint | Milliseconds epoch |
| `committed_at` | string | `YYYY-MM-DD HH:MM:SS` UTC |
| `status__c` | string | `Nova` (initial state on CREATE) → `Concluída` (resolved). NULL if unchanged. |
| `open_source__c` | string | `Manual` (created by the EN); `Automation` (Salesforce automation). NULL if unchanged. |
| `pendency_type__c` | string | E.g. `Solicitação de contato (Parceiro ao cliente)`. NULL if unchanged or undefined. |
| `comments__c` | string | HTML text of the request (written by the EN). NULL if unchanged. |
| `comment_response__c` | string | HTML text of the response (written by the CRN). NULL if unchanged. |
| `solicitacao_data_de_conclusao__c` | string | Completion date — NULL on CREATE; populated on UPDATE when `status__c='Concluída'`. |
| `caso__c` | string (`500b...`) | FK → `events_case` |
| `purchase_sale_contract__c` | string (`a0H...`) | FK → `purchase_sale_contract` |
| `offer_id__c` | string | Equivalent to `sk_offer` in `dw_sale.dim_sale_agreement` |
| `id_created_by` / `id_last_modified_by` | string (`005b...`) | FK → `users` |

**Reconstructing current state:**
```sql
-- Current state of each pending request (latest value of each field per id_record)
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY id_record, 'status__c'
               ORDER BY id_replay DESC
           ) AS rn
    FROM datalake_salesforce_clean.events_pendency
    WHERE status__c IS NOT NULL
)
SELECT id_record, status__c, committed_at
FROM ranked WHERE rn = 1
```

**Count of pending requests by status for a case:**
```sql
SELECT
    caso__c,
    status__c,
    COUNT(DISTINCT id_record) AS total_pendencias
FROM (
    SELECT id_record, caso__c, status__c,
           ROW_NUMBER() OVER (PARTITION BY id_record ORDER BY id_replay DESC) AS rn
    FROM datalake_salesforce_clean.events_pendency
    WHERE status__c IS NOT NULL
      AND caso__c IS NOT NULL
) t
WHERE rn = 1
GROUP BY 1, 2
```

#### `events_received_document` — Document Request (ReceivedDocument__c)

**Grain:** 1 row per CDC event of a ReceivedDocument__c record.

**What it is:** Request for additional documents from buyers or sellers during the purchase-and-sale process. Status lifecycle: `Solicitado` → `Enviado` → `Aprovado`.

| Column | Type / Values | Note |
|--------|----------------|------------|
| `id_record` | string (`a0q...`) | ReceivedDocument__c record ID |
| `id_replay` | bigint | CDC cursor |
| `event_type` | string | `CREATE` (all fields populated, `status__c='Solicitado'`); `UPDATE` (sparse, typically only `status__c` changes) |
| `commit_ts` | bigint | Milliseconds epoch |
| `committed_at` | string | `YYYY-MM-DD HH:MM:SS` UTC |
| `status__c` | string | `Solicitado` → `Enviado` → `Aprovado`. NULL if unchanged. |
| `requested_document_for__c` | string | `Comprador` or `Vendedor` |
| `received_document__c` | string | E.g. `Matrícula completa do imóvel`, `Extrato do FGTS`, `Outros` |
| `fs_request_justification__c` | string | Plain text (not HTML). Justification for the request. |
| `opportunity__c` | string (`006b...`) | FK → `opportunity`. Used at the **pre-contract** stage (e.g. FGTS/financing analysis). **Mutually exclusive with `purchase_sale_contract__c`**. |
| `purchase_sale_contract__c` | string (`a0H...`) | FK → `purchase_sale_contract`. Used at the **post-contract** stage. **Mutually exclusive with `opportunity__c`**. |
| `caso__c` | string (`500b...`) | FK → `events_case` |
| `id_owner` / `id_created_by` | string (`005b...`) | FK → `users` |

#### `events_incident` — Incidents (Incident)

**Grain:** 1 row per CDC event of an Incident record.

**What it is:** Groups multiple pending-request notes for a Legal Ops case. Each incident brings together pending items from different parties (buyer, seller, property, negotiation) into a single record.

> ⚠️ **Critical difference:** `events_incident` is **not sparse**. Both CREATE and UPDATE send the **full state** on every event — all fields are populated.

| Column | Type / Values | Note |
|--------|----------------|------------|
| `id_record` | string (`0ny...`) | Incident record ID |
| `id_replay` | bigint | CDC cursor |
| `event_type` | string | `CREATE` (`status='ACTIVE'`); `UPDATE` (full state — not sparse) |
| `commit_ts` | bigint | Milliseconds epoch |
| `committed_at` | string | `YYYY-MM-DD HH:MM:SS` UTC |
| `status` | string | `ACTIVE` (open) → `Resolved` (resolved) |
| `subject` | string | Always `Pendência` |
| `impact` / `priority` / `urgency` | string | Observed as `High` / `Critical` / `High` |
| `is_closed` | boolean | Always `false` in observed data |
| `resolution_date_time` | string | NULL when `status='ACTIVE'`; populated when `status='Resolved'` |
| `pendency_notes__c` | string | Concatenated plain text. Each note is prefixed with a role (`HOUSE`, `SELLER`, `BUYER`, `NEGOTIATION`, `NOTE`) followed by `:`. Multiple notes separated by ` \|\| `. |
| `incident_number` | string | E.g. `INC-000003779` |
| `case_legal_ops__c` | string (`a14...`) | FK → `events_case_legal_ops` |
| `case__c` | string (`500b...`) | FK → `events_case` |
| `id_owner` / `id_created_by` / `id_last_modified_by` | string (`005b...`) | FK → `users` |

**Pending notes by category (prefix parsing):**
```sql
SELECT
    id_record,
    status,
    committed_at,
    -- Extracts the role prefix: HOUSE, SELLER, BUYER, etc.
    REGEXP_EXTRACT(note_part, '^([A-Z]+):', 1) AS role,
    TRIM(REGEXP_REPLACE(note_part, '^[A-Z]+:\s*', ''))   AS note_text
FROM datalake_salesforce_clean.events_incident
CROSS JOIN UNNEST(SPLIT(pendency_notes__c, ' || ')) AS t(note_part)
WHERE event_type = 'UPDATE'
  AND status = 'ACTIVE'
```

#### `events_case_legal_ops` — Legal Ops Cases (CaseLegalOps__c)

**Grain:** 1 row per CDC event of a CaseLegalOps__c record.

**What it is:** A Legal Ops case created when an EN sends the offer to a Legal Analyst for contract analysis and due diligence. Each case is created with `status__c='Aberto'` and progresses as the analysis moves forward.

| Column | Type / Values | Note |
|--------|----------------|------------|
| `id_record` | string (`a14...`) | CaseLegalOps__c ID |
| `id_replay` | bigint | CDC cursor |
| `event_type` | string | `CREATE` (most fields populated, `status__c='Aberto'`); `UPDATE` (sparse) |
| `commit_ts` | bigint | Milliseconds epoch |
| `committed_at` | string | `YYYY-MM-DD HH:MM:SS` UTC |
| `status__c` | string | `Aberto` (initial state), `Oferta Cancelada`. NULL if unchanged. |
| `queue__c` | string | `Front`, `Back`, `Confecção`, `Docs`. Set on CREATE. NULL if unchanged. |
| `risk_classification__c` | string | `Sem apontamentos`, `Baixo`. NULL if unchanged. |
| `dilligence_sent_date__c` | string | Due-diligence send date (`YYYY-MM-DD`). NULL if unchanged. |
| `delay_reason__c` | string | E.g. `Não Aplicável (dentro do SLA)`. NULL if unchanged. |
| `front_complexity_level__c` | string | E.g. `Não vai para Front`. NULL if unchanged. |
| `dilligence_scope__c` | string | E.g. `New DD`. NULL if unchanged. |
| `inscription_link__c` | string | `Sim` when the matrícula link is available (text, not a URL). NULL if unchanged. |
| `error_type__c` | string | E.g. `Inclusão de partes`. NULL if unchanged. |
| `reasons_changes__c` | string | List of change reasons separated by `;`. E.g. `Qualificação: Dados Incorretos;Preços e Condições`. NULL if unchanged. |
| `number_change__c` | double | Change counter for the case. |
| `reopen_date__c` | string | Case reopening date. NULL if unchanged. |
| `contract__c` | string (`800b...`) | FK → `contract` |
| `id_owner` / `id_created_by` | string (`005b...`) | FK → `users` |
| `deadline_extension__c` | string | Deadline extension granted. NULL if unchanged. |
| `ccv_sent_date2nd__c` | string | Date the CCV was sent for the second time. |
| `had_ccv__c` | boolean | Flag for whether the case had a CCV. |

**Open cases by queue and risk_classification (current state):**
```sql
WITH latest_status AS (
    SELECT id_record,
           FIRST_VALUE(status__c) IGNORE NULLS OVER (
               PARTITION BY id_record ORDER BY id_replay DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS current_status,
           FIRST_VALUE(queue__c) IGNORE NULLS OVER (
               PARTITION BY id_record ORDER BY id_replay ASC
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS initial_queue,
           FIRST_VALUE(risk_classification__c) IGNORE NULLS OVER (
               PARTITION BY id_record ORDER BY id_replay DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
           ) AS latest_risk,
           ROW_NUMBER() OVER (PARTITION BY id_record ORDER BY id_replay DESC) AS rn
    FROM datalake_salesforce_clean.events_case_legal_ops
)
SELECT
    initial_queue,
    latest_risk,
    COUNT(*) AS total_casos
FROM latest_status
WHERE rn = 1
  AND current_status = 'Aberto'
GROUP BY 1, 2 ORDER BY 3 DESC
```

---

## Key Metrics

Use [Related Metric Entities](#related-metric-entities) when the question asks for an **official**, listing-cohort conversion rate (L2VB/L2VC/L2OS/L2CCV). The bullets below are FS Transact's own **component/exploratory** metrics — full formulas, statuses, benchmarks, and dashboard links live in the [EoF Metrics](#eof-metrics) and [EoP Metrics](#eop-metrics) subsections below.

### Official metrics (metric entities)

| When you need… | Metric entity |
|----------------|---------------|
| L2VB, L2VC, L2OS, L2CCV (listing-cohort conversions) | [Listing Demand Funnel Conversions](../metric_entities/listing_demand_funnel_conversions.md) |

### Component / exploratory metrics

- **EoF pipeline & conversion** — `# CCV`, `CD`, `OS2CCV`, `OS2OA`, `CCV2CD`, average CCV/CD ticket, effective seller discount, EoF lead times (`LT OS2OA`, `LT OA2CCV`, `LT CCV2CD`, `LT OS2CD`), NPS CCV, and BP cohort conversions (`BPOS2BPCCV`, etc.) — see [EoF Metrics](#eof-metrics) below for formulas, benchmarks, and dashboards.
- **EoP post-closing** — Lead Time by payment track (Cash / Internal Corban / Mortgage w/ Partners), NPS EoP, DSAT and Resolution Rate, Attach Rate and Share Routed to IC — see [EoP Metrics](#eop-metrics) below for formulas, filters, and dashboards.

### EoF Drop Attribution

~50% of drops are actionable (the rest are non-actionable: buyer decided to rent, seller closed with someone else, etc.):

| Driver | % of actionable drops | Stage |
|--------|------------------------|---------|
| Negotiation friction / price misalignment | ~17 pp | Concentrated in OS→OA |
| Financial barriers (credit rejection, funding mismatch, down payment, FGTS) | ~12 pp | OA→CCV (9pp) + post-CCV (2.5pp) |
| Documentation / legal issues (property hard-blocks, pending items, DD) | ~8 pp | OA→CCV (5pp) + post-CCV (3pp) |

Of **post-CCV cancellations**: ~37% are caused by credit rejection.

### EoF Metrics

| Metric | Status | Formula / Source | Benchmark | Dashboard |
|---------|--------|-----------------|-----------|-----------|
| `# CCV` | ✅ | `COUNT(DISTINCT sk_offer) WHERE sk_sale_agreement_signed_date > 0` — `fact_offers` | — | [Fibonacci](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=NCV4qOpFaqbK2BnCnpRNn7Cxw-0yWw-TY6PXZYsIRmvWCNPHjQZaXs-RcTCPWaZh) |
| `CD` | ✅ | Product: `COUNT(DISTINCT sk_offer) WHERE sk_legal_analysis_ended_date > 0` — `fact_closing_flows`. Finance official (incl. Bypass exclusion): `datalake_gsheets_clean.closed_deals` with `contract_group <> 'Bypass'`. | — | [Fibonacci](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=NCV4qOpFaqbK2BnCnpRNn7Cxw-0yWw-TY6PXZYsIRmvWCNPHjQZaXs-RcTCPWaZh) |
| `OS2CCV` | ✅ | `COUNT(ts_sale_agreement_signed IS NOT NULL) / COUNT(ts_offer_submitted IS NOT NULL)` — `fact_offers` | ~40% (BP OS2CD) | — |
| `OS2OA` | ✅ | `COUNT(ts_offer_accepted IS NOT NULL) / COUNT(ts_offer_submitted IS NOT NULL)` — `fact_offers` | ~60% | — |
| `OA2SO` | ✅ | `SUM(Contagem_SO) / SUM(Contagem_oa)` — Dataset 18848 (`fact_offers` + `fact_closing_flows`) | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `SO2CCVe` | ✅ | `SUM(Contagem_CCVe) / SUM(Contagem_SO)` — Dataset 18848 | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `CCVe2CCVa` | ✅ | `SUM(Contagem_CCV_Assinado) / SUM(Contagem_CCVe)` — Dataset 18848 | — | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `CCV2CD` | ✅ | `SUM(Contagem_Closed_Deals) / SUM(Sale_Agreement)` WHERE `payment_model <> 'CLOSING_3P'` — Dataset 18848 | ~95% | [EoF Conv.](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| `% Distratos` | ✅ | `COUNT(is_ccv_canceled = TRUE) / COUNT(ts_sale_agreement_signed IS NOT NULL)` — `fact_offers` + `dim_sale_agreement` | — | — |
| `Ticket médio CCV` | ✅ | `AVG(sale_price_agreed) WHERE ts_sale_agreement_signed IS NOT NULL` — `fact_offers` | — | — |
| `Ticket médio CD` | ✅ | `AVG(sale_price_agreed)` — `fact_offers` JOIN `fact_closing_flows` | — | — |
| `% Desconto efetivo (seller discount)` | ✅ | `AVG(fo.last_discount_proposed) WHERE ts_offer_accepted IS NOT NULL` — `fact_offers`. See [Seller Discount — Correct Fields](#seller-discount--correct-fields) for concept and tables. | — | — |
| `% Desconto na 1ª proposta` | ✅ | `AVG(fo.first_discount_proposed) WHERE ts_offer_submitted IS NOT NULL` — `fact_offers` | — | — |
| `Desconto máximo na flow` | ✅ | `AVG(fsf.max_discount_proposed)` — `fact_sale_flows`. ⚠️ Includes flows with non-accepted offers. | — | — |
| `% Termo de corretagem` | ✅ | Numerator: CDs with TC; denominator: CCVs — `fact_closing_flows`. Confirm the TC flag name. | — | — |
| `LT OS2OA` | ✅ | `AVG(days_offer_submitted_to_offer_accepted)` — pre-computed column on `fact_offers` | ~2 days | — |
| `LT OA2CCV` | ✅ | `AVG(days_offer_accepted_to_sale_agreement_signed)` — pre-computed column on `fact_offers` | ~6 days | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT OS2CCV` | ✅ | Sum of the two above, or `AVG(ts_sale_agreement_signed - ts_offer_submitted)` | — | — |
| `LT CCV2CD` | ✅ | `AVG(days_sale_agreement_signed_to_legal_analysis_ended)` — `fact_closing_flows` (pre-computed). Filter: `is_ccv_canceled = FALSE`. Segment by `sub_division`. | ~10 days | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=1745870402) |
| `LT OS2CD` | ✅ | `AVG(DATE_DIFF('day', CAST(fo.ts_offer_submitted AS DATE), dd.date))` — `fact_closing_flows` JOIN `fact_offers fo` JOIN `dim_date dd ON fcf.sk_legal_analysis_ended_date = dd.sk_date`. ⚠️ Never subtract `sk_legal_analysis_ended_date` directly from `ts_offer_submitted` — `sk_*` is an integer surrogate key, not a timestamp. | — | — |
| `LT OA2SO` | ⚠️ | OA → SAC. Approximate via `fact_offers`. Confirm whether a business-day calendar is available. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT SO2CCVe` | ⚠️ | SAC → CCV draft. Same dependency. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `LT CCVe2CCVa` | ⚠️ | CCV draft → signed CCV. Same dependency. | — | [SLA Sheet](https://docs.google.com/spreadsheets/d/1b69z6hkWqhri5FDLwtDWu2EJzJ0RsgMLyy_9qFT_IUs/edit?gid=556290245) |
| `NPS CCV` | ⚠️ | `(promoters - detractors) / total * 100`. Filter: `metric_group IN ('buyerccv','sellerccv')` — `metric_group` lives on `dim_nps_campaign`, **not** on `dim_nps_answer`. Source: `dw_customer_satisfaction.fact_nps_dispatches` + `dim_nps_answer` + `dim_nps_campaign`. | ~75 | — |
| `NPS Buyer lost proposal` | ⚠️ | Same NPS source. `metric_group = 'buyerlostproposal'`. | ~22 | — |
| `BPOS2BPCCV` | ⚠️ | M0+M1 cohort: buyers with VISIT_BOOKED in month M with a CCV in M or M+1. Join `fact_sale_demand_event` + `fact_offers`. `fact_buyer_prospects` gives lifetime conversion — not usable for a monthly cohort. | — | — |
| `BPOS2BPOA` | ⚠️ | Same cohort approach, numerator = OA in M or M+1. | — | — |
| `BPOA2BPCCV` | ⚠️ | Buyers with VISIT_BOOKED + OA in month M; numerator = CCV in M or M+1. | — | — |
| `UC CCV` | ❌ | Cost source not mapped. Benchmark: ~R$250/CCV. | — | — |
| `UC DD` | ❌ | Cost source not mapped. Benchmark: ~R$250/DD. | — | — |
| `R$ Bypass Revenue` | ❌ | "Bypass" concept not defined. | — | — |

### EoP Metrics

#### Lead Time

| Metric | Status | Formula / Source | Benchmark | Dashboard |
|---------|--------|-----------------|-----------|-----------|
| `Lead Time Cash + IC` | ✅ | `AVG(days_sale_agreement_signed_to_house_registry_ended)` — `dw_sale.fact_closing_flows`. Filter: `is_ccv_canceled = FALSE AND sub_division IN ('INTERNAL CORBAN','CASH%')`. Anchor: `sk_house_registry_ended_date`. | Consolidated Cash+IC | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `Lead Time - Cash` | ✅ | Same column. Filter: `division = 'CASH' AND is_ccv_canceled = FALSE`. CASH = `payment_method IN ('CASH','CASH_USING_FGTS')`. | ~75.5d (CRN parceiro) / ~121.9d (no partner) | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Internal Corban` | ✅ | Filter: `sub_division = 'INTERNAL CORBAN' AND is_ccv_canceled = FALSE`. IC = `franchise_name LIKE '%Quinto Andar%'`. | ~100d | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Mortgage w/ Partners` | ✅ | Filter: `division = 'FINANCED' AND is_ccv_canceled = FALSE`. FINANCED = `payment_method LIKE '%FINANCED%' AND credit_model <> 'EXTERNAL'`. | ~127d | [DS 16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| `Lead Time - Cash w/ CRN Partner` | ❌ | CRN data not yet included in the dataset. | — | — |
| `Lead Time - Cash wo/ CRN Partner` | ❌ | Same. | — | — |

#### NPS EoP

Confirmed source: `dw_customer_satisfaction.fact_nps_dispatches` + `dim_nps_answer` + `dim_nps_campaign`. Formula: `(COUNT(DISTINCT CASE WHEN score_category = 'promoter' THEN sk_nps_answer END) - COUNT(DISTINCT CASE WHEN score_category = 'detractor' THEN sk_nps_answer END)) / NULLIF(COUNT(DISTINCT sk_nps_answer), 0) * 100`. Scope filter: `dim_nps_campaign.metric_group IN ('buyerendofprocess','sellerendofprocess')` — `metric_group` lives on `dim_nps_campaign`, **not** on `dim_nps_answer`. `is_answered` lives on `fact_nps_dispatches`. Segmenting by payment_method requires a LEFT JOIN to `dim_sale_agreement` via `disp.sk_offer` (direct join — `fact_offers` is not needed). CRN segmentation: `seguiu_com_cart_parceiro`. IC segmentation: `franchise_name` from `dw_atta.fact_pre_analysis_proposal_flow`.

| Metric | Status | Filter | Benchmark | Dashboard |
|---------|--------|--------|-----------|-----------|
| `NPS Cash + IC` | ✅ | `payment_method IN ('Internal Corban','Cash')` | ~45 (total EoP) | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `NPS - Cash` | ✅ | `payment_method IN ('Cash')` | 54.1 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Cash w/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro = 'Sim'` | 62.1 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Cash wo/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro <> 'Sim'` | 2.8 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Internal Corban` | ✅ | `payment_method IN ('Internal Corban')` | 29.6 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| `NPS - Mortgage w/ Partners` | ✅ | `payment_method IN ('Financed Internal')` | 36.6 | [DS 18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |

#### DSAT and Resolution Rate

Confirmed source: Dataset 18277 (`dw_atta` schema). Columns: `csat_score`, `resolution`, `id_response`, `response_date`, `payment_method`, `seguiu_com_cart_parceiro`. Formulas:
- **DSAT:** `COUNT(CASE WHEN csat_score IN (1,2) THEN 1 END) / NULLIF(CAST(COUNT(csat_score) AS DOUBLE), 0)`
- **Resolution Rate:** `COUNT(CASE WHEN resolution = 1 THEN 1 END) / NULLIF(CAST(COUNT(id_response) AS DOUBLE), 0)`

| Metric | Status | Main filter | Dashboard |
|---------|--------|-----------------|-----------|
| `DSAT - Cash` | ✅ | `payment_method = 'Cash'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) · [Polygon](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/?native_filters_key=qrFlLhJPBrGpXeHbk0hKesRA557cNDVxvqVx1_9vmAeePM1FKeo_63C9BBHu066x) |
| `DSAT - Cash w/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro = 'Sim'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Cash wo/ CRN Parceiro` | ✅ | + `seguiu_com_cart_parceiro <> 'Sim'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Internal Corban` | ✅ | `payment_method = 'Internal Corban'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Mortgage w/ Partners` | ✅ | `payment_method = 'Financed Internal'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `DSAT - Cash AI` | ❌ | "WIP" dataset — logic to identify AI cases not yet built. | — |
| `Resolution Rate - Cash` | ✅ | `payment_method = 'Cash'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `Resolution Rate - IC` | ✅ | `payment_method = 'Internal Corban'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| `Resolution Rate - Mortgage w/ Partners` | ✅ | `payment_method = 'Financed Internal'` | [DS 18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |

#### Attach Rate and Share IC

Source: Dataset 18841 (`dw_sale.fact_offers` + `dw_sale.dim_sale_agreement` + `dw_atta.fact_pre_analysis_proposal_flow` + `dw_atta.dim_franchise_atta`). Internal Corban = `franchise_name LIKE '%Quinto Andar%'`.

| Metric | Status | Formula | Dashboard |
|---------|--------|---------|-----------|
| `Attach Rate - IC` | ✅ | `SUM(CASE WHEN IS_INTERNAL_CORBAN=1 THEN IS_INTERNAL_FINANCED END) / NULLIF(SUM(CASE WHEN IS_INTERNAL_CORBAN=1 THEN IS_FINANCED END), 0)` | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Attach Rate - Mortgage` | ✅ | `SUM(IS_INTERNAL_FINANCED) / NULLIF(SUM(IS_FINANCED), 0)` (no IC filter) | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Attach Rate - Mortgage w/ Partners` | ✅ | `SUM(CASE WHEN IS_INTERNAL_CORBAN=0 THEN IS_INTERNAL_FINANCED END) / NULLIF(SUM(CASE WHEN IS_INTERNAL_CORBAN=0 THEN IS_FINANCED END), 0)` | [DS 18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| `Share Routed to IC` | ✅ | `COUNT(DISTINCT CASE WHEN franchise_name LIKE '%Quinto Andar%' AND contagem_ticket_IC > 0 THEN id_offer END) / NULLIF(COUNT(DISTINCT id_offer), 0)`. Filters: `payment_model = 'CCV_ASSISTANCE' AND ccv_model = 'Is a 5A model' AND payment_method LIKE '%FINANCED%' AND sub_division <> 'CONSORTIUM'`. Source: Dataset 19155 (`datalake_sale_closing_flows.closing_flow`). | [DS 18647](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18647) |

### Buyer Prospect Metrics

| Metric | Status | Notes |
|---------|--------|-------|
| `# Buyer Prospect` | ✅ | `COUNT(DISTINCT sk_buyer) WHERE event_name = 'VISIT_BOOKED' AND 1P`. ~90% vs Fibonacci. |
| `BP2CCV` | ⚠️ | Official source: `sandbox.summary_table` (SQL not available). DW: join `fact_sale_demand_event` (VISIT_BOOKED month M, 1P) + `fact_offers` (CCV in M or M+1) — M0+M1 cohort. `fact_buyer_prospects.sale_agreements_signed` = lifetime, not usable. |
| `BPOS2BPCCV` | ⚠️ | Same cohort logic. Buyers with VISIT_BOOKED in month M; numerator = CCV in M or M+1. |
| `BPOS2BPOA` | ⚠️ | Same. Numerator = OA in M or M+1. |
| `BPOA2BPCCV` | ⚠️ | Buyers with VISIT_BOOKED + OA in M; numerator = CCV in M or M+1. |
| `HT BP2CCV` | ❌ | HT = High Ticket. Defined in the `datalake_buyer_prospect` tables. Source not mapped in the central DW. |

### Reference Benchmarks

Use to validate query outputs and identify anomalies.

#### EoF

| Metric | Benchmark |
|---------|-----------|
| BP OS2CD | ~40% |
| OS2OA | ~60% |
| OA2CCV | ~70% |
| CCV2CD | ~95% |
| LT OS→OA | ~2 days |
| LT OA→CCV | ~6 days |
| LT CCV→CD | ~10 days |
| NPS CCV | ~75 |
| NPS Lost Proposal | ~22 |
| Unit cost CCV drafting | ~R$250/CCV (37 analysts, ~R$500k/month) |
| Unit cost Due Diligence | ~R$250/DD (49 analysts, ~R$650k/month) |
| % CCVs with contractual adjustments | ~25% |
| % cases with pending items | ~39% (~50% avoidable) |

#### EoP

| Track | NPS | Lead Time |
|-------|-----|-----------|
| Cash — CRN parceiro | 62.1 | 75.5d |
| Cash — no CRN parceiro | 2.8 | 121.9d |
| Cash — aggregate | 54.1 | 84.3d |
| Mortgage — Internal Corban | 29.6 | 100.2d |
| Mortgage — w/ Partners | 36.6 | 126.6d |
| Mortgage — aggregate | 36.6 | 125.7d |
| Total EoP NPS | ~45 | — |
| Post-contract unit cost | ~R$1,079/CCV | — |
| Attach rate CRN parceiro (Cash) | ~82% | — |
| Attach rate Internal Corban (Mortgage) | ~14% (target: 40% mid-2026, 100% end-2026) | — |

#### Reference Superset Dashboards

| Dashboard | URL |
|-----------|-----|
| **Fibonacci** (top-level FS KPIs) | [dashboard/2608](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2608/?native_filters_key=dDh6IIGlT-pzn26pNdObLfREBRYeXFAyq8La-U_w2qg17iJtziEiH75U_c7WAce3) |
| **Demand Conversion** | [dashboard/2915](https://superset.apps.data-prd.habitat.zone/superset/dashboard/2915/?native_filters_key=0a3HQaGb7F3w5ocmOaRjX2vCetgsveB6t3ubyOkCTKglp4Sh1ktOzUF3bETXwkQ-) |
| **Polygon** (NPS / EoP KPIs) | [dashboard/3087](https://superset.apps.data-prd.habitat.zone/superset/dashboard/3087/) |
| **EoF Conversion** (OA2SO, SO2CCVe, CCV2CD) | [dashboard/1384](https://superset.apps.data-prd.habitat.zone/superset/dashboard/1384/?native_filters_key=9NJo85VO9rON_m4l734v6MuTsFkoQabYATt6vlRV8mCQ9f4ZkRjkDyiiZrfudQKH) |
| **Dataset Lead Time EoP** | [datasource/16038](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=16038) |
| **Dataset DSAT/Resolution Rate** | [datasource/18277](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18277) |
| **Dataset NPS EoP** | [datasource/18337](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18337) |
| **Dataset Attach Rate** | [datasource/18841](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18841) |
| **Dataset Share IC** | [datasource/18647](https://superset.apps.data-prd.habitat.zone/explore/?datasource_type=table&datasource_id=18647) |

---

## Relationships with Other Entities

- **FR Transact (For Rent analog):** [`fr_transact.md`](fr_transact.md) documents the equivalent funnel for rentals. The EN/CCV/closing vocabulary is analogous, but tables, keys, and grains are entirely separate (`dw_sale.*` vs `dw_rent.*`) — do not port SQL patterns between the two without re-checking schema and grain. FR's "Sinal" (`datalake_rental_transact_clean.advance_payment`) is a different product from FS's Sinal/Earnest Payment (see [Glossary and Synonyms](#glossary-and-synonyms) and [Overview](#overview) → Steps common to Cash and Mortgage) — see `fr_transact.md`'s Dos and Don'ts before conflating the two.
- **Closing (cross-domain signed contracts):** [`closing.md`](closing.md) documents the generic "monthly volume of signed contracts" question covering both RENT and SALE — for SALE it points back to CCV (`fact_offers.ts_sale_agreement_signed`) and to the 1P filters in [Shared building blocks](#shared-building-blocks) of this document. Consult `closing.md` when the question does not specify RENT or SALE.
- **Broker attribution:** `fact_offers.sk_broker_demand` / `sk_broker_supply` identify the demand and supply brokers of the offer; details on program, performance, and broker commission live in [`broker_xp.md`](broker_xp.md), not in this document.
- **House and Listing:** `fact_offers.sk_house` and `dim_offer.sale_price` (listing snapshot) reference the house/listing entity documented in [`house_and_listing.md`](house_and_listing.md); remember from [Seller Discount — Correct Fields](#seller-discount--correct-fields) that `dw_sale.dim_listing.price` is a live snapshot, not the CCV price.
- **Bank Reconciliation (Sinal / cash-in):** For Sale's Sinal, brokerage, and ByPass bank reconciliation lives in [`bank_reconciliation.md`](bank_reconciliation.md) (`datalake_bank_conciliation.for_sale_cashin`) — consult it to reconcile Sinal financial values (see [Overview](#overview) → Steps common to Cash and Mortgage) with bank statements.
- **Atta (financing/Corban):** `dw_atta.fact_pre_analysis_proposal_flow` / `dim_proposal_atta` / `dim_franchise_atta` / `dim_closing_offer_partner` carry the Internal/Partner Corban financing detail referenced in [Overview](#overview) and [Tables](#tables). For the Atta credit-analysis workflow beyond what [Tables](#tables) documents, treat `dw_atta.*` as Atta's own domain, not FS Transact's.
- **Customer Satisfaction (NPS/CSAT):** `dw_customer_satisfaction.fact_nps_dispatches` / `dim_nps_answer` / `dim_nps_campaign` are shared across domains; FS Transact only owns the `metric_group` filters (`buyerccv`, `sellerccv`, `buyerendofprocess`, `sellerendofprocess`, `buyerlostproposal`) documented in [EoF Metrics](#eof-metrics) and [EoP Metrics](#eop-metrics).
- **Related Metric Entities:** for the official listing-cohort conversions (L2VB/L2VC/L2OS/L2CCV), see [Related Metric Entities](#related-metric-entities) at the top of this document — these take precedence over the coincident/offer-cohort ratios in [EoF Metrics](#eof-metrics) when the question asks for an official number.

### Relationships between CDC Tables

```
events_case_legal_ops ──── (case_legal_ops__c) ──── events_incident
                   │                                       │
                   └──── (contract__c) ─── contract        └──── (case__c) ─── events_case
                                                                        │
events_pendency ──── (caso__c) ─── events_case              └──── (id_*) ─── users
      │
      └──── (purchase_sale_contract__c) ──── purchase_sale_contract
      └──── (offer_id__c) ──────────────── dw_sale.dim_sale_agreement.sk_offer

events_received_document ──── (caso__c) ─── events_case
      │
      ├──── (opportunity__c) [pre-contract] ──── opportunity
      └──── (purchase_sale_contract__c) [post-contract] ──── purchase_sale_contract
```

---

## Dos and Don'ts — Never Make These Mistakes

**Do:** Always apply the 1P filters from [Shared building blocks](#shared-building-blocks) (`payment_model <> 'CLOSING_3P'` + the Casa Mineira tag exclusions) before reporting any EoF/EoP number, and always LEFT JOIN `dim_sale_agreement` from `fact_offers` — it only has rows for offers that reached the agreement stage.

**Don't:** Treat CCV and CD as the same metric, or report either one without stating whether it is gross or net of cancellations — see the full table below for every other common mistake.

| ❌ Mistake | ✅ Correct approach |
|---------|-------------------|
| Using CCV as "number of sales" or a revenue metric | CD ≠ CCV. Use `fact_closing_flows.sk_legal_analysis_ended_date` for CD (Finance) |
| Assuming `fact_closing_flows` is the only CD source | Part of CD volume is entered manually and may live in `datalake_gsheets_clean.closed_deals`. Check both when reconciling with Finance. |
| Querying EoF/EoP without 1P filters | Always filter `payment_model <> 'CLOSING_3P'` (on `dim_sale_agreement`) + legacy tags (`tags_from_salesflow` on `dim_offer`) |
| Filtering Casa Mineira tags via `dim_sale_agreement.tags_from_salesflow` | The column **does not exist** on `dim_sale_agreement` (Trino: `COLUMN_NOT_FOUND`). It is on `dw_sale.dim_offer.tags_from_salesflow` — join via `sk_offer`. Use `COALESCE(do.tags_from_salesflow, '')` so offers with no tag aren't dropped. |
| Using `ROW_NUMBER() OVER (...)` inside `ON` or `WHERE` (e.g. to get the Internal Corban's most recent proposal) | Trino/Spark do not allow window functions in `ON`/`WHERE`. Isolate it in a CTE (`ic_latest`) with `ROW_NUMBER()` in the `SELECT`, then filter `rn = 1` in the join. |
| Mixing 1P and 3P in the same funnel analysis | 3P follows a completely different flow. Always keep them separate. |
| INNER JOIN on `dim_sale_agreement` | Always LEFT JOIN — the table only has rows for offers that reached the agreement stage |
| Using `fact_visits.sk_offer` to enumerate offers | Only carries the first offer per booking. Use `fact_offers` directly. |
| Using `fact_buyer_prospects` to compute `# BP` | Captures only the first historical booking (~50% of the total). Correct source: `fact_sale_demand_event` WHERE `event_name = 'VISIT_BOOKED'`. |
| Using `dim_sale_agreement.is_3p_lead_gen` | That column does not exist on `dim_sale_agreement`. Filter via `fact_offers.is_3p_lead_gen`. |
| Reporting EoP LT as a single average | Always segment by `payment_method` and Corban/CRN type — distributions vary greatly across tracks. |
| Using `ts_offer_accepted` or `ts_sale_agreement_created` as a revenue proxy | Use `fact_closing_flows.sk_legal_analysis_ended_date` (CD) for revenue, or `ts_sale_agreement_signed` (CCV) for pipeline. |
| Reporting CCV volume without stating gross vs net | Default = gross (includes CCVs later cancelled). Always state it. |
| Including `sk_* = -1` in GROUP BY without filtering | All `sk_*` columns use `-1` for unassigned rows. Filter `sk_closing_specialist <> -1` etc. |
| Conflating SAC with CCV | SAC = draft created (pipeline). CCV = signed contract (commercial milestone). CD = post-DD and TC. |
| Using EoP status columns without validating the enum | `closing_status`, `*_dilligence_status` may have been extended. Validate current values before use. |
| Using `dim_listing.price` to compute the seller discount | `dim_listing.price` is the listing's current price (CDC from EBDB, ~30 min), **not updated** when the offer is accepted or the CCV is signed. For effective discount use `fact_offers.last_discount_proposed`; for raw prices use `dim_offer.sale_price` (snapshot at the moment of the offer) vs `dim_sale_agreement.sale_price_agreed` (CCV price). See [Seller Discount — Correct Fields](#seller-discount--correct-fields). |
| Confusing `max_discount_proposed` (fact_sale_flows) with the effective discount | `max_discount_proposed` = the largest discount gap across any offer in the flow, including rejected offers. For closed deals, use `fact_offers.last_discount_proposed` filtered by `ts_offer_accepted IS NOT NULL`. |
| Using `fact_buyer_prospects.sale_agreements_signed` for cohorted BP2CCV | Gives lifetime conversion, not a monthly cohort. Fibonacci uses an M0+M1 window. |

### Salesforce CDC Tables

**Do:**
- Use `id_replay` to order events for the same `id_record` — it is the correct monotonic cursor for CDC.
- To reconstruct current state: apply `LAST_VALUE(...) IGNORE NULLS OVER (PARTITION BY id_record ORDER BY id_replay)` or `ROW_NUMBER()` + filter `rn=1` per field.
- Use `TIMESTAMP_MILLIS(commit_ts)` to convert to a timestamp.
- For `events_incident`, use the most recent record directly (`MAX(id_replay)`) — it is not sparse, all fields are always populated.
- Remember that `opportunity__c` and `purchase_sale_contract__c` on `events_received_document` are **mutually exclusive** depending on the business stage.

**Don't:**
- Don't treat NULL in business columns as "missing data" — in sparse CDC, NULL means the field did not change in that event.
- Don't use `commit_ts` as seconds — it is **milliseconds**. Divide by 1000 or use `TIMESTAMP_MILLIS()`.
- Don't assume `events_incident` is sparse — unlike the other 3 tables, it sends full state on every event.
- Don't join `events_case_legal_ops` to `dw_sale.fact_offers` directly via `contract__c` — the field is a Salesforce ID (`800b...`), not `sk_offer`. Use `purchase_sale_contract__c` on `events_pendency`/`events_received_document` as the bridge via the clean `purchase_sale_contract` table.
- Don't use the CDC record's `created_date` for time-based volume analyses — use `committed_at` or `TIMESTAMP_MILLIS(commit_ts)` to date the event.

---

## Golden Queries

### Shared building blocks

Canonical joins and mandatory filters reused across the queries below.

```sql
-- Canonical 1P EoF/EoP base: offers submitted, excluding 3P and Casa Mineira.
-- tags_from_salesflow lives on dim_offer (NOT on dim_sale_agreement).
SELECT
    COUNT(*) AS offers_submitted
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
```

Reuse the same 1P joins/filters in the queries below. Additional join patterns:

- **Closed Deals (product-side CD):** `dw_sale.fact_closing_flows fcf` joined to `fact_offers` on `sk_offer`. Finance's Bypass cut is on `datalake_gsheets_clean.closed_deals.contract_group`, not on `fact_closing_flows`.
- **Internal Corban:** isolate `ROW_NUMBER()` in a CTE (`ic_latest`); filter `ic.franchise_name LIKE '%Quinto Andar%'`. Window functions cannot go in `ON`/`WHERE` in Trino.
- **NPS EoP:** `fact_nps_dispatches` + `dim_nps_answer` + `dim_nps_campaign`; `metric_group` is on `dim_nps_campaign`; join `dim_sale_agreement` via `disp.sk_offer`.
- **# Buyer Prospect (1P):** `fact_sale_demand_event` + `dim_sale_event_type` + `dim_date`; `event_name = 'VISIT_BOOKED'` and `is_3p_demand = false` / `is_3p_supply = false`.

**Mandatory Filters (1P)**

**Always** apply when querying EoF or EoP data to restrict to valid 1P transactions:

```sql
-- payment_model + is_ccv_canceled live on dw_sale.dim_sale_agreement (dsa)
-- tags_from_salesflow lives on dw_sale.dim_offer (do) — NOT on dim_sale_agreement
WHERE dsa.payment_model <> 'CLOSING_3P'                          -- excludes 3P/Marketplace transactions
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'    -- excludes legacy Casa Mineira flow
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
```

**Why:**
- `CLOSING_3P` = Marketplace transactions. Completely different funnel, actors, and data. Never include in 1P analyses.
- Legacy tags = Casa Mineira closing types that are no longer active. They distort conversion, LT, and cost figures.
- `tags_from_salesflow` requires a `JOIN dw_sale.dim_offer` — the column does **not** exist on `dim_sale_agreement` (Trino returns `COLUMN_NOT_FOUND`). The `COALESCE` prevents offers with no tag from being dropped by the `NOT LIKE`.

**Full base for the EoF funnel (preserving offers that did not reach agreement stage):**
```sql
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (    dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
```

**Division / sub_division logic** (used in datasets 16038, 19155, 18841):
```sql
-- division
CASE
  WHEN payment_method IN ('CASH','CASH_USING_FGTS')                   THEN 'CASH'
  WHEN payment_method LIKE '%FINANCED%' AND credit_model = 'EXTERNAL' THEN 'FINANCED W/O PARTNER'
  ELSE 'FINANCED'
END AS division

-- sub_division (requires join with dw_atta.fact_pre_analysis_proposal_flow)
CASE
  WHEN franchise_name LIKE '%Quinto Andar%'                            THEN 'INTERNAL CORBAN'
  WHEN payment_method = 'CASH_USING_FGTS'                             THEN 'CASH W/ FGTS'
  WHEN payment_method = 'CASH'                                         THEN 'CASH W/O FGTS'
  WHEN payment_method LIKE '%FINANCED%' AND credit_model = 'EXTERNAL' THEN 'EXTERNAL FINANCING'
  ELSE 'INTERNAL FINANCING'
END AS sub_division
```

### Where to start — beginner queries

Before the more advanced analyses below, these four answer the most common questions for someone starting to explore FS Transact. All use only 1–2 tables and no CTEs.

**1. How many CCVs were signed this month?**
The most basic pipeline question (see [Overview](#overview) for the difference between CCV and CD).
```sql
SELECT
    DATE_TRUNC('month', fo.ts_sale_agreement_signed) AS month,
    COUNT(*)                                          AS ccv_count
FROM dw_sale.fact_offers fo
WHERE fo.ts_sale_agreement_signed IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC
```
> Without the 1P filters ([Shared building blocks](#shared-building-blocks)) this number includes 3P and the legacy Casa Mineira flow — for official reporting, apply the same filters as in the examples below.

**2. How many Closed Deals (CD) — Finance's official sales metric — did we have this month?**
CD ≠ CCV (see [Overview](#overview)). This is the simplest count, without the full 1P filters.
```sql
SELECT
    dd.month_start AS month,
    COUNT(*)       AS closed_deals
FROM dw_sale.fact_closing_flows fcf
JOIN dw_public.dim_date dd ON fcf.sk_legal_analysis_ended_date = dd.sk_date
WHERE fcf.sk_legal_analysis_ended_date > 0
GROUP BY 1
ORDER BY 1 DESC
```

**3. Who are the specialists currently assigned to an offer?**
`offer_specialists` is wide (one name/email column per specialist type) — use the assignment source of truth (see [Main Tables](#main-tables)) instead of trying to reconstruct this from `fact_offers`.
```sql
SELECT
    id_offer,
    consultant_name,          -- Deal Maker
    pre_specialist_name,      -- PRE (negotiation)
    post_specialist_name,     -- POST (post-CCV)
    credit_specialist_name,   -- CREDIT (credit analysis)
    notes_registry_specialist_name,          -- CRN
    real_estate_register_specialist_name     -- CRI
FROM datalake_sale_offer_flows.offer_specialists
WHERE id_offer = :id_offer   -- replace with the id_offer (= id_firestore) of interest
```

**4. What was the discovery (pre-offer) journey of a specific buyer?**
Visits, bookings, and offers per buyer/house pair, before any CCV (see [Main Tables](#main-tables)).
```sql
SELECT
    sk_sale_flow,
    sk_house,
    first_event,             -- booking, offer, or talk_to_agent
    bookings,
    visits_completed,
    offers_submitted,
    max_discount_proposed
FROM dw_sale.fact_sale_flows
WHERE sk_buyer = :sk_buyer   -- replace with the sk_buyer (= id_external from EBDB) of interest
ORDER BY sk_house
```

### Monthly EoF conversion funnel
```sql
SELECT
    DATE_TRUNC('month', fo.ts_offer_submitted)                                      AS month_os,
    COUNT(*)                                                                          AS offers_submitted,
    COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL)                          AS offers_accepted,
    COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL)                   AS ccv_signed,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*), 0) * 100, 1)                                             AS os2oa_pct,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*) FILTER (WHERE fo.ts_offer_accepted IS NOT NULL), 0) * 100, 1) AS oa2ccv_pct
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 1
```

### Closed Deals by month (financial metric)
```sql
-- Product-side CD (sk_legal_analysis_ended_date). Sentinel -1 is missing; IS NOT NULL does not drop it.
-- 1P filters: payment_model + Casa Mineira tags (see Shared building blocks).
-- Bypass is NOT on fact_closing_flows — Finance excludes it via
-- datalake_gsheets_clean.closed_deals.contract_group <> 'Bypass'.
SELECT
    dd.month_start AS month_cd,
    COUNT(*)       AS closed_deals
FROM dw_sale.fact_closing_flows fcf
JOIN dw_public.dim_date              dd  ON fcf.sk_legal_analysis_ended_date = dd.sk_date
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fcf.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer          do  ON fcf.sk_offer = do.sk_offer
WHERE fcf.sk_legal_analysis_ended_date > 0
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1
ORDER BY 1
```

### EoP Lead Time by track
```sql
-- Internal Corban needs the most recent record per offer: isolate it in a CTE
-- (ROW_NUMBER() cannot appear in the ON/WHERE clause in Trino/Spark).
WITH ic_latest AS (
    SELECT
        fpp.sk_offer,
        dfr.franchise_name,
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_offer
                           ORDER BY fpp.ts_last_updated DESC) AS rn
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
)
SELECT
    CASE WHEN dsa.payment_method IN ('CASH','CASH_USING_FGTS')        THEN 'CASH'
         WHEN ic.franchise_name LIKE '%Quinto Andar%'                  THEN 'INTERNAL CORBAN'
         ELSE 'FINANCED W/ PARTNER'
    END                                                                  AS track,
    AVG(fcf.days_sale_agreement_signed_to_house_registry_ended)          AS avg_lt_days,
    COUNT(*)                                                              AS ccv_count
FROM dw_sale.fact_closing_flows fcf
JOIN dw_sale.dim_sale_agreement dsa ON fcf.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer         do  ON fcf.sk_offer = do.sk_offer
LEFT JOIN ic_latest                 ic  ON fcf.sk_offer = ic.sk_offer AND ic.rn = 1
WHERE fcf.sk_house_registry_ended_date IS NOT NULL
  AND dsa.is_ccv_canceled = false
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1 ORDER BY 2
```

### # Buyer Prospect by month (NBP vs RBP)
```sql
SELECT
    DATE_FORMAT(dd.month_start, '%Y-%m')                           AS month,
    dbpt.buyer_prospect_type,
    COUNT(DISTINCT fde.sk_buyer)                                    AS buyer_prospects
FROM dw_sale.fact_sale_demand_event fde
JOIN dw_sale.dim_sale_event_type    det  ON fde.sk_event_type          = det.sk_event_type
JOIN dw_public.dim_date             dd   ON fde.sk_event_date          = dd.sk_date
JOIN dw_sale.dim_buyer_prospect_type dbpt ON fde.sk_buyer_prospect_type = dbpt.sk_buyer_prospect_type
WHERE det.event_name   = 'VISIT_BOOKED'
  AND fde.is_3p_demand = false
  AND fde.is_3p_supply = false
GROUP BY 1, 2 ORDER BY 1, 2
```

### NPS EoP by payment track
```sql
-- Dedup the Internal Corban proposal per offer via a CTE (avoids fan-out on NPS).
-- is_answered lives on fact_nps_dispatches; metric_group lives on dim_nps_campaign.
-- fact_offers is not needed — dim_sale_agreement is joined directly via disp.sk_offer.
WITH ic_latest AS (
    SELECT
        fpp.sk_offer,
        dfr.franchise_name,
        ROW_NUMBER() OVER (PARTITION BY fpp.sk_offer
                           ORDER BY fpp.ts_last_updated DESC) AS rn
    FROM dw_atta.fact_pre_analysis_proposal_flow fpp
    LEFT JOIN dw_atta.dim_franchise_atta dfr ON fpp.sk_franchise = dfr.sk_franchise
)
SELECT
    DATE_TRUNC('month', ans.ts_answered)                                               AS month,
    CASE WHEN dsa.payment_method IN ('CASH','CASH_USING_FGTS') THEN 'Cash'
         WHEN ic.franchise_name LIKE '%Quinto Andar%'           THEN 'Internal Corban'
         ELSE 'Financed w/ Partner'
    END                                                                                  AS track,
    ROUND((COUNT(DISTINCT CASE WHEN ans.score_category = 'promoter'  THEN ans.sk_nps_answer END)
         - COUNT(DISTINCT CASE WHEN ans.score_category = 'detractor' THEN ans.sk_nps_answer END))
        * 100.0 / NULLIF(COUNT(DISTINCT ans.sk_nps_answer), 0), 1)                    AS nps
FROM dw_customer_satisfaction.dim_nps_answer       ans
JOIN dw_customer_satisfaction.fact_nps_dispatches  disp ON disp.sk_nps_answer   = ans.sk_nps_answer
JOIN dw_customer_satisfaction.dim_nps_campaign     dnc  ON disp.sk_nps_campaign = dnc.sk_nps_campaign
LEFT JOIN dw_sale.dim_sale_agreement                dsa  ON disp.sk_offer        = dsa.sk_offer
LEFT JOIN ic_latest                                 ic   ON disp.sk_offer        = ic.sk_offer AND ic.rn = 1
WHERE disp.is_answered    = true
  AND dnc.metric_group   IN ('buyerendofprocess','sellerendofprocess')
GROUP BY 1, 2 ORDER BY 1, 2
```

### LegoContract assessment performance by month (ACTION_NEEDED rate and confidence)
```sql
-- Monthly evolution of assessment quality — the main source of LegoContract product metrics.
-- ⚠️ An id_sales_flow can have multiple analyses per day; this query aggregates everything without deduping.
--    For "latest analysis per contract" metrics, see the query below.
SELECT
    DATE_TRUNC('month', analysis_date)                                                 AS month,
    validation_id,
    assessment_name,
    COUNT(*)                                                                            AS total_executions,
    COUNT(*) FILTER (WHERE assessment_consolidated_status = 'ACTION_NEEDED')           AS action_needed,
    COUNT(*) FILTER (WHERE assessment_consolidated_status = 'OK')                      AS ok,
    COUNT(*) FILTER (WHERE assessment_consolidated_status = 'UNAVAILABLE')             AS unavailable,
    ROUND(
        COUNT(*) FILTER (WHERE assessment_consolidated_status = 'ACTION_NEEDED') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE assessment_consolidated_status <> 'UNAVAILABLE'), 0),
    1)                                                                                  AS action_needed_pct,
    ROUND(
        COUNT(*) FILTER (WHERE assessment_confidence = 'HIGH') * 100.0
        / NULLIF(COUNT(*), 0),
    1)                                                                                  AS high_confidence_pct
FROM datalake_legalops_clean.lego_analysis_results
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 5 DESC
```

### Latest analysis per contract — most recent assessments by id_sales_flow
```sql
-- Deduped to the most recent analysis per sales_flow. Use for "current state" contract analyses.
WITH latest AS (
    SELECT
        id_sales_flow,
        MAX(analysis_date) AS last_analysis_date
    FROM datalake_legalops_clean.lego_analysis_results
    GROUP BY 1
)
SELECT
    r.id_sales_flow,
    r.analysis_date,
    r.validation_id,
    r.assessment_name,
    r.assessment_status,
    r.assessment_consolidated_status,
    r.assessment_confidence
FROM datalake_legalops_clean.lego_analysis_results r
JOIN latest l
    ON r.id_sales_flow = l.id_sales_flow
    AND r.analysis_date = l.last_analysis_date
ORDER BY r.id_sales_flow, r.assessment_name
```

### Ranking of the hardest-to-pass validations (ACTION_NEEDED rate)
```sql
-- Identifies which assessments are failing the most — useful for prioritizing investigation and improvement.
SELECT
    validation_id,
    assessment_name,
    COUNT(*)                                                                     AS total,
    COUNT(*) FILTER (WHERE assessment_consolidated_status = 'ACTION_NEEDED')    AS action_needed,
    ROUND(
        COUNT(*) FILTER (WHERE assessment_consolidated_status = 'ACTION_NEEDED') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE assessment_consolidated_status <> 'UNAVAILABLE'), 0),
    1)                                                                           AS action_needed_pct,
    ROUND(
        COUNT(*) FILTER (WHERE assessment_confidence = 'LOW') * 100.0
        / NULLIF(COUNT(*), 0),
    1)                                                                           AS low_confidence_pct
FROM datalake_legalops_clean.lego_analysis_results
WHERE analysis_date >= DATE_ADD('month', -3, CURRENT_DATE)  -- last 3 months
GROUP BY 1, 2
HAVING COUNT(*) >= 30  -- exclude assessments with too little data
ORDER BY action_needed_pct DESC
```

### Effective seller discount by month (accepted deals)
```sql
-- ⚠️ Use last_discount_proposed (computed against the sale_price at the moment of the offer),
-- do NOT cross dim_listing.price with sale_price_agreed — dim_listing.price is the listing's
-- current price and is not updated when the offer is accepted or the CCV is signed.
-- See Seller Discount — Correct Fields.
SELECT
    DATE_TRUNC('month', fo.ts_offer_accepted)                                  AS month,
    COUNT(*)                                                                    AS deals_aceitos,
    ROUND(AVG(fo.last_discount_proposed) * 100, 2)                             AS avg_discount_pct,
    ROUND(approx_percentile(fo.last_discount_proposed, 0.5) * 100, 2)          AS median_discount_pct,
    ROUND(AVG(do.sale_price) / 1.0, 0)                                         AS avg_listing_price,
    ROUND(AVG(fo.sale_price_agreed) / 1.0, 0)                                  AS avg_agreed_price
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_accepted IS NOT NULL
  AND fo.last_discount_proposed IS NOT NULL
  AND fo.last_discount_proposed >= 0
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 1
```

### Effective discount distribution (histogram in 2pp buckets)
```sql
SELECT
    FLOOR(fo.last_discount_proposed * 100 / 2) * 2  AS discount_bucket_pct,
    COUNT(*)                                         AS deals
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.ts_offer_accepted IS NOT NULL
  AND fo.last_discount_proposed BETWEEN 0 AND 0.30
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 1
```

### CCV cancellation reasons
```sql
SELECT
    dsa.sale_agreement_cancellation_reason,
    COUNT(*)                               AS ccvs_cancelados
FROM dw_sale.fact_offers fo
JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
LEFT JOIN dw_sale.dim_offer         do  ON fo.sk_offer = do.sk_offer
WHERE dsa.is_ccv_canceled = true
  AND dsa.payment_model <> 'CLOSING_3P'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
  AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'
GROUP BY 1 ORDER BY 2 DESC
```

### Performance by demand broker
```sql
SELECT
    fo.sk_broker_demand,
    COUNT(*)                                                                   AS offers_submitted,
    COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL)            AS ccv_signed,
    ROUND(CAST(COUNT(*) FILTER (WHERE fo.ts_sale_agreement_signed IS NOT NULL) AS DOUBLE)
          / NULLIF(COUNT(*), 0) * 100, 1)                                      AS os2ccv_pct
FROM dw_sale.fact_offers fo
LEFT JOIN dw_sale.dim_offer          do  ON fo.sk_offer = do.sk_offer
LEFT JOIN dw_sale.dim_sale_agreement dsa ON fo.sk_offer = dsa.sk_offer
WHERE fo.sk_broker_demand <> -1
  AND fo.ts_offer_submitted IS NOT NULL
  AND (dsa.sk_offer IS NULL
       OR (dsa.payment_model <> 'CLOSING_3P'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo-cm%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#casa-mineira%'
           AND COALESCE(do.tags_from_salesflow, '') NOT LIKE '%#fluxo_cm%'))
GROUP BY 1 ORDER BY 2 DESC
```
