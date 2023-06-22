WITH
tenant_prospect_status AS (
    SELECT
        sk_client,
        city_group,
        ts_start,
        ts_end,
        status,
        status_detail,
        LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) AS last_status,
        LEAD(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) AS next_status
    FROM
        dw_datamarts.tenant_prospect_status
    WHERE
        CAST(ts_start AS TIMESTAMP) >= CAST(ts_first_activation AS TIMESTAMP)
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
        CAST(NULLIF(flrf.sk_offer, -1) AS BIGINT) AS sk_offer,
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
        datalake_listing_temp.fact_listing_rent_flows_house AS flrf
    JOIN dw_public.dim_date AS dd_bc
        ON flrf.sk_booking_created_date = dd_bc.sk_date
    JOIN dw_public.dim_date AS dd_os
        ON flrf.sk_offer_submitted_date = dd_os.sk_date
    JOIN dw_public.dim_date AS dd_oa
        ON flrf.sk_offer_approved_date = dd_oa.sk_date
    JOIN dw_public.dim_date AS dd_ds
        ON flrf.sk_tenant_first_doc_sent_date = dd_ds.sk_date
    JOIN dw_public.dim_date AS dd_ca
        ON flrf.sk_credit_analysis_approved_date = dd_ca.sk_date
    JOIN dw_public.dim_date AS dd_cs
        ON flrf.sk_contract_signed_date = dd_cs.sk_date
    WHERE
        CAST(
            COALESCE(dd_bc.date, dd_os.date) AS DATE
        ) > CAST('1900-01-01' AS DATE)
),

