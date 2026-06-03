# SEO

## Overview

SEO (Search Engine Optimization) tracks QuintoAndar's organic search visibility and top-of-funnel demand performance. The domain spans two analytical surfaces: (1) keyword-level search signals from Google Search Console and SEMrush (impressions, clicks, CTR, position, search volume), and (2) funnel conversion from organic traffic to Prospects (users who schedule a visit or send an offer). Non-branded search is the primary strategic focus — it captures users who haven't committed to a specific platform yet, providing long-term sustainability without relying purely on brand awareness.

## Glossary and Synonyms

- **SEO** (Search Engine Optimization) → strategy and data domain for organic traffic performance; do not confuse with **SEM** (Search Engine Marketing = sponsored/paid links)
- **SERP** → Search Engine Results Page; the page users see after performing a search
- **GSC** (Google Search Console) → tool tracking organic click/impression/position data; maps to `datalake_google_search_console.keyword_clusters`
- **SEMrush** → competitive intelligence tool for keyword rankings and search volume; maps to `datalake_semrush.keyword_clusters`
- **Branded** → search queries containing "quintoandar" or variants (5andar, quinto andar); `is_branded = 1` in GSC table, `cluster_macro = 'Player'` in SEMrush
- **Non-branded** → generic queries not including the brand name; `is_branded = 0`; primary strategic focus
- **Short/Head tail** → broad, high-volume queries (e.g., "alugar apartamento"); current strategic priority
- **Long tail** → specific, lower-volume queries (e.g., "alugar apartamento três quartos mobiliado em Pinheiros")
- **Goldenset** → curated list of highest-priority strategic keywords; `is_goldenset = true` in keyword tables
- **Cluster macro** → top-level keyword intent label: Non-Related, Player, Informational, Rent/Sale Generic/Local, House Type Generic/Local, Local, Unallocated
- **Cluster micro** → finer-grained segmentation combining player, informational, transactional, location, and house flags
- **High intent** → queries with strong transactional intent; `cluster_macro IN ('Rent Local', 'Rent Generic', 'Sale Local', 'Sale Generic')`
- **Mid/Low intent** → research-phase or informational queries; `cluster_macro NOT IN ('Rent Local', 'Rent Generic', 'Sale Local', 'Sale Generic')`
- **Transactional journey** → users in later conversion stages, using keywords like "business + housetype + location"
- **Informational journey** → users in early research phase seeking guides/content (e.g., "Como é morar em Copacabana")
- **ToF** (Top of Funnel) → user visiting Search Page, Listing Page, or Schedule Page at QuintoAndar
- **Prospect** → user who schedules a visit or sends an offer; higher-intent than ToF
- **TP** (Tenant Prospect) → prospect in the rental business context (`business_context = 'Rent'`)
- **BP** (Buyer Prospect) → prospect in the sale business context (`business_context = 'Sale'`)
- **Actual** → observed (real) Prospect count in the period; from `growth_demand_performance_*` tables
- **Target** → forecast Prospect count from Ops teams; from `rental_prospect_target` / `sale_prospect_target`
- **Business Context / BC** → type of contract: `Rent` or `Sale` (stored lowercase in DW tables, requires normalization)
- **House type** → type of property: apartment, house, studio, condominium house
- **Regions** → pages about serviced areas: city, neighborhood, condominium, street
- **UGC** → User Generated Content
- **POI** → Points of Interest — nearby places shown on listings or nearby-search pages (e.g., apartments near Liberdade subway)
- **Page structure** → URL-based page classification (e.g., `/alugar` → "Transacional", `/condominio` → "Condominium")
- **Page cluster** → content-based grouping (e.g., "Rental Search", "Purchase Search", "Condominio")
- **Player** → competitor tracked in SEMrush: zapimoveis, quintoandar, olximoveis, chavesnamao, imovelweb, loft, wimoveis, vivareal
- **QAC** (QuintoAndar Classifieds) → QuintoAndar’s initiative to display the full market inventory from Navent (Imovelweb, Wimoveis, ..) listings as a freemium business model.

## Tables

