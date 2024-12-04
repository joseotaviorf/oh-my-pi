WITH fact_house_listing_flows_adjust AS (
    SELECT
        hl.sk_house_listing_flow,
        hl.sk_lead,
        hl.sk_house_listing,
        hl.sk_region,
        hl.mkt_completion,
        hl.has_isales_intervention,
        hl.has_fup_photo_task,
        hl.sk_lead_date,
        hl.sk_prospect_date,
        hl.sk_qualified_date,
        hl.sk_available_qualified_date,
        hl.sk_opportunity_date,
        hl.sk_first_listing_date,
        hl.sk_first_contact_date,
        hl.sk_conversion_date,
        hl.sk_discard_date,
        hl.lead_origin,
        hl.funnel_drop_reason,
        dua.mkt_origin AS affiliate_mkt_origin,
        dua.mkt_channel AS affiliate_mkt_channel,
        dua.mkt_medium AS affiliate_mkt_medium,
        dua.mkt_source AS affiliate_mkt_source,
        hl.mkt_channel,
        hl.mkt_source,
        hl.mkt_medium,
        hl.lead_context_origin,
        hl.sk_user_lead_affiliate,
        hl.sk_user_house_registrant,
        hl.is_b2b,
        dhl.rental_administrator,
        CASE
            WHEN dhl.is_for_rent= True
                 AND dhl.consultant_type = 'CIQ_FULL' THEN 'CIQ'
            WHEN dhl.is_for_rent=True
                AND hl.mkt_origin = 'CIQ'
                AND dhl.consultant_type = 'CIQ_MANAGER' THEN 'Backend'
            WHEN hl.mkt_origin = 'CIQ'
                AND (dhl.consultant_type IS NULL
                     OR dhl.consultant_type = 'Core') THEN 'Other'
            ELSE hl.mkt_origin
        END AS mkt_origin,
        dhl.ts_house_first_publication,
        FROM_UTC_TIMESTAMP(dhl.ts_house_first_publication,'Brazil/East') AS ts_house_first_publication_br_tz,
        CASE
            WHEN LOWER(om.sales_company) = 'mensageria'
                OR LOWER(olc.sales_company) = 'mensageria'
                OR LOWER(dl.sales_company) = 'mensageria'
                OR LOWER(du.sales_company) = 'mensageria'
                THEN 'MENSAGERIA'
            WHEN om.sales_company IS NOT NULL
                THEN om.sales_company
            WHEN olc.sales_company IS NOT NULL
                THEN olc.sales_company
            WHEN dl.sales_company = 'OLOS' AND hl.ops_agent = 'IS_INBOUND'
              THEN 'QUINTO_ANDAR_INBOUND'
            WHEN dl.sales_company = 'OLOS' AND hl.ops_agent = 'IS_OUTBOUND'
              THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN dl.sales_company = 'OLOS'
                THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN IFNULL(dl.sales_company, '') <> 'OLOS' AND du.sales_company = 'QUINTO_ANDAR'
                THEN 'QUINTO_ANDAR_INBOUND'
            ELSE COALESCE(du.sales_company, dl.sales_company)
        END AS sales_company
    FROM
        dw_public.fact_house_listing_flows AS hl
    INNER JOIN
        dw_rent.dim_house_listing AS dhl
            ON hl.sk_house_listing = dhl.sk_house_listing
    JOIN
        dw_public.dim_lead AS dl
            ON dl.sk_lead = hl.sk_lead
    LEFT JOIN
        dw_quintoandar.dim_user_sales_rep AS du
            ON du.sk_user_sales_rep = hl.sk_user_house_registrant
    LEFT JOIN
        datalake_olos_dialer.outbound_mailing AS om
            ON om.id_lead = hl.sk_lead
    LEFT JOIN
        datalake_olos_dialer.outbound_last_contact olc
            ON olc.id_lead = hl.sk_lead
    LEFT JOIN dw_public.dim_user_affiliate dua
        ON hl.sk_user_lead_affiliate = dua.sk_user
),
source_ops_rent AS (
    WITH photo_job AS (
        SELECT
            LEFT(fpj.sk_house_listing,9) AS sk_house,
            MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
            MIN(dpj.dt_job_scheduled) AS ts_first_job_scheduled,
            SUM(CASE
                    WHEN fpj.creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1
                    ELSE 0
                END) AS photo_job_by_isales
        FROM
            dw_public.fact_photo_job AS fpj
        LEFT JOIN
            dw_public.dim_photo_job AS dpj
                on fpj.id_photo_job = dpj.sk_photo_job
        GROUP BY 1
    )
    SELECT
        hlf.sk_house_listing_flow,
        hlf.sk_lead,
        hlf.sk_house_listing,
        hlf.sales_company,
        CASE
            WHEN hlf.mkt_origin = 'B2B'
                AND hlf.is_b2b = TRUE THEN 'B2B'
            WHEN hlf.mkt_origin = 'CIQ' THEN 'CIQ'
            WHEN (hlf.mkt_completion = 'Full Self-Service'
                    OR (hlf.has_isales_intervention = false))
                    AND (photo_job_by_isales < 1) THEN 'FSS'
            WHEN (hlf.mkt_completion = 'Full Self-Service'
                    OR (hlf.has_isales_intervention = false))
                    AND photo_job_by_isales >= 1
                    AND sk_first_photo_job_date = hlf.sk_opportunity_date THEN 'FSS IS PhotoJob'
            WHEN hlf.sales_company = 'MENSAGERIA' THEN 'MENSAGERIA'
            WHEN hlf.sales_company IN ('QUINTO_ANDAR','OLOS','QUINTO_ANDAR_INBOUND','QUINTO_ANDAR_OUTBOUND','') THEN 'IS Int'
            WHEN hlf.sales_company IN ('ACTION_LINE','ATENTO','ALGAR','AEC') THEN 'IS Ext'
            ELSE  'Other'
        END AS sourcing_ops,
        CASE
            WHEN hlf.sk_lead_date = ssf.sk_lead_date
                AND hlf.sk_lead_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_lead_date > 0 THEN 'Rent'
            ELSE NULL
        END AS lead_context,
        CASE
            WHEN hlf.sk_prospect_date = ssf.sk_prospect_date
                AND hlf.sk_prospect_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_prospect_date > 0 THEN 'Rent'
            ELSE NULL
        END AS prospect_context,
        CASE
            WHEN hlf.sk_qualified_date = ssf.sk_qualified_date
                AND hlf.sk_qualified_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_qualified_date > 0  THEN 'Rent'
            ELSE NULL
        END AS qualified_context,
        CASE
            WHEN hlf.sk_available_qualified_date = ssf.sk_available_qualified_date
                AND hlf.sk_available_qualified_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_available_qualified_date > 0  THEN 'Rent'
            ELSE NULL
        END AS available_qualified_context,
        CASE
            WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date
                AND hlf.sk_opportunity_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_opportunity_date > 0  THEN 'Rent'
            ELSE NULL
        END AS opportunity_context,
        CASE
            WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date
                AND hlf.sk_first_listing_date > 0 THEN 'Hybrid'
            WHEN hlf.sk_first_listing_date > 0  THEN 'Rent'
            ELSE NULL
        END AS first_listing_context,
        hlf.lead_origin,
        hlf.rental_administrator,
        hlf.funnel_drop_reason,
        pj.sk_first_photo_job_date,
        pj.ts_first_job_scheduled,
        FROM_UTC_TIMESTAMP(pj.ts_first_job_scheduled,'Brazil/East') AS ts_first_job_scheduled_br_tz
    FROM
        fact_house_listing_flows_adjust AS hlf
        LEFT JOIN
            photo_job AS pj
                ON pj.sk_house = LEFT(hlf.sk_house_listing,9)
        LEFT JOIN
            dw_sale.fact_listing_flows AS ssf
                ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
),
sale_fact_listing_flows_adjust AS (
    SELECT
        hl.sk_house_listing_flow,
        hl.sk_lead,
        hl.sk_house_listing,
        hl.sk_region,
        hl.mkt_completion,
        hl.has_isales_intervention,
        hl.has_fup_photo_task,
        hl.sk_lead_date,
        hl.sk_prospect_date,
        hl.sk_qualified_date,
        hl.sk_available_qualified_date,
        hl.sk_opportunity_date,
        hl.sk_first_listing_date,
        hl.sk_first_contact_date,
        hl.sk_conversion_date,
        hl.sk_discard_date,
        hl.lead_origin,
        hl.funnel_drop_reason,
        dua.mkt_origin AS affiliate_mkt_origin,
        dua.mkt_channel AS affiliate_mkt_channel,
        dua.mkt_medium AS affiliate_mkt_medium,
        dua.mkt_source AS affiliate_mkt_source,
        hl.mkt_channel,
        hl.mkt_source,
        hl.mkt_medium,
        hl.lead_context_origin,
        hl.sk_user_lead_affiliate,
        hl.sk_user_house_registrant,
        hl.is_b2b,
        CASE
            WHEN  dl.consultant_type = 'CIQ_FULL'
                OR (dl.consultant_type='CIQ_MANAGER'
                    AND dl.ts_created > dt_consultant_started) THEN 'CIQ'
            ELSE hl.mkt_origin
        END AS mkt_origin,
        dl.ts_first_publication,
        FROM_UTC_TIMESTAMP(dl.ts_first_publication,'Brazil/East') AS ts_house_first_publication_br_tz,
        COALESCE(dl.is_casa_mineira_migration, false) as is_casa_mineira_migration,
        CASE
            WHEN LOWER(om.sales_company) = 'mensageria'
                OR LOWER(olc.sales_company) = 'mensageria'
                OR LOWER(dl.sales_company) = 'mensageria'
                OR LOWER(du.sales_company) = 'mensageria'
                THEN 'MENSAGERIA'
            WHEN om.sales_company IS NOT NULL
                THEN om.sales_company
            WHEN olc.sales_company IS NOT NULL
                THEN olc.sales_company
            WHEN dl.sales_company = 'OLOS' AND hl.ops_agent = 'IS_INBOUND'
              THEN 'QUINTO_ANDAR_INBOUND'
            WHEN dl.sales_company = 'OLOS' AND hl.ops_agent = 'IS_OUTBOUND'
              THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN dl.sales_company = 'OLOS'
                THEN 'QUINTO_ANDAR_OUTBOUND'
            WHEN IFNULL(dl.sales_company, '') <> 'OLOS' AND du.sales_company = 'QUINTO_ANDAR'
                THEN 'QUINTO_ANDAR_INBOUND'
            ELSE COALESCE(du.sales_company, dl.sales_company)
        END AS sales_company
    FROM
        dw_sale.fact_listing_flows AS hl
    LEFT JOIN
        dw_sale.dim_listing AS dl
            on left(hl.sk_house_listing,9) = dl.sk_house
    JOIN
        dw_public.dim_lead AS dl
            ON dl.sk_lead = hl.sk_lead
    LEFT JOIN
        dw_quintoandar.dim_user_sales_rep AS du
            ON du.sk_user_sales_rep = hl.sk_user_house_registrant
    LEFT JOIN
        datalake_olos_dialer.outbound_mailing AS om
            ON om.id_lead = hl.sk_lead
    LEFT JOIN
        datalake_olos_dialer.outbound_last_contact olc
            ON olc.id_lead = hl.sk_lead
    LEFT JOIN dw_public.dim_user_affiliate dua
        ON hl.sk_user_lead_affiliate = dua.sk_user
),
source_ops_sale AS (
    with photo_job AS (
        SELECT
            LEFT(fpj.sk_house_listing,9) AS sk_house,
            MIN(fpj.sk_date_job_created) AS sk_first_photo_job_date,
            MIN(dpj.dt_job_scheduled) AS ts_first_job_scheduled,
            SUM(CASE
                    WHEN fpj.creation_origin IN ('InsideSales_internal','InsideSales_external') THEN 1
                    ELSE 0
                END) AS photo_job_by_isales
        FROM
            dw_public.fact_photo_job AS fpj
        LEFT JOIN
            dw_public.dim_photo_job AS dpj
                ON fpj.id_photo_job = dpj.sk_photo_job
        GROUP BY 1
    )
    SELECT
        ssf.sk_house_listing_flow,
        ssf.sk_lead,
        ssf.sk_house_listing,
        ssf.sales_company,
        CASE
            WHEN ssf.mkt_origin = 'B2B'
                AND ssf.is_b2b = TRUE THEN 'B2B'
            WHEN ssf.mkt_origin = 'CIQ' THEN 'CIQ'
            WHEN (ssf.mkt_completion = 'Full Self-Service'
                    OR (ssf.has_isales_intervention = false))
                AND (photo_job_by_isales < 1) THEN 'FSS'
            WHEN (ssf.mkt_completion = 'Full Self-Service'
                    OR (ssf.has_isales_intervention = false))
                AND photo_job_by_isales >= 1
                AND sk_first_photo_job_date = ssf.sk_opportunity_date THEN 'FSS IS PhotoJob'
            WHEN ssf.sales_company = 'MENSAGERIA' THEN 'MENSAGERIA'
            WHEN ssf.sales_company IN ('QUINTO_ANDAR','OLOS','QUINTO_ANDAR_INBOUND','QUINTO_ANDAR_OUTBOUND','') THEN 'IS Int'
            WHEN ssf.sales_company IN ('ACTION_LINE','ATENTO','ALGAR','AEC') THEN 'IS Ext'
            ELSE  'Other'
        END AS sourcing_ops,
        CASE
            WHEN hlf.sk_lead_date = ssf.sk_lead_date
                AND ssf.sk_lead_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_lead_date > 0 THEN 'Sale'
            ELSE NULL
        END AS lead_context,
        CASE
            WHEN hlf.sk_prospect_date = ssf.sk_prospect_date
                AND ssf.sk_prospect_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_prospect_date > 0 THEN 'Sale'
            ELSE NULL
        END AS prospect_context,
        CASE
            WHEN hlf.sk_qualified_date = ssf.sk_qualified_date
                AND ssf.sk_qualified_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_qualified_date > 0  THEN 'Sale'
            ELSE NULL
        END AS qualified_context,
        CASE
            WHEN hlf.sk_available_qualified_date = ssf.sk_available_qualified_date
                AND ssf.sk_available_qualified_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_available_qualified_date > 0  THEN 'Sale'
            ELSE NULL
        END AS available_qualified_context,
        CASE
            WHEN hlf.sk_opportunity_date = ssf.sk_opportunity_date
                AND ssf.sk_opportunity_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_opportunity_date > 0  THEN 'Sale'
            ELSE NULL
        END AS opportunity_context,
        CASE
            WHEN hlf.sk_first_listing_date = ssf.sk_first_listing_date
                AND ssf.sk_first_listing_date > 0 THEN 'Hybrid'
            WHEN ssf.sk_first_listing_date > 0  THEN 'Sale'
            ELSE NULL
        END AS first_listing_context,
        ssf.lead_origin,
        ssf.funnel_drop_reason,
        sk_first_photo_job_date,
        pj.ts_first_job_scheduled,
        FROM_UTC_TIMESTAMP(pj.ts_first_job_scheduled,'Brazil/East') AS ts_first_job_scheduled_br_tz,
        dhl.rental_administrator
    FROM
        sale_fact_listing_flows_adjust AS ssf
        LEFT JOIN
            photo_job AS pj
                ON pj.sk_house = LEFT(ssf.sk_house_listing,9)
        LEFT JOIN
            dw_public.fact_house_listing_flows AS hlf
                ON hlf.sk_house_listing_flow = ssf.sk_house_listing_flow
        LEFT JOIN
            dw_rent.dim_house_listing AS dhl
            ON dhl.sk_house_listing = hlf.sk_house_listing
        where ssf.is_casa_mineira_migration = false
),
fact_sale AS (
    SELECT
        ssf.sk_house_listing_flow,
        ssf.sk_lead,
        ssf.sk_house_listing,
        ssf.sk_region,
        ssf.sk_lead_date,
        ssf.sk_first_contact_date,
        ssf.sk_prospect_date,
        ssf.sk_qualified_date,
        ssf.sk_available_qualified_date,
        ssf.sk_opportunity_date,
        ssf.sk_first_listing_date,
        ssf.sk_conversion_date,
        ssf.sk_discard_date,
        sor.lead_context AS context_lead,
        sor.prospect_context AS context_prospect,
        sor.qualified_context AS context_qualified,
        sor.available_qualified_context AS context_available_qualified,
        sor.opportunity_context AS context_opportunity,
        sor.first_listing_context AS context_first_listing,
        sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
        sor.ts_first_job_scheduled,
        sor.ts_first_job_scheduled_br_tz,
        ssf.ts_first_publication,
        ssf.ts_house_first_publication_br_tz,
        CASE
            WHEN ssf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE ssf.mkt_origin
        END AS mkt_origin,
        ssf.mkt_completion,
        ssf.mkt_channel,
        CASE
            WHEN ssf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE ssf.mkt_source
        END AS mkt_source,
        ssf.mkt_medium,
        ssf.affiliate_mkt_origin,
        ssf.affiliate_mkt_channel,
        ssf.affiliate_mkt_medium,
        ssf.affiliate_mkt_source,
        sor.sales_company,
        sor.sourcing_ops,
        ssf.lead_origin,
        ssf.funnel_drop_reason,
        ssf.lead_context_origin,
        ssf.has_isales_intervention,
        ssf.has_fup_photo_task,
        ssf.sk_user_lead_affiliate,
        'Sale' AS origin_table,
        sor.rental_administrator
    FROM
        sale_fact_listing_flows_adjust AS ssf
    JOIN
        source_ops_sale AS sor
            ON sor.sk_house_listing_flow = ssf.sk_house_listing_flow
    where ssf.is_casa_mineira_migration = false
),
fact_rent AS (
    SELECT
        hlf.sk_house_listing_flow,
        hlf.sk_lead,
        hlf.sk_house_listing,
        hlf.sk_region,
        hlf.sk_lead_date,
        hlf.sk_first_contact_date,
        hlf.sk_prospect_date,
        hlf.sk_qualified_date,
        hlf.sk_available_qualified_date,
        hlf.sk_opportunity_date,
        hlf.sk_first_listing_date,
        hlf.sk_conversion_date,
        hlf.sk_discard_date,
        sor.lead_context AS context_lead,
        sor.prospect_context AS context_prospect,
        sor.qualified_context AS context_qualified,
        sor.available_qualified_context AS context_available_qualified,
        sor.opportunity_context AS context_opportunity,
        sor.first_listing_context AS context_first_listing,
        sor.sk_first_photo_job_date AS sk_first_photojob_date_fact_photo_job,
        sor.ts_first_job_scheduled,
        sor.ts_first_job_scheduled_br_tz,
        hlf.ts_house_first_publication as ts_first_publication,
        hlf.ts_house_first_publication_br_tz,
        CASE
            WHEN hlf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE hlf.mkt_origin
        END AS mkt_origin,
        hlf.mkt_completion,
        hlf.mkt_channel,
        CASE
            WHEN hlf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE hlf.mkt_source
        END AS mkt_source,
        hlf.mkt_medium,
        hlf.affiliate_mkt_origin,
        hlf.affiliate_mkt_channel,
        hlf.affiliate_mkt_medium,
        hlf.affiliate_mkt_source,
        sor.sales_company,
        sor.sourcing_ops,
        hlf.lead_origin,
        hlf.funnel_drop_reason,
        hlf.lead_context_origin,
        hlf.has_isales_intervention,
        hlf.has_fup_photo_task,
        hlf.sk_user_lead_affiliate,
        'Rent' AS origin_table,
        hlf.rental_administrator
    FROM
        fact_house_listing_flows_adjust AS hlf
    JOIN
        source_ops_rent AS sor
            ON sor.sk_house_listing_flow = hlf.sk_house_listing_flow
),
union_all AS (
    SELECT
        *
    FROM
        fact_rent
    UNION ALL
    SELECT
        *
    FROM
        fact_sale
)
SELECT
    ua.sk_house_listing_flow,
    ua.sk_lead,
    CAST(LEFT(ua.sk_house_listing,9) AS BIGINT) AS sk_house,
    ua.sk_house_listing,
    ua.sk_region,
    ua.sk_lead_date,
    ua.sk_first_contact_date,
    ua.sk_prospect_date,
    ua.sk_qualified_date,
    ua.sk_available_qualified_date,
    ua.sk_opportunity_date,
    ua.sk_first_listing_date,
    ua.sk_conversion_date,
    ua.sk_discard_date,
    ua.sk_first_photojob_date_fact_photo_job,
    ua.sk_user_lead_affiliate,
    dr.country_code,
    ua.context_lead,
    ua.context_prospect,
    ua.context_qualified,
    ua.context_available_qualified,
    ua.context_opportunity,
    ua.context_first_listing,
    ua.mkt_origin,
    ua.mkt_completion,
    ua.mkt_channel,
    ua.mkt_source,
    ua.mkt_medium,
    ua.affiliate_mkt_origin,
    ua.affiliate_mkt_channel,
    ua.affiliate_mkt_medium,
    ua.affiliate_mkt_source,
    ua.sales_company,
    ua.sourcing_ops,
    ua.lead_origin,
    ua.funnel_drop_reason,
    ua.lead_context_origin,
    ua.origin_table,
    ua.rental_administrator,
    ROW_NUMBER() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_rn_prospect, -- column to help differentiate the prospect with equal dates
    DENSE_RANK() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_prospect_date,-1)) AS aux_order_prospect,
    ROW_NUMBER() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_rn_qualified, -- column to help differentiate the qualified with equal dates
    DENSE_RANK() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_qualified_date,-1)) AS aux_order_qualified,
    ROW_NUMBER() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_available_qualified_date,-1)) AS aux_rn_available_qualified, -- column to help differentiate the available qualified with equal dates
    DENSE_RANK() OVER(PARTITION BY ua.sk_house_listing_flow ORDER BY NULLIF(sk_available_qualified_date,-1)) AS aux_order_available_qualified,
    MIN(NULLIF(ua.sk_prospect_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS first_prospect_date,
    MAX(NULLIF(ua.sk_prospect_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS last_prospect_date,
    MIN(NULLIF(ua.sk_qualified_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS first_qualified_date,
    MAX(NULLIF(ua.sk_qualified_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS last_qualified_date,
    MIN(NULLIF(ua.sk_available_qualified_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS first_available_qualified_date,
    MAX(NULLIF(ua.sk_available_qualified_date,-1)) OVER(PARTITION BY ua.sk_house_listing_flow) AS last_available_qualified_date,
    ua.has_isales_intervention,
    ua.has_fup_photo_task,
    ua.ts_first_job_scheduled,
    ua.ts_first_job_scheduled_br_tz,
    ua.ts_first_publication,
    ua.ts_house_first_publication_br_tz
FROM
    union_all ua
    LEFT JOIN dw_public.dim_region dr
        ON ua.sk_region = dr.sk_region
