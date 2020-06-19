WITH
lead_date AS (
SELECT
    dd.week_start,
    dd.date,
    base.lead_origin_context,
    base.mkt_campaign_context,
    base.mkt_completion,
    base.mkt_channel,
    COUNT(base.id_house) AS lead
FROM datamarts.temp_sale_supply_funnel AS base
JOIN public.dim_date dd ON dd.sk_date = sk_lead_date
WHERE dd.date >= '2020-01-13' and dd.date < current_date
GROUP BY 1,2,3,4,5,6
),
prospect_date AS (
SELECT
    dd.week_start,
    dd.date,
    base.lead_origin_context,
    base.mkt_campaign_context,
    base.mkt_completion,
    base.mkt_channel,
    COUNT(base.id_house) AS prospect
FROM datamarts.temp_sale_supply_funnel AS base
JOIN public.dim_date dd ON dd.sk_date = sk_prospect_date
WHERE dd.date >= '2020-01-13' and dd.date < current_date
GROUP BY 1,2,3,4,5,6
),
qualified_date AS (
SELECT
    dd.week_start,
    dd.date,
    base.lead_origin_context,
    base.mkt_campaign_context,
    base.mkt_completion,
    base.mkt_channel,
    COUNT(base.id_house) AS qualified
FROM datamarts.temp_sale_supply_funnel AS base
JOIN public.dim_date dd ON dd.sk_date = sk_qualified_date
WHERE dd.date >= '2020-01-13' and dd.date < current_date
GROUP BY 1,2,3,4,5,6
),
opportunity_date AS (
SELECT
    dd.week_start,
    dd.date,
    base.lead_origin_context,
    base.mkt_campaign_context,
    base.mkt_completion,
    base.mkt_channel,
    COUNT(id_house) AS opportunity
FROM datamarts.temp_sale_supply_funnel AS base
JOIN public.dim_date dd ON dd.sk_date = sk_opportunity_date
WHERE dd.date >= '2020-01-13' and dd.date < current_date
GROUP BY 1,2,3,4,5,6
),
first_listing_date AS (
SELECT
    dd.week_start,
    dd.date,
    base.lead_origin_context,
    base.mkt_campaign_context,
    base.mkt_completion,
    base.mkt_channel,
    COUNT(id_house) AS first_listing
FROM datamarts.temp_sale_supply_funnel AS base
JOIN public.dim_date dd ON dd.sk_date = sk_first_listing_date
WHERE dd.date >= '2019-12-02' and dd.date < current_date
GROUP BY 1,2,3,4,5,6
)
SELECT
    date(coalesce(l.date, p.date, q.date, o.date, fl.date)) as date,
    date(coalesce(l.week_start, p.week_start, q.week_start, o.week_start, fl.week_start)) as week_start,
    coalesce(l.lead_origin_context, p.lead_origin_context, q.lead_origin_context, o.lead_origin_context, fl.lead_origin_context) AS "lead_origin_context",
    coalesce(l.mkt_campaign_context, p.mkt_campaign_context, q.mkt_campaign_context, o.mkt_campaign_context, fl.mkt_campaign_context) AS "mkt_campaign_context",
    coalesce(l.mkt_completion, p.mkt_completion, q.mkt_completion, o.mkt_completion, fl.mkt_completion) AS "mkt_completion",
    coalesce(l.mkt_channel, p.mkt_channel, q.mkt_channel, o.mkt_channel, fl.mkt_channel) AS "mkt_channel",
    CASE WHEN l.lead IS NULL THEN 0 ELSE l.lead END AS lead,
    CASE WHEN p.prospect IS NULL THEN 0 ELSE p.prospect END AS prospect,
    CASE WHEN q.qualified IS NULL THEN 0 ELSE q.qualified END AS qualified,
    CASE WHEN o.opportunity IS NULL THEN 0 ELSE o.opportunity END AS opportunity,
    CASE WHEN fl.first_listing IS NULL THEN 0 ELSE fl.first_listing END AS first_listing
FROM lead_date l
FULL JOIN prospect_date p
    ON p.week_start = l.week_start AND p.lead_origin_context = l.lead_origin_context AND p.mkt_campaign_context = l.mkt_campaign_context AND p.date = l.date
    AND p.mkt_completion = l.mkt_completion AND p.mkt_channel = l.mkt_channel
FULL JOIN qualified_date q
    ON q.week_start = l.week_start AND q.lead_origin_context = l.lead_origin_context AND q.mkt_campaign_context = l.mkt_campaign_context AND q.date = l.date
    AND q.mkt_completion = l.mkt_completion AND q.mkt_channel = l.mkt_channel
FULL JOIN opportunity_date o
    ON o.week_start = l.week_start AND o.lead_origin_context = l.lead_origin_context AND o.mkt_campaign_context = l.mkt_campaign_context  AND o.date = l.date
    AND o.mkt_completion = l.mkt_completion AND o.mkt_channel = l.mkt_channel
FULL JOIN first_listing_date fl
    ON fl.week_start = l.week_start AND fl.lead_origin_context = l.lead_origin_context AND fl.mkt_campaign_context = l.mkt_campaign_context AND fl.date = l.date
    AND fl.mkt_completion = l.mkt_completion AND fl.mkt_channel = l.mkt_channel
;