| You need... | Use this table |
|-------------|----------------|
| Monthly Prospect and ToF performance metrics by region, UTM, channel, BC | `delta.metric_growth.growth_demand_performance_monthly` |
| Weekly Prospect and ToF performance metrics by region, UTM, channel, BC | `delta.metric_growth.growth_demand_performance_weekly` |
| Daily Prospect and ToF performance metrics by region, UTM, channel, BC | `delta.metric_growth.growth_demand_performance_daily` |
| Daily new and recovered target for Tenant Prospects by channel, region | `delta.datalake_gsheets_clean.rental_prospect_target` |
| Daily new and recovered target for Buyer Prospects by channel, region | `delta.datalake_gsheets_clean.sale_prospect_target` |
| Daily keyword-level impressions, clicks, CTR, position with clustering (GSC) | `delta.datalake_google_search_console.keyword_clusters` |
| Monthly keyword-level rankings, search volume, and competitor comparison for Brazil (SEMrush) | `delta.datalake_semrush.keyword_clusters` |
| Monthly keyword-level rankings, traffic share, and competitive positioning for LATAM classified portals — Argentina, Ecuador, Mexico, Panama, Peru (SEMrush, excluding Brazil) | `datalake_semrush_classified.keywords_from_players` |
| Daily QAC funnel metrics — ToF, QAC exposure, listing views, lead intent, and lead confirmed — by date, business context, and city (distinct Amplitude users) | `growth.growth_demand_qac_funnel` |

**Critical rules:**
- For average position, always compute `SUM(posimp) / SUM(impressions)` — `AVG(position)` ignores impression weight and produces misleading results.
- `datalake_google_search_console.keyword_clusters.is_branded` is an integer (1/0), not a string label; map to `medium` values (`SEO branded`, `SEO non-branded`) when joining with demand performance tables.
- Join `rental_prospect_target` and `sale_prospect_target` to `dw_public.dim_date` on `date` to derive `month_start` for alignment with monthly observed metrics. Also set `country_code = 'BR'` on target tables when joining to observed metrics.
- Normalize `business_context` to initial-capital (`Rent`, `Sale`) when combining rows across tables — raw values are lowercase.
- `datalake_semrush.keyword_clusters` date column is `dt_display` (always fixed to the 15th of each month — an arbitrary ingestion artifact). When a row with `dt_display = DATE '2026-05-15'` exists, it means the **entire month of May 2026** has already been captured, not just data up to the 15th. Always treat `dt_display` as a month identifier: use `DATE_TRUNC('month', dt_display)` to normalize it to the 1st of the month, or filter by year/month only — never interpret the 15th as a mid-month cutoff. `datalake_google_search_console.keyword_clusters` uses `dt_created`.
- `datalake_semrush_classified.keywords_from_players` uses the same `dt_display` monthly artifact (always fixed to the 15th — treat as month identifier; presence of the 15th means the entire month has been captured). Always filter by `country` when querying a specific market: `mex` (Mexico), `arg` (Argentina), `per` (Peru), `ecu` (Ecuador), `pan` (Panama). Use the `player` column to segment by portal; 26 portals are tracked across the 5 countries.
- `growth.growth_demand_qac_funnel` brings a QAC metrics overview: one row per `dt_reference` × `metric_name` × `business_context` × `city_group`. Always filter or pivot by `metric_name` to isolate the funnel step of interest. `metric_value` = distinct Amplitude users (`id_amplitude`). Join with other SEO tables only on `dt_reference` + `city_group` — there is no surrogate key FK. 

## Key Metrics

- **Prospects** — `SUM(new_prospects + recovered_prospects)` across Rent + Sale; from `growth_demand_performance_*` tables
- **New Prospects** — `new_prospects`; first-time prospect identification in the period
- **Recovered Prospects** — `recovered_prospects`; users who re-engaged after inactivity
- **Target** — `ntp + rtp` (rental) or `nbp + rbp` (sale); from `rental_prospect_target` / `sale_prospect_target`
- **ToF Users** — `tof_users`; unique users reaching Search/Listing/Schedule pages
- **ToF Events** — `tof_events`; total top-of-funnel events (use `tof_users` for user counts)
- **ToF → Prospect rate** — `SUM(new_prospects + recovered_prospects) / CAST(SUM(tof_users) AS DOUBLE)`
- **Impressions** — `SUM(impressions)`; times a page appeared in SERP
- **Clicks** — `SUM(clicks)`; times users clicked a search result
- **CTR** — `SUM(clicks) / CAST(NULLIF(SUM(impressions), 0) AS DOUBLE) * 100`; click-through rate
- **Average Position** — `SUM(posimp) / SUM(impressions)`; impression-weighted SERP position (lower = better)
- **Search Volume** — `search_volume` in SEMrush table; average monthly query volume per keyword

## Relationships with Other Entities

### Date dimension (N:1)

- Join `rental_prospect_target.date` or `sale_prospect_target.date` → `dw_public.dim_date.date` to get `month_start`, enabling alignment of daily targets with monthly observed Prospect metrics.

### Geographic alignment (implicit, no FK)

- `city_abreviation` in both keyword tables is a semantic proxy for `city_group` in `growth_demand_performance_*` tables. They share the same city abbreviation values but are not joined via a surrogate key — filter by matching string values.

## Dos and Don'ts

**Do:**