--------------------------------------------------------------------------------------
-- Join rent bottom funnel in the first rent flow cohort and introduce 0s for UNION --
--------------------------------------------------------------------------------------
fact_rent_flows AS (
    SELECT
        CAST(rf.dt_event AS DATE) AS dt_event,
        CAST(rf.ts_event AS TIMESTAMP) AS ts_event,
        CAST(tps.status AS STRING) AS status,
        CAST(tps.status_detail AS STRING) AS status_detail,
        CAST(tps.next_status AS STRING) AS next_status,
        CAST(tps.ts_start AS TIMESTAMP) AS ts_status_start,
        CAST(tps.ts_end AS TIMESTAMP) AS ts_status_end,
        CAST(dr.city_group AS STRING) AS city_group,
        CAST(dr.country_name AS STRING) AS country_name,
        CAST(rf.flow_event AS STRING) AS flow_event,
        CAST(rf.mkt_origin AS STRING) AS mkt_origin,
        CAST(rf.mkt_channel AS STRING) AS mkt_channel,
        CAST(rf.mkt_medium AS STRING) AS mkt_medium,
        CAST(rf.mkt_source AS STRING) AS mkt_source,
        CAST(rf.utm_medium AS STRING) AS utm_medium,
        CAST(rf.utm_source AS STRING) AS utm_source,
        CAST(rf.utm_campaign AS STRING) AS utm_campaign,
        CAST(rf.utm_term AS STRING) AS utm_term,
        CAST(rf.utm_content AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS campaign_name,
        CAST(rf.sk_rf AS STRING) AS sk_rf,
        CAST(rf.sk_client AS BIGINT) AS sk_client,
        CAST(rf.sk_house_listing AS BIGINT) AS sk_house_listing,
        CAST(rf.id_house AS BIGINT) AS id_house,
        CAST(rf.rent_flow_order AS BIGINT) AS rent_flow_order,
        CAST(rf.tenant_prospect_order AS BIGINT) AS tenant_prospect_order,
        CAST(frf.sk_booking AS BIGINT) AS sk_booking,
        CAST(frf.sk_offer AS BIGINT) AS sk_offer,
        CAST(frf.sk_proposal AS BIGINT) AS sk_proposal,
        CAST(frf.sk_contract AS BIGINT) AS sk_contract,
        CAST(frf.dt_booking_created AS DATE) AS dt_booking_created,
        CAST(frf.flg_visit_completed AS BOOLEAN) AS flg_visit_completed,
        CAST(frf.dt_offer_submitted AS DATE) AS dt_offer_submitted,
        CAST(frf.dt_offer_approved AS DATE) AS dt_offer_approved,
        CAST(frf.dt_tenant_first_doc_sent AS DATE) AS dt_tenant_first_doc_sent,
        CAST(frf.dt_credit_analysis_approved AS DATE) AS dt_credit_analysis_approved,
        CAST(frf.dt_contract_signed AS DATE) AS dt_contract_signed,
        CAST(0.0 AS DOUBLE) AS marketing_cost,
        CAST(0.0 AS DOUBLE) AS rent_flows_target,
        CAST(0.0 AS DOUBLE) AS new_rent_flows_target,
        CAST(0.0 AS DOUBLE) AS new_tenant_prospects_target,
        CAST(0.0 AS DOUBLE) AS recovered_tenant_prospects_target,
        CAST(0.0 AS DOUBLE) AS budget
    FROM
        dw_datamarts.rent_flow_interactions AS rf
        JOIN dw_public.dim_region AS dr
            USING(sk_region)
        LEFT JOIN rental_funnel AS frf
            ON CAST(rf.sk_client AS BIGINT) = CAST(frf.sk_client AS BIGINT)
            AND CAST(rf.id_house AS INTEGER) = CAST(frf.id_house AS INTEGER)
        LEFT JOIN tenant_prospect_status AS tps
            ON CAST(rf.ts_event AS TIMESTAMP) >= CAST(tps.ts_start AS TIMESTAMP)
            AND CAST(rf.ts_event AS TIMESTAMP) <= CAST(COALESCE(tps.ts_end, CURRENT_DATE) AS TIMESTAMP)
            AND CAST(rf.sk_client AS BIGINT) = CAST(tps.sk_client AS BIGINT)
            AND CAST(dr.city_group AS STRING) = CAST(tps.city_group AS STRING)
            AND tps.status = 'ACTIVE'
    WHERE
        rf.rent_flow_order = 1
),

-------------------------------------------------------------------------------------------------------------------------------
-- Query Performance Marketing Investment for Rental Demand costs (mkt_origin = 'Tenants PWA') and introduce NULLs for UNION --
-------------------------------------------------------------------------------------------------------------------------------
demand_daily_spent AS (
    SELECT
        CAST(dd.date AS DATE) AS dt_event,
        CAST(dd.date AS TIMESTAMP) AS ts_event,
        CAST(NULL AS STRING) AS status,
        CAST(NULL AS STRING) AS status_detail,
        CAST(NULL AS STRING) AS next_status,
        CAST(NULL AS TIMESTAMP) AS ts_status_start,
        CAST(NULL AS TIMESTAMP) AS ts_status_end,
        CAST(co.city_group AS STRING) AS city_group,
        CAST(NULL AS STRING) AS country_name,
        CAST(NULL AS STRING) AS flow_event,
        CAST(co.mkt_origin AS STRING) AS mkt_origin,
        CAST(co.mkt_channel AS STRING) AS mkt_channel,
        CAST(co.mkt_medium AS STRING) AS mkt_medium,
        CAST(co.mkt_source AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_medium,
        CAST(NULL AS STRING) AS utm_source,
        CAST(co.utm_campaign AS STRING) AS utm_campaign,
        CAST(co.utm_term AS STRING) AS utm_term,
        CAST(co.utm_content AS STRING) AS utm_content,
        CAST(co.campaign_name AS STRING) AS campaign_name,
        CAST(NULL AS STRING) AS sk_rf,
        CAST(NULL AS BIGINT) AS sk_client,
        CAST(NULL AS BIGINT) AS sk_house_listing,
        CAST(NULL AS BIGINT) AS id_house,
        CAST(NULL AS BIGINT) AS rent_flow_order,
        CAST(NULL AS BIGINT) AS tenant_prospect_order,
        CAST(NULL AS BIGINT) AS sk_booking,
        CAST(NULL AS BIGINT) AS sk_offer,
        CAST(NULL AS BIGINT) AS sk_proposal,
        CAST(NULL AS BIGINT) AS sk_contract,
        CAST(NULL AS DATE) AS dt_booking_created,
        CAST(NULL AS BOOLEAN) AS flg_visit_completed,
        CAST(NULL AS DATE) AS dt_offer_submitted,
        CAST(NULL AS DATE) AS dt_offer_approved,
        CAST(NULL AS DATE) AS dt_tenant_first_doc_sent,
        CAST(NULL AS DATE) AS dt_credit_analysis_approved,
        CAST(NULL AS DATE) AS dt_contract_signed,
        CAST(SUM(co.cost) AS DOUBLE) AS marketing_cost,
        CAST(COUNT(NULL) AS DOUBLE) AS rent_flows_target,
        CAST(COUNT(NULL) AS DOUBLE) AS new_rent_flows_target,
        CAST(COUNT(NULL) AS DOUBLE) AS new_tenant_prospects_target,
        CAST(COUNT(NULL) AS DOUBLE) AS recovered_tenant_prospects_target,
        CAST(COUNT(NULL) AS DOUBLE) AS budget
    FROM
        datalake_marketing_costs.daily_costs AS co
        JOIN dw_public.dim_date AS dd
            ON dd.sk_date = co.id_date
    WHERE
        co.mkt_origin = 'Tenants PWA'
        AND CAST(dd.date AS DATE) >= CAST('2018-01-01' AS DATE)
        AND co.mkt_medium != 'Branding'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36
),

target_sheets AS (
    SELECT
        str.dt_target AS dt_event,
        NULLIF(str.city_group, '') AS city_group,
        'Tenants PWA' AS mkt_origin,
        NULLIF(str.mkt_channel, '') AS mkt_channel,
        NULLIF(str.mkt_medium, '') AS mkt_medium,
        NULLIF(str.mkt_source, '') AS mkt_source,
        CAST(NULL AS FLOAT) AS rent_flows_target,
        NULLIF(str.new_rent_flows_target, '')::FLOAT AS new_rent_flows_target,
        NULLIF(str.new_tenant_prospects_target, '')::FLOAT AS new_tenant_prospects_target,
        CAST(NULL AS FLOAT) AS recovered_tenant_prospects_target,
        NULLIF(str.budget, '')::FLOAT AS budget
    FROM
        datalake_gsheets_clean.demand_targets_replanning AS str
    WHERE
        CAST(str.dt_target AS DATE) < CAST('2021-08-01' AS DATE)

    UNION ALL

    SELECT
        cps.dt_event,
        cps.city_group,
        'Tenants PWA' AS mkt_origin,
        NULLIF(cps.mkt_channel, '') AS mkt_channel,
        NULLIF(cps.mkt_medium, '') AS mkt_medium,
        NULLIF(cps.mkt_source, '') AS mkt_source,
        CAST(NULL AS FLOAT) AS rent_flows_target,
        CAST(NULL AS FLOAT) AS new_rent_flows_target,
        CAST(NULL AS FLOAT) AS new_tenant_prospects_target,
        CAST(NULL AS FLOAT) AS recovered_tenant_prospects_target,
        cps.daily_value AS budget
    FROM datalake_gsheets_clean.mkt_cost_per_source AS cps
    WHERE
        business = 'Rent'
        AND CAST(dt_event AS DATE) >= CAST('2021-08-01' AS DATE)

    UNION ALL

    SELECT
        NULLIF(dt_target, '')::DATE AS dt_event,
        city_group,
        'Tenants PWA' AS mkt_origin,
        CASE
            WHEN mkt_channel IN ('Lost Tracking', 'Not Mapped', 'Agents') THEN 'Other'
            ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium,
        mkt_source,
        CAST(NULL AS FLOAT) AS rent_flows_target,
        CAST(NULL AS FLOAT) AS new_rent_flows_target,
        CAST(NULLIF(ntp_target, '') AS FLOAT) AS new_tenant_prospects_target,
        CAST(NULLIF(rtp_target, '') AS FLOAT) AS recovered_tenant_prospects_target,
        CAST(NULL AS FLOAT) AS budget
    FROM
        datalake_gsheets_clean.rental_ntp_source_targets
    WHERE
        CAST(NULLIF(dt_target, '') AS DATE) >= CAST('2021-08-01' AS DATE)

    UNION ALL

    SELECT
        NULLIF(date, '')::DATE AS dt_event,
        city_group,
        'Tenants PWA' AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        NULLIF(rf_target, '')::FLOAT AS rent_flows_target,
        CAST(NULL AS FLOAT) AS new_rent_flows_target,
        CAST(NULL AS FLOAT) AS new_tenant_prospects_target,
        CAST(NULL AS FLOAT) AS recovered_tenant_prospects_target,
        CAST(NULL AS FLOAT) AS budget
    FROM
        datalake_gsheets_clean.rental_flows_targets
),

-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
demand_daily_targets AS (
    SELECT
        CAST(dt_event AS DATE) AS dt_event,
        CAST(dt_event AS TIMESTAMP) AS ts_event,
        CAST(NULL AS STRING) AS status,
        CAST(NULL AS STRING) AS status_detail,
        CAST(NULL AS STRING) AS next_status,
        CAST(NULL AS TIMESTAMP) AS ts_status_start,
        CAST(NULL AS TIMESTAMP) AS ts_status_end,
        CAST(city_group AS STRING) AS city_group,
        CAST(NULL AS STRING) AS country_name,
        CAST(NULL AS STRING) AS flow_event,
        CAST(mkt_origin AS STRING) AS mkt_origin,
        CAST(mkt_channel AS STRING) AS mkt_channel,
        CAST(mkt_medium AS STRING) AS mkt_medium,
        CAST(mkt_source AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_medium,
        CAST(NULL AS STRING) AS utm_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS campaign_name,
        CAST(NULL AS STRING) AS sk_rf,
        CAST(NULL AS BIGINT) AS sk_client,
        CAST(NULL AS BIGINT) AS sk_house_listing,
        CAST(NULL AS BIGINT) AS id_house,
        CAST(NULL AS BIGINT) AS rent_flow_order,
        CAST(NULL AS BIGINT) AS tenant_prospect_order,
        CAST(NULL AS BIGINT) AS sk_booking,
        CAST(NULL AS BIGINT) AS sk_offer,
        CAST(NULL AS BIGINT) AS sk_proposal,
        CAST(NULL AS BIGINT) AS sk_contract,
        CAST(NULL AS DATE) AS dt_booking_created,
        CAST(NULL AS BOOLEAN) AS flg_visit_completed,
        CAST(NULL AS DATE) AS dt_offer_submitted,
        CAST(NULL AS DATE) AS dt_offer_approved,
        CAST(NULL AS DATE) AS dt_tenant_first_doc_sent,
        CAST(NULL AS DATE) AS dt_credit_analysis_approved,
        CAST(NULL AS DATE) AS dt_contract_signed,
        CAST(0.0 AS DOUBLE) AS marketing_cost,
        CAST(rent_flows_target AS DOUBLE) AS rent_flows_target,
        CAST(new_rent_flows_target AS DOUBLE) AS new_rent_flows_target,
        CAST(new_tenant_prospects_target AS DOUBLE) AS new_tenant_prospects_target,
        CAST(recovered_tenant_prospects_target AS DOUBLE) AS new_tenant_prospects_target,
        CAST(budget AS DOUBLE) AS budget
    FROM
        target_sheets
),

-------------------------------------------------------------------------------------
-- Query Performance Marketing Rental Demand targets and introduce NULLs for UNION --
-------------------------------------------------------------------------------------
deactivations AS (
    SELECT
        DATE(ts_start) AS dt_event,
        CAST(ts_start AS TIMESTAMP) AS ts_event,
        CAST(status AS STRING) AS status,
        CAST(status_detail AS STRING) AS status_detail,
        CAST(NULL AS STRING) AS next_status,
        CAST(ts_start AS TIMESTAMP) AS ts_status_start,
        CAST(ts_end AS TIMESTAMP) AS ts_status_end,
        CAST(city_group AS STRING) AS city_group,
        CAST(NULL AS STRING) AS country_name,
        CAST(NULL AS STRING) AS flow_event,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_medium,
        CAST(NULL AS STRING) AS utm_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS campaign_name,
        CAST(NULL AS STRING) AS sk_rf,
        CAST(sk_client AS BIGINT) AS sk_client,
        CAST(NULL AS BIGINT) AS sk_house_listing,
        CAST(NULL AS BIGINT) AS id_house,
        CAST(NULL AS BIGINT) AS rent_flow_order,
        CAST(NULL AS BIGINT) AS tenant_prospect_order,
        CAST(NULL AS BIGINT) AS sk_booking,
        CAST(NULL AS BIGINT) AS sk_offer,
        CAST(NULL AS BIGINT) AS sk_proposal,
        CAST(NULL AS BIGINT) AS sk_contract,
        CAST(NULL AS DATE) AS dt_booking_created,
        CAST(NULL AS BOOLEAN) AS flg_visit_completed,
        CAST(NULL AS DATE) AS dt_offer_submitted,
        CAST(NULL AS DATE) AS dt_offer_approved,
        CAST(NULL AS DATE) AS dt_tenant_first_doc_sent,
        CAST(NULL AS DATE) AS dt_credit_analysis_approved,
        CAST(NULL AS DATE) AS dt_contract_signed,
        CAST(0.0 AS DOUBLE) AS marketing_cost,
        CAST(NULL AS DOUBLE) AS rent_flows_target,
        CAST(NULL AS DOUBLE) AS new_rent_flows_target,
        CAST(NULL AS DOUBLE) AS new_tenant_prospects_target,
        CAST(NULL AS DOUBLE) AS recovered_tenant_prospects_target,
        CAST(NULL AS DOUBLE) AS budget
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
    deactivations AS d
