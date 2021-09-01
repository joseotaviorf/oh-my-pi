WITH
tenant_prospect_status as (
    SELECT
        sk_client,
        city_group,
        ts_start,
        ts_end,
        status,
        status_detail,
        LAG(status) OVER(PARTITION BY sk_client, city_group order by ts_start) as last_status
    FROM
        datamarts.tenant_prospect_status
    WHERE
        ts_start >= ts_first_activation
),
-----------------------------
-- Query the bottom funnel --
-----------------------------
rental_funnel AS (
    SELECT DISTINCT
        flrf.sk_client,
        flrf.sk_house_listing,
        SUBSTRING(flrf.sk_house_listing, 1, 9) AS id_house,
        NULLIF(flrf.sk_booking, -1) AS sk_booking,
        NULLIF(flrf.sk_offer, -1) AS sk_offer,
        NULLIF(flrf.sk_proposal, -1) AS sk_proposal,
        NULLIF(flrf.sk_contract, -1) AS sk_contract,
        dd_bc.date AS dt_booking_created,
        flrf.flg_visit_completed,
        dd_os.date AS dt_offer_submitted,
        dd_oa.date AS dt_offer_approved,
        dd_ds.date AS dt_tenant_first_doc_sent,
        dd_ca.date AS dt_credit_analysis_approved,
        dd_cs.date AS dt_contract_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_date AS dd_bc
            ON flrf.sk_booking_created_date = dd_bc.sk_date
        JOIN dim_date AS dd_os
            ON flrf.sk_offer_submitted_date = dd_os.sk_date
        JOIN dim_date AS dd_oa
            ON flrf.sk_offer_approved_date = dd_oa.sk_date
        JOIN dim_date AS dd_ds
            ON flrf.sk_tenant_first_doc_sent_date = dd_ds.sk_date
        JOIN dim_date AS dd_ca
            ON flrf.sk_credit_analysis_approved_date = dd_ca.sk_date
        JOIN dim_date AS dd_cs
            ON flrf.sk_contract_signed_date = dd_cs.sk_date
    WHERE
        COALESCE(dd_bc.date, dd_os.date) > 0
),
--------------------------------------------------------------------------------------
-- Join rent bottom funnel in the first rent flow cohort and introduce 0s for UNION --
--------------------------------------------------------------------------------------
fact_rent_flows AS (
    SELECT
        rf.dt_event,
        rf.ts_event,
        tps.status,
        tps.status_detail,
        tps.ts_start AS ts_status_start,
        tps.ts_end AS ts_status_end,
        dr.city_group,
        rf.flow_event,
        rf.mkt_origin,
        rf.mkt_channel,
        rf.mkt_medium,
        rf.mkt_source,
        rf.utm_medium,
        rf.utm_source,
        rf.utm_campaign,
        rf.utm_term,
        rf.utm_content,
        NULL::TEXT AS campaign_name,
        rf.sk_rf,
        rf.sk_client,
        rf.sk_house_listing,
        rf.id_house,
        rf.rent_flow_order,
        rf.tenant_prospect_order,
        frf.sk_booking,
        frf.sk_offer,
        frf.sk_proposal,
        frf.sk_contract,
        frf.dt_booking_created,
        frf.flg_visit_completed,
        frf.dt_offer_submitted,
        frf.dt_offer_approved,
        frf.dt_tenant_first_doc_sent,
        frf.dt_credit_analysis_approved,
        frf.dt_contract_signed,
        0.0 AS marketing_cost,
        0.0 AS new_rent_flows_target,
        0.0 AS new_tenant_prospects_target,
        0.0 AS budget
    FROM
        datamarts.rent_flow_interactions AS rf
        JOIN dim_region AS dr
            USING(sk_region)
        LEFT JOIN rental_funnel AS frf
            ON rf.sk_client = frf.sk_client
            AND rf.id_house = frf.id_house
        LEFT JOIN tenant_prospect_status AS tps
            ON rf.ts_event >= tps.ts_start
            AND rf.ts_event <= COALESCE(tps.ts_end, CURRENT_DATE)
            AND rf.sk_client = tps.sk_client
            AND dr.city_group = tps.city_group
            AND tps.status = 'ACTIVE'
    WHERE
        rf.rent_flow_order = 1
),
-------------------------------------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment for Rental Demand costs (mkt_origin = 'Tenants PWA') and introduce NULLs for UNION --
-------------------------------------------------------------------------------------------------------------------------------
demand_daily_spent AS (
    SELECT
        dd.date AS dt_event,
        dd.date::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL::TEXT AS status_detail,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        co.city_group,
        NULL::TEXT AS flow_event,
        co.mkt_origin,
        co.mkt_channel,
        co.mkt_medium,
        co.mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        co.utm_campaign,
        co.utm_term,
        co.utm_content,
        co.campaign_name,
        NULL AS sk_rf,
        NULL::INT AS sk_client,
        NULL::INT AS sk_house_listing,
        NULL::INT AS id_house,
        NULL::INT AS rent_flow_order,
        NULL::INT AS tenant_prospect_order,
        NULL::INT AS sk_booking,
        NULL::INT AS sk_offer,
        NULL::INT AS sk_proposal,
        NULL::INT AS sk_contract,
        NULL::DATE AS dt_booking_created,
        NULL::BOOL AS flg_visit_completed,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_approved,
        NULL::DATE AS dt_tenant_first_doc_sent,
        NULL::DATE AS dt_credit_analysis_approved,
        NULL::DATE AS dt_contract_signed,
        SUM(co.cost::FLOAT) AS marketing_cost,
        COUNT(NULL) AS new_rent_flows_target,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS budget
    FROM
        marketing.fact_marketing_daily_costs AS co
        JOIN dim_date AS dd
            ON dd.sk_date = co.sk_date
    WHERE
        co.mkt_origin = 'Tenants PWA'
        AND dd.date >= DATE('2018-01-01')
        AND co.mkt_medium != 'Branding'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35
),
taxonomy AS (
    SELECT DISTINCT
        td.Origin as mkt_origin,
        td.Channel as mkt_channel,
        td.Medium as mkt_medium
    FROM
        datalake_raw.gsheets_taxonomy_demand AS td
    WHERE
        td.Channel NOT IN  ('Paid Retention', 'Paid Traffic')
),
target_sheets AS (
    SELECT
        NULLIF(str.date, '')::date AS dt_event,
        NULLIF(str.city_group, '') AS city_group,
        'Tenants PWA' AS mkt_origin,
        NULLIF(str.mkt_channel, '') AS mkt_channel,
        NULLIF(str.mkt_medium, '') AS mkt_medium,
        NULLIF(str.mkt_source, '') AS mkt_source,
        NULLIF(str.new_rent_flows_target, '')::FLOAT AS new_rent_flows_target,
        NULLIF(str.new_tenant_prospects_target, '')::FLOAT AS new_tenant_prospects_target,
        NULLIF(str.budget, '')::FLOAT AS budget
    FROM
        datalake_gsheets_clean_prod.demand_targets_replanning AS str
    WHERE
        NULLIF(str.date, '')::date < DATE('2021-08-01')

    UNION ALL

    SELECT
        NULLIF(cps.date, '')::date AS dt_event,
        NULLIF(cps.city, '') AS city_group,
        'Tenants PWA' AS mkt_origin,
        NULLIF(t.mkt_channel, '') AS mkt_channel,
        NULLIF(cps.mkt_medium, '') AS mkt_medium,
        NULLIF(cps.mkt_source, '') AS mkt_source,
        NULL::FLOAT AS new_rent_flows_target,
        NULL::FLOAT AS new_tenant_prospects_target,
        NULLIF(cps.daily_value, '')::FLOAT AS budget
    FROM datalake_gsheets_clean_prod.mkt_cost_per_source AS cps
        LEFT JOIN taxonomy AS t
            ON cps.mkt_medium = t.mkt_medium
    WHERE
        business = 'Rent'
        AND NULLIF(cps.date, '')::date >= DATE('2021-08-01')

    UNION ALL

    SELECT
        NULLIF(date, '')::date AS dt_event,
        city_group,
        'Tenants PWA' AS mkt_origin,
        CASE
            WHEN mkt_channel IN ('Lost Tracking', 'Not Mapped', 'Agents') THEN 'Other'
            ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium,
        mkt_source,
        NULL::FLOAT AS new_rent_flows_target,
        NULLIF(ntp_target, '')::FLOAT AS new_tenant_prospects_target,
        NULL::FLOAT AS budget
    FROM
        datalake_gsheets_clean_prod.rental_ntp_source_targets
    WHERE
        NULLIF(date, '')::date >= DATE('2021-08-01')
),
-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
demand_daily_targets AS (
    SELECT
        dt_event,
        dt_event::TIMESTAMP AS ts_event,
        NULL::TEXT AS status,
        NULL::TEXT AS status_detail,
        NULL::TIMESTAMP AS ts_status_start,
        NULL::TIMESTAMP AS ts_status_end,
        city_group,
        NULL::TEXT AS flow_event,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS campaign_name,
        NULL AS sk_rf,
        NULL::INT AS sk_client,
        NULL::INT AS sk_house_listing,
        NULL::INT AS id_house,
        NULL::INT AS rent_flow_order,
        NULL::INT AS tenant_prospect_order,
        NULL::INT AS sk_booking,
        NULL::INT AS sk_offer,
        NULL::INT AS sk_proposal,
        NULL::INT AS sk_contract,
        NULL::DATE AS dt_booking_created,
        NULL::BOOL AS flg_visit_completed,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_approved,
        NULL::DATE AS dt_tenant_first_doc_sent,
        NULL::DATE AS dt_credit_analysis_approved,
        NULL::DATE AS dt_contract_signed,
        0.0 AS marketing_cost,
        new_rent_flows_target,
        new_tenant_prospects_target,
        budget
    FROM
        target_sheets
),
-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
deactivations AS (
    SELECT
        DATE(ts_start) AS dt_event,
        ts_start AS ts_event,
        status,
        status_detail,
        ts_start AS ts_status_start,
        ts_end AS ts_status_end,
        city_group,
        NULL::TEXT AS flow_event,
        NULL::text as mkt_origin,
        NULL::text as mkt_channel,
        NULL::text as mkt_medium,
        NULL::text as mkt_source,
        NULL::TEXT AS utm_medium,
        NULL::TEXT AS utm_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS campaign_name,
        NULL AS sk_rf,
        sk_client,
        NULL::INT AS sk_house_listing,
        NULL::INT AS id_house,
        NULL::INT AS rent_flow_order,
        NULL::INT AS tenant_prospect_order,
        NULL::INT AS sk_booking,
        NULL::INT AS sk_offer,
        NULL::INT AS sk_proposal,
        NULL::INT AS sk_contract,
        NULL::DATE AS dt_booking_created,
        NULL::BOOL AS flg_visit_completed,
        NULL::DATE AS dt_offer_submitted,
        NULL::DATE AS dt_offer_approved,
        NULL::DATE AS dt_tenant_first_doc_sent,
        NULL::DATE AS dt_credit_analysis_approved,
        NULL::DATE AS dt_contract_signed,
        0.0 AS marketing_cost,
        NULL::INT AS new_rent_flows_target,
        NULL::INT AS new_tenant_prospects_target,
        NULL::INT AS budget
    FROM
        tenant_prospect_status
    WHERE
        status IN ('CHURNED', 'RENTED')
        AND last_status = 'ACTIVE'
)
SELECT
    rf.*
FROM
    fact_rent_flows AS rf

UNION ALL

SELECT
    dds.*
FROM
    demand_daily_spent AS dds

UNION ALL

SELECT
    ddt.*
FROM
    demand_daily_targets AS ddt

UNION ALL

SELECT
    d.*
FROM
    deactivations AS d;