- Use `tof_users` (not `tof_events`) for Top-of-Funnel user counts.
- For channel breakdown (branded/non-branded), use `medium`; values of interest: `SEO branded`, `SEO non-branded`, `SEM branded`, `SEM non-branded`. For all-channel comparisons, aggregate remaining values using `behavior_type` into categories: `Other non-organic`, `Other organic`, `Other`.
- Default to `SUM(new_prospects + recovered_prospects)` across both business contexts (Rent + Sale) for Prospect counts; only split by BC if the user explicitly asks.
- Normalize `business_context` to initial-capital (`Rent`, `Sale`) when combining rows from different tables.
- Set `country_code = 'BR'` on target tables when joining to observed metric tables.
- Join daily target tables to `dw_public.dim_date` on `date` to get `month_start`.
- Compute average position as `SUM(posimp) / SUM(impressions)`.
- Treat `is_branded` in `datalake_google_search_console.keyword_clusters` as `1` (branded) / `0` (non-branded) when aligning with `medium` breakdowns in other tables.

**Don't:**

- Don't use `AVG(position)` for average position — always use `SUM(posimp) / SUM(impressions)`.
- Don't ask the user to specify business context if they haven't mentioned it — default to consolidated Rent + Sale view.
- Don't confuse SEO (organic) with SEM (paid/sponsored) — they are tracked separately via `medium` values in `growth_demand_performance_*`.

## Golden Queries

### Query 1 — Monthly Prospects and ToF by business context

Aggregates Prospects, ToF users, and conversion rate per business context for a given month.

```sql
SELECT
  dt_month_start,
  CASE 
    WHEN LOWER(business_context) = 'rent' THEN 'Rent'
    WHEN LOWER(business_context) = 'sale' THEN 'Sale'
    ELSE 'Not Mapped'
  END AS business_context,
  SUM(new_prospects + recovered_prospects) AS prospects,
  SUM(tof_users) AS tof_users,
  SUM(new_prospects + recovered_prospects) / CAST(SUM(tof_users) AS DOUBLE) AS tof_2_prospect
FROM 
  metric_growth.growth_demand_performance_monthly
WHERE 
  dt_month_start = DATE '2025-06-01'
GROUP BY 1, 2
ORDER BY 1, 2;
```

Use `growth_demand_performance_weekly` (date column: `dt_week_start`) or `growth_demand_performance_daily` (date column: `dt_event`) for other granularities — same column structure.

### Query 2 — Actual vs target Prospects by month

Joins observed Prospects with rent+sale targets, grouped by month.

```sql
WITH actual AS (
  SELECT 
    dt_month_start AS month_start,
    SUM(new_prospects + recovered_prospects) AS actual_prospects
  FROM 
    metric_growth.growth_demand_performance_monthly
  GROUP BY 1
),
tgt AS (
  SELECT 
    dd.month_start, 
    (t.ntp + t.rtp) AS target_prospect
  FROM 
    datalake_gsheets_clean.rental_prospect_target AS t
  LEFT JOIN 
    dw_public.dim_date AS dd ON dd.date = t.date
  UNION ALL 
  SELECT 
    dd.month_start, 
    (t.nbp + t.rbp) AS target_prospect
  FROM 
    datalake_gsheets_clean.sale_prospect_target AS t
  LEFT JOIN 
    dw_public.dim_date AS dd ON dd.date = t.date
),
tgt_agg AS (
  SELECT 
    month_start,
    SUM(target_prospect) AS target_prospect
  FROM tgt
  GROUP BY 1
)
SELECT
  a.month_start,
  a.actual_prospects,
  t.target_prospect
FROM actual AS a
LEFT JOIN tgt_agg AS t ON a.month_start = t.month_start;
```

### Query 3 — Monthly branded vs non-branded GSC performance

Impressions, clicks, CTR, and average position from Google Search Console split by branded flag.

```sql
SELECT
  DATE_TRUNC('MONTH', dt_created) AS month_start,
  is_branded,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(posimp) / CAST(NULLIF(SUM(impressions), 0) AS DOUBLE) AS avg_position,
  SUM(clicks) / CAST(NULLIF(SUM(impressions), 0) AS DOUBLE) * 100 AS ctr
FROM
  datalake_google_search_console.keyword_clusters
WHERE
  dt_created >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;
```

### Query 4 — Monthly average position by competitor (SEMrush)

Impression-weighted average organic position for tracked players on non-branded keywords.

```sql
WITH tbl AS (
  SELECT 
    DATE_TRUNC('month', dt_display) AS dt_display, 
    player_name,
    traffic,
    (traffic * position) AS postraff
  FROM 
    datalake_semrush.keyword_clusters
  WHERE
    cluster_macro NOT IN ('Player')
    AND player_name IN ('zapimoveis', 'quintoandar', 'olximoveis', 'chavesnamao', 'imovelweb', 'loft', 'wimoveis', 'vivareal')
) 
SELECT 
  dt_display, 
  player_name, 
  SUM(postraff) / SUM(traffic) AS avg_position
FROM tbl
WHERE dt_display >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY dt_display DESC, avg_position DESC;
```
### 5. Share of first position clicks (1st, 2nd ou 3rd) from goldenset keywords.

```sql
WITH tbl_clicks AS ( 
  SELECT 
    DATE_TRUNC('MONTH', dt_created) AS month_start,
    SUM(CASE WHEN ROUND(position, 0) BETWEEN 1 AND 3 THEN clicks ELSE 0 END) AS top_clicks,
    SUM(clicks) AS all_clicks
  FROM 
    datalake_google_search_console.keyword_clusters
  WHERE 
    dt_created >= DATE '2026-01-01'
    AND is_goldenset = True
    AND structure = 'Transacional'
  GROUP BY 
    1
)
SELECT 
  month_start,
  top_clicks / CAST(all_clicks AS DOUBLE) * 100 AS share_top
FROM 
  tbl_clicks
ORDER BY 
  1
```

## Semantic Context

### Why SEO matters for QuintoAndar

Organic search delivers cost-effective, sustainable traffic with higher long-term ROI than paid channels — it is free and compounds over time. A strong SEO presence builds trust and credibility in the real estate market, making users more likely to choose QuintoAndar over competitors when they find it ranking organically. SEO optimization also directly improves user experience (site speed, mobile-friendliness, navigation), reinforcing conversion and satisfaction across all channels.

### Branded vs Non-Branded

Branded searches include "quintoandar" or variants (5andar, quinto andar) — users have already decided on a platform. Non-branded searches are generic (e.g., "alugar apartamento") — users are still open to options and have not committed to a specific company. QuintoAndar's strategic focus is non-branded: it captures users before brand commitment and ensures long-term sustainability with lower dependency on brand awareness alone.

### Short/Head Tail vs Long Tail

Short-tail queries are broad and high-volume (e.g., "alugar apartamento") — users are still undecided. Long-tail queries are more specific with lower volume but higher conversion intent (e.g., "alugar apartamento de três quartos mobiliados em Pinheiros"). QuintoAndar's current priority is short-tail: higher search volume and more available supply to match demand. This strategic choice depends on business maturity and market strategy and can be revisited over time.

### Informational vs Transactional Journeys

Informational queries target early-stage users seeking knowledge or guides (e.g., "Como é morar em Copacabana"). SEO for this intent captures users before they consider transactions, builds authority, and guides them through the renting/buying process — an underserved content area with growth potential. Transactional queries come from users with strong conversion intent using specific keywords (e.g., "Alugar apartamento em São Paulo" or "business + housetype + location") — these map to High intent clusters in the keyword taxonomy.

### Keyword Clusters

Keywords are grouped by semantic similarity and search intent to align content and pages with user intention. Clusters are categorized into three intent levels: **High intent** (strong conversion intent — buy/rent), **Mid intent** (research phase, comparisons), and **Low intent** (broad informational searches). A key strategic use of clusters is competitor benchmarking: comparing performance within each cluster reveals optimization opportunities such as content coverage gaps, indexation issues, and tech SEO improvements. The **goldenset** is the curated subset of highest-priority keywords for focused optimization effort.

### Google Search Console (GSC) and SEMrush

**GSC** is QuintoAndar's primary source for own-site organic performance: search queries, impressions, clicks, CTR, and average position. A key analytical pattern is identifying queries with high impressions but low CTR — these signal ranking presence without capturing clicks, pointing to content or title optimization opportunities.

**SEMrush** adds the competitive intelligence layer that GSC lacks: keyword rankings and search volume across competitors, domain authority, and backlink profiles. It reveals what drives category-wide visibility and where QuintoAndar has ranking gaps versus players like Zap, Viva Real, and OLX. Use GSC for QuintoAndar's own performance analysis; use SEMrush for market positioning and competitive benchmarking.

### QAC - QuintoAndar Classifieds

QAC is QuintoAndar’s initiative to become the definitive Destination for Housing by displaying the full market inventory, including Navent (Imovelweb, Wimoveis, ..) listings not managed by QuintoAndar. It operates as a freemium model for the 3P Marketplace. Start date of the first QAC version: May 26, 2026 (for city groups of Belo Horizonte, Porto Alegre and Campinas). Mega-Launch start date: July 2026 (for city groups of v1 plus RMSP, Curitiba, Brasilia and Goiânia), with 3P freemium model publicly positioned and aggressive supply display expansion to additional markets.
