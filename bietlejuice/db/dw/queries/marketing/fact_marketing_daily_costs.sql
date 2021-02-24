/*
 *   Description:
 *       These CTEs collect information FROM several marketing campaign source tables and share the costs between city groups,
 *       funnel side (e.g., demand, supply) and platform (e.g., mobile, Desktop, other) grouping by date.
 *       The rules to share costs between city groups, funnel side and platform depends on marketing source and are
 *       defined in each specific CTE.
 */
-- Google daily costs (Manual and Fact)
WITH google_consolidated_cost AS (
    WITH t_google AS (
        SELECT
            fg.sk_date,
            COALESCE(dgk.campaign_name, dga.campaign_name, dgc.campaign_name, dgv.campaign_name) AS campaign_name,
            COALESCE(dgk.account_name, dga.account_name, dgc.account_name, dgv.account_name) AS account_name,
            COALESCE(dgk.report_type, dga.report_type, dgc.report_type, dgv.report_type) AS report_type,
            COALESCE(gtatf.flag, 'other') AS ad_type,
            CASE WHEN fg.sk_keyword <> - 1 THEN
                dgk.keyword_name || '_' || LOWER(
                LEFT (dgk.match_type, 1))
            ELSE
                CAST(dga.ad_group_name AS varchar)
            END AS utm_term,
            CAST(dga.id_ad AS varchar) AS utm_content,
            fg.desktop_cost,
            fg.mobile_cost,
            fg.total_cost
        FROM
            marketing_costs.fact_google_daily_cost_attributions fg
        LEFT JOIN marketing_costs.dim_google_keyword dgk ON dgk.sk_keyword = fg.sk_keyword
        LEFT JOIN marketing_costs.dim_google_ad dga ON dga.sk_ad = fg.sk_ad
        LEFT JOIN marketing_costs.dim_google_campaign dgc ON dgc.sk_campaign = fg.sk_campaign
        LEFT JOIN marketing_costs.dim_google_video dgv ON dgv.sk_video = fg.sk_video
        LEFT JOIN datalake_raw.gsheets_taxonomy_ad_type_flags gtatf ON dga.ad_type = gtatf.ad_type
    WHERE
        dgk.is_test_campaign IS NOT TRUE
        AND dga.is_test_campaign IS NOT TRUE
        AND dgc.is_test_campaign IS NOT TRUE
        AND (gtatf.flag <> 'other'
            OR gtatf.flag IS NULL)
        AND SUBSTRING(COALESCE(dgk.campaign_name, dga.campaign_name, dgc.campaign_name, dgv.campaign_name), 1, 5) <> 'ZEBRA'),
    manual_google_costs AS (
        WITH t_prep AS (
            SELECT
                REPLACE(REPLACE(LOWER(f_remove_accentuation (account_name)), ' - ', '_'), ' ', '_') AS prep_account_name,
                campaign_name,
                TO_CHAR(CAST(g.date AS date), 'yyyyMMdd')::integer AS sk_date,
                CAST(REPLACE(desktop_cost, ',', '') AS numeric(12, 2)) AS desktop_cost,
                CAST(REPLACE(mobile_cost, ',', '') AS numeric(12, 2)) AS mobile_cost,
                CAST(REPLACE(tablet_cost, ',', '') AS numeric(12, 2)) AS tablet_cost
            FROM
                datalake_raw.gsheets_marketing_manual_costs_google g
)
            SELECT
                CASE WHEN prep_account_name = 'quintoandar_display_and_video' THEN
                    'quintoandar_dra'
                ELSE
                    prep_account_name
                END AS account_name,
                *
            FROM
                t_prep
)
            SELECT
                COALESCE(m.sk_date, g.sk_date) AS sk_date,
                CASE WHEN m.sk_date IS NOT NULL THEN
                    m.campaign_name
                ELSE
                    g.campaign_name
                END AS campaign_name,
                CASE WHEN m.sk_date IS NOT NULL THEN
                    m.account_name
                ELSE
                    g.account_name
                END AS account_name,
                CASE WHEN m.sk_date IS NOT NULL THEN
                    m.campaign_name
                ELSE
                    g.campaign_name
                END AS utm_campaign,
                CASE WHEN m.sk_date IS NULL THEN
                    g.utm_term
                END AS utm_term,
                CASE WHEN m.sk_date IS NULL THEN
                    g.utm_content
                END AS utm_content,
                CASE WHEN m.sk_date IS NOT NULL THEN
                    m.desktop_cost
                ELSE
                    g.desktop_cost
                END AS desktop_cost,
                CASE WHEN m.sk_date IS NOT NULL THEN
                    m.mobile_cost
                ELSE
                    g.mobile_cost
                END AS mobile_cost,
                g.report_type AS report_type,
                g.ad_type AS ad_type
            FROM
                t_google g
            FULL OUTER JOIN manual_google_costs m ON m.sk_date = g.sk_date
            AND m.account_name = g.account_name
            AND m.campaign_name = g.campaign_name
    WHERE
        COALESCE(m.sk_date, g.sk_date) >= 20180101
),
formatted_historic_affiliates_national_campaigns_cost AS (
    SELECT
        CAST(TO_CHAR(TO_DATE(cost_date, 'MM/DD/YYYY'), 'YYYYMMDD') AS integer) AS sk_cost_date,
        campaign,
        CAST(REPLACE(
                COST, ',', '') AS numeric(16, 4)) AS
        COST,
        city_group
    FROM
        datalake_raw.gsheets_affiliates_historic_national_costs
),
fb_hist_list_affiliates AS (
    SELECT DISTINCT
        TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer AS sk_date,
        df.campaign_name,
        hist.campaign
    FROM
        marketing_costs.fact_facebook_daily_cost_attributions ff
        JOIN marketing_costs.dim_facebook_ad df ON ff.sk_ad = df.sk_ad
            AND df.is_test_campaign IS NOT TRUE
        JOIN formatted_historic_affiliates_national_campaigns_cost hist ON LOWER(df.campaign_name) = LOWER(hist.campaign)
            AND TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer = hist.sk_cost_date
    WHERE
        TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer >= 20190101
        AND SUBSTRING(df.campaign_name, 1, 5) <> 'ZEBRA'
),
facebook_info AS (
    SELECT DISTINCT
        campaign_name,
        account_name
    FROM
        marketing_costs.dim_facebook_ad
),
gg_hist_list_affiliates AS (
    SELECT DISTINCT
        gcc.sk_date,
        gcc.campaign_name,
        hist.campaign
    FROM
        google_consolidated_cost gcc
        JOIN formatted_historic_affiliates_national_campaigns_cost hist ON LOWER(gcc.campaign_name) = LOWER(hist.campaign)
            AND gcc.sk_date = hist.sk_cost_date
    WHERE
        gcc.sk_date >= 20190101
),
google_info AS (
    SELECT DISTINCT
        campaign_name,
        account_name
    FROM
        google_consolidated_cost
    WHERE
        sk_date >= 20190101
),
-- Affiates Costs
affiliates_cost AS (
    SELECT
        hist.sk_cost_date,
        'facebook' AS origin,
        'fact_facebook_daily_cost_attributions' AS fact_cost,
        hist.campaign,
        hist.city_group AS campaign_city,
        df.account_name,
        LOWER(hist.campaign) AS campaign_name_l,
        LOWER(df.account_name) AS account_name_l,
    hist.campaign AS utm_campaign,
    NULL::varchar AS utm_term,
    NULL::varchar AS utm_content,
    hist.cost AS desktop_cost,
    NULL::numeric(16,
        4) AS mobile_cost,
    NULL::numeric(16,
        4) AS other_cost,
NULL::numeric(16,
    4) AS total_cost
FROM
    formatted_historic_affiliates_national_campaigns_cost hist
    -- Filter in affiliate_costs of national-campaigns with manual-historic costs
    JOIN fb_hist_list_affiliates hl ON hl.sk_date = hist.sk_cost_date
        AND hl.campaign = hist.campaign
    LEFT JOIN facebook_info df ON LOWER(df.campaign_name) = LOWER(hist.campaign)
UNION ALL
SELECT
    hist.sk_cost_date,
    'google' AS origin,
    'fact_google_daily_cost_attributions' AS fact_cost,
    hist.campaign,
    hist.city_group AS campaign_city,
    gi.account_name,
    LOWER(hist.campaign) AS campaign_name_l,
    LOWER(gi.account_name) AS account_name_l,
    hist.campaign AS utm_campaign,
    NULL::varchar AS utm_term,
    NULL::varchar AS utm_content,
    hist.cost AS desktop_cost,
    NULL::numeric(16,
        4) AS mobile_cost,
    NULL::numeric(16,
        4) AS other_cost,
    NULL::numeric(16,
        4) AS total_cost
FROM
    formatted_historic_affiliates_national_campaigns_cost hist
    -- Filter in affiliate_costs of national-campaigns with manual-historic costs
    JOIN gg_hist_list_affiliates hl ON hl.sk_date = hist.sk_cost_date
        AND hl.campaign = hist.campaign
    LEFT JOIN google_info gi ON LOWER(gi.campaign_name) = LOWER(hist.campaign)
),
-- Share costs FROM campaigns for all sources
campaigns_full AS (
    WITH sources_to_be_shared AS (
        -- Get Sources Costs and Rule ID FROM campaign name
        WITH sources AS (
            -- FACEBOOK
            SELECT
                TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer AS sk_date,
                'facebook'::varchar AS origin,
                'fact_facebook_daily_cost_attributions'::varchar AS fact_cost,
                df.campaign_name,
                LOWER(SPLIT_PART(df.campaign_name, '.', 4)) AS campaign_city,
                df.account_name,
                LOWER(df.campaign_name) AS campaign_name_l,
                LOWER(df.account_name) AS account_name_l,
                df.campaign_name AS utm_campaign,
                df.adset_name AS utm_term,
                df.ad_name AS utm_content,
                ff.spend_desktop AS desktop_cost,
                ff.spend_mobile AS mobile_cost,
                ff.spend_other AS other_cost,
                NULL::numeric(16,
                    4) AS total_cost,
                NULL AS report_type,
                NULL AS ad_type
            FROM
                marketing_costs.fact_facebook_daily_cost_attributions ff
                JOIN marketing_costs.dim_facebook_ad df ON ff.sk_ad = df.sk_ad
                    AND df.is_test_campaign IS NOT TRUE
            LEFT JOIN fb_hist_list_affiliates hl ON hl.sk_date = TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer
                AND df.campaign_name = hl.campaign_name
        WHERE
            TO_CHAR(ff.dt_start::date, 'yyyyMMdd')::integer >= 20180101
            AND SUBSTRING(df.campaign_name, 1, 5) <> 'ZEBRA'
            -- Filter out affiliate_costs of national-campaigns with manual-historic costs
            AND hl.sk_date IS NULL
            -- GOOGLE
        UNION
        SELECT
            gcc.sk_date,
            'google'::varchar AS origin,
            'fact_google_daily_cost_attributions'::varchar AS fact_cost,
            gcc.campaign_name,
            LOWER(
                CASE WHEN SPLIT_PART(gcc.campaign_name, '.', 2) ~ '^[0-9]+$' THEN
                    SPLIT_PART(gcc.campaign_name, '.', 3)
                ELSE
                    SPLIT_PART(gcc.campaign_name, '.', 2)
                END) AS campaign_city,
            gcc.account_name,
            LOWER(gcc.campaign_name) AS campaign_name_l,
            LOWER(gcc.account_name) AS account_name_l,
            CAST(gcc.utm_campaign AS varchar) AS utm_campaign,
            CAST(gcc.utm_term AS varchar) AS utm_term,
            CAST(gcc.utm_content AS varchar) AS utm_content,
            gcc.desktop_cost AS desktop_cost,
            gcc.mobile_cost AS mobile_cost,
            NULL::numeric(16,
                4) AS other_cost,
            NULL::numeric(16,
                4) AS total_cost,
            gcc.report_type,
            gcc.ad_type
        FROM
            google_consolidated_cost gcc
        LEFT JOIN gg_hist_list_affiliates hl ON hl.sk_date = gcc.sk_date
            AND gcc.campaign_name = hl.campaign_name
    WHERE
        -- Filter out affiliate_costs of national-campaigns with manual-historic costs
        hl.sk_date IS NULL
        -- FACEBOOK & GOOGLE AFFILIATES' HISTORIC COST
    UNION
    SELECT
        *,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        affiliates_cost
        --TROVIT
    UNION
    SELECT
        ftc.sk_date,
        'trovit'::varchar AS origin,
        'fact_trovit_daily_cost_attributions'::varchar AS fact_cost,
        dtc.campaign_name,
        NULL::varchar AS campaign_city,
        account_name,
        LOWER(dtc.campaign_name) AS campaign_name_l,
        NULL::varchar(512) AS account_name_l,
        dtc.campaign_name AS utm_campaign,
        NULL::varchar(512) AS utm_term,
        NULL::varchar(512) AS utm_content,
        ftc.desktop_cost AS desktop_cost,
        ftc.mobile_cost AS mobile_cost,
        NULL::numeric(16,
            4) AS other_cost,
        NULL::numeric(16,
            4) AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        marketing_costs.fact_trovit_daily_cost_attributions ftc
        LEFT JOIN marketing_costs.dim_trovit_campaign dtc ON ftc.sk_trovit_campaign = dtc.sk_trovit_campaign
    WHERE
        ftc.sk_date >= 20180101
        -- MITULA
    UNION
    SELECT
        fm.sk_date,
        'mitula'::varchar AS origin,
        'fact_mitula_daily_cost_attributions'::varchar AS fact_cost,
        campaign_name,
        NULL::varchar AS campaign_city,
        account_name,
        LOWER(campaign_name) AS campaign_name_l,
        NULL::varchar(512) AS account_name_l,
        campaign_name AS utm_campaign,
        NULL::varchar(512) AS utm_term,
        NULL::varchar(512) AS utm_content,
        fm.desktop_cost AS desktop_cost,
        fm.mobile_cost AS mobile_cost,
        NULL::numeric(16,
            4) AS other_cost,
        NULL::numeric(16,
            4) AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        marketing_costs.fact_mitula_daily_cost_attributions fm
        JOIN marketing_costs.dim_mitula_campaign dm ON fm.sk_mitula_campaign = dm.sk_mitula_campaign
    WHERE
        fm.sk_date >= 20180101
        -- CRITEO
    UNION
    SELECT
        fct.sk_date,
        'criteo'::varchar AS origin,
        'fact_criteo_daily_cost_attributions'::varchar AS fact_cost,
        dct.campaign_name,
        NULL AS campaign_city,
        advertiser_name AS account_name,
        LOWER(dct.campaign_name) AS campaign_name_l,
        LOWER(advertiser_name) AS account_name_l,
        dct.campaign_name AS utm_campaign,
        NULL::varchar(512) AS utm_term,
        NULL::varchar(512) AS utm_content,
        NULL::numeric(16,
            4) AS desktop_cost,
        NULL::numeric(16,
            4) AS mobile_cost,
        NULL::numeric(16,
            4) AS other_cost,
        fct.cost AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        marketing_costs.fact_criteo_daily_cost_attributions fct
        LEFT JOIN marketing_costs.dim_criteo_campaign dct ON fct.sk_criteo_campaign = dct.sk_criteo_campaign
    WHERE
        fct.sk_date >= 20180101
        -- RTB
    UNION
    SELECT
        frt.sk_date,
        'rtb'::VARCHAR AS origin,
        'fact_rtb_daily_cost_attributions'::VARCHAR AS fact_cost,
        drt.campaign_name,
        NULL::VARCHAR AS campaign_city,
        drt.account_name AS account_name,
        lower(drt.campaign_name) AS campaign_name_l,
        lower(drt.account_name) AS account_name_l,
        drt.campaign_name AS utm_campaign,
        NULL::VARCHAR(512) AS utm_term,
        NULL::VARCHAR(512) AS utm_content,
        NULL::NUMERIC(16,4) AS desktop_cost,
        NULL::NUMERIC(16,4) AS mobile_cost,
        NULL::NUMERIC(16,4) AS other_cost,
        sum(cost) AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM marketing_costs.fact_rtb_daily_cost_attributions frt
        LEFT JOIN marketing_costs.dim_rtb_campaign drt
        ON frt.sk_sub_campaign = drt.sk_sub_campaign
        AND frt.sk_date = drt.sk_date
    WHERE frt.sk_date >= 20180101
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,16,17
    -- TWITTER
    UNION
    SELECT
        ftw.sk_date,
        'twitter'::varchar AS origin,
        'fact_twitter_daily_cost_attributions'::varchar AS fact_cost,
        dtwc.campaign_name,
        NULL AS campaign_city,
        dtwc.account_name AS account_name,
        LOWER(dtwc.campaign_name) AS campaign_name_l,
        LOWER(dtwc.account_name) AS account_name_l,
        REPLACE(dtwc.campaign_name, ' ', '_') AS utm_campaign,
        UPPER(dtag.ad_group_name) AS utm_term,
        NULL::varchar(512) AS utm_content,
        SUM(desktop_cost) AS desktop_cost,
        SUM(mobile_cost) AS mobile_cost,
        SUM(other_cost) AS other_cost,
        NULL::numeric(16,
            4) AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        marketing.fact_twitter_daily_cost_attributions ftw
        JOIN marketing.dim_twitter_campaign dtwc ON ftw.sk_campaign = dtwc.sk_campaign
        JOIN marketing.dim_twitter_ad_group dtag ON ftw.sk_ad_group = dtag.sk_ad_group
    WHERE
        ftw.sk_date >= 20180101
    GROUP BY
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11
        -- LINKEDIN
    UNION
    SELECT
        fli.sk_date,
        'linkedin'::varchar AS origin,
        'fact_linkedin_daily_cost_attributions'::varchar AS fact_cost,
        dlc.campaign_name,
        NULL AS campaign_city,
        dlcc.account_name AS account_name,
        LOWER(dlc.campaign_name) AS campaign_name_l,
        LOWER(dlcc.account_name) AS account_name_l,
        dlc.campaign_name AS utm_campaign,
        NULL::varchar AS utm_term,
        NULL::varchar AS utm_content,
        NULL::numeric(16,
            4) AS desktop_cost,
        NULL::numeric(16,
            4) AS mobile_cost,
        NULL::numeric(16,
            4) AS other_cost,
        SUM(total_cost) AS total_cost,
        NULL AS report_type,
        NULL AS ad_type
    FROM
        marketing_costs.fact_linkedin_daily_cost_attributions fli
        JOIN marketing_costs.dim_linkedin_campaign dlc ON dlc.sk_campaign = fli.sk_campaign
        JOIN marketing_costs.dim_linkedin_campaign_group dlcc ON dlcc.sk_campaign_group = fli.sk_campaign_group
    GROUP BY
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11
)
    SELECT
        NULLIF (REGEXP_SUBSTR (campaign_name, '^([[:alpha:]]\\d{3}[[:alpha:]])'), '')::varchar AS rule_id,
        *
    FROM
        sources),
    shared_costs AS (
        SELECT
            sh.sk_date,
            origin,
            fact_cost,
            campaign_name,
            COALESCE(r.city_group, sh.campaign_city) AS campaign_city,
            account_name,
            campaign_name_l,
            account_name_l,
            utm_campaign,
            utm_term,
            utm_content,
            -- Desktop Cost Shared
            sh.desktop_cost * COALESCE(r.share, 1) AS desktop_cost,
            -- Mobile Cost Shared
            sh.mobile_cost * COALESCE(r.share, 1) AS mobile_cost,
            -- Other Cost Shared
            sh.other_cost * COALESCE(r.share, 1) AS other_cost,
            -- Total Cost Shared
            sh.total_cost * COALESCE(r.share, 1) AS total_cost,
            sh.report_type,
            sh.ad_type
        FROM
            sources_to_be_shared sh
        LEFT JOIN staging.sharing_rules_marketing_daily_costs r ON sh.sk_date = r.sk_date
            AND sh.rule_id = r.rule_id
)
        SELECT
            sk_date,
            origin,
            fact_cost,
            campaign_name,
            campaign_city,
            account_name,
            campaign_name_l,
            CASE WHEN campaign_name_l LIKE '%calc%' THEN
                'Calculator'
            ELSE
                'Other'
            END AS campaign_origin_aquisition,
            account_name_l,
            utm_campaign,
            utm_term,
            utm_content,
            desktop_cost,
            mobile_cost,
            other_cost,
            total_cost,
            report_type,
            ad_type
        FROM
            shared_costs
),
taxonomy_by_platform AS (
    SELECT
        txmc.*,
        s.mkt_platform,
        CAST(COALESCE(nullif (TRIM(SPLIT_PART(txmc.cost_factor, ';', s.i)), ''), '1.0') AS float) AS fator_custo
    FROM
        datalake_raw.gsheets_taxonomy_mkt_cost_new_test txmc
    CROSS JOIN (
        SELECT
            1::integer,
            'Desktop'::varchar
    UNION ALL
    SELECT
        2::integer,
        'Mobile'::varchar
    UNION ALL
    SELECT
        3::integer,
        'Other'::varchar) AS s (i,
        mkt_platform)
),
cost_taxonomy AS (
    WITH manual_shared_costs AS (
        SELECT
            NULL::varchar AS origin,
            TO_CHAR(NULLIF (dt, '')::date, 'yyyyMMdd')::integer AS sk_date,
            NULLIF (account_name, '') AS account_name,
            NULLIF (campaign_name, '') AS campaign_name,
            NULLIF (city_group, '') AS cost_city_group,
            NULL AS city_campaign_mapping_rule,
            NULL AS campaign_city_matched,
            CASE WHEN LOWER(NULLIF (campaign_name, ''))
            LIKE '%calc%' THEN
                'Calculator'
            ELSE
                'Other'
            END::varchar campaign_origin_aquisition,
            'Inbound'::varchar AS mkt_category,
            'Self-Service'::varchar AS mkt_flow,
            'Full Self-Service'::varchar AS mkt_completion,
            NULLIF (mkt_origin, '') AS mkt_origin,
            NULLIF (mkt_channel, '') AS mkt_channel,
            NULLIF (mkt_medium, '') AS mkt_medium,
            NULLIF (mkt_source, '') AS mkt_source,
            NULLIF (s.mkt_platform, '') AS mkt_platform,
            CASE WHEN (COALESCE(CAST(nullif (cost_share_mobile, '') AS numeric(12, 2)), 0) + COALESCE(CAST(nullif (cost_share_desktop, '') AS numeric(12, 2)), 0) + COALESCE(CAST(nullif (cost_share_other, '') AS numeric(12, 2)), 0)) = 1 THEN
                CASE WHEN s.mkt_platform = 'Mobile' THEN
                    COALESCE(CAST(nullif (cost_share_mobile, '') AS numeric(12, 2)), 0)
                WHEN s.mkt_platform = 'Desktop' THEN
                    COALESCE(CAST(nullif (cost_share_desktop, '') AS numeric(12, 2)), 0)
                WHEN s.mkt_platform = 'Other' THEN
                    COALESCE(CAST(nullif (cost_share_other, '') AS numeric(12, 2)), 0)
                END
            ELSE
                CASE WHEN s.mkt_platform = 'Mobile' THEN
                    1::numeric(12, 2)
                ELSE
                    0::numeric(12, 2)
                END
            END AS fator_custo,
            NULLIF (campaign_name, '') AS utm_campaign,
            NULLIF (utm_term, '') AS utm_term,
            NULLIF (utm_content, '') AS utm_content,
            CAST(NULLIF (REPLACE(
                        COST, ',', ''), '') AS numeric(12, 2)) * fator_custo AS
            COST,
            NULLIF (side, '') AS side
        FROM
            datalake_raw.marketing_manual_shared_costs
        CROSS JOIN (
            SELECT
                1::integer,
                'Desktop'::varchar
        UNION ALL
        SELECT
            2::integer,
            'Mobile'::varchar
        UNION ALL
        SELECT
            3::integer,
            'Other'::varchar) AS s (i,
            mkt_platform)
    WHERE
        mkt_source <> 'Google'
        OR (mkt_source = 'Google' AND LOWER(SUBSTRING(campaign_name, 1, 3)) <> 'dsa')),
    name_convention_shared_costs AS (
        WITH city_group_share_rules AS (
            SELECT
                NULL AS origin,
                REPLACE(nullif (s.dt, ''), '-', '')::int AS sk_date,
                NULLIF (account_name, '') AS account_name,
                NULLIF (campaign_name, '') AS campaign_name,
                NULLIF (r.city_group, '') AS cost_city_group,
                NULL AS city_campaign_mapping_rule,
                NULL AS campaign_city_matched,
                CASE WHEN LOWER(NULLIF (campaign_name, ''))
                LIKE '%calc%' THEN
                    'Calculator'
                ELSE
                    'Other'
                END AS campaign_origin_aquisition,
                'Inbound' AS mkt_category,
                'Self-Service' AS mkt_flow,
                'Full Self-Service' AS mkt_completion,
                NULLIF (mkt_origin, '') AS mkt_origin,
                NULLIF (mkt_channel, '') AS mkt_channel,
                NULLIF (mkt_medium, '') AS mkt_medium,
                NULLIF (mkt_source, '') AS mkt_source,
                NULLIF (campaign_name, '') AS utm_campaign,
                NULLIF (utm_term, '') AS utm_term,
                NULLIF (utm_content, '') AS utm_content,
                CAST(NULLIF (REPLACE(
                            COST, ',', ''), '') AS numeric(16, 4)) * r.share AS
                COST,
                NULLIF (side, '') AS side,
                cost_share_desktop,
                cost_share_mobile,
                cost_share_other
            FROM
                datalake_raw.marketing_name_convention_shared_costs s
                INNER JOIN staging.sharing_rules_marketing_daily_costs r ON REPLACE(nullif (s.dt, ''), '-', '')::int = r.sk_date
                    AND s.rule_id = r.rule_id
                    AND s.side = r.funnel_side
)
                SELECT
                    origin,
                    sk_date,
                    account_name,
                    campaign_name,
                    cost_city_group,
                    city_campaign_mapping_rule,
                    campaign_city_matched,
                    campaign_origin_aquisition,
                    mkt_category,
                    mkt_flow,
                    mkt_completion,
                    mkt_origin,
                    mkt_channel,
                    mkt_medium,
                    mkt_source,
                    s.mkt_platform,
                    /*  Cost factor  if share costs FROM platforms (mobile, desktop, other) sums to 1, then it means that the sharing is defined to
                     *   platforms and needs to be used to share costs, otherwise, all sharing will attributed to Mobile platform.
                     */
                    CASE WHEN (COALESCE(CAST(nullif (cost_share_mobile, '') AS numeric(12, 2)), 0) + COALESCE(CAST(nullif (cost_share_desktop, '') AS numeric(12, 2)), 0) + COALESCE(CAST(nullif (cost_share_other, '') AS numeric(12, 2)), 0)) = 1 THEN
                        CASE WHEN s.mkt_platform = 'Mobile' THEN
                            COALESCE(CAST(nullif (cost_share_mobile, '') AS numeric(12, 2)), 0)
                        WHEN s.mkt_platform = 'Desktop' THEN
                            COALESCE(CAST(nullif (cost_share_desktop, '') AS numeric(12, 2)), 0)
                        WHEN s.mkt_platform = 'Other' THEN
                            COALESCE(CAST(nullif (cost_share_other, '') AS numeric(12, 2)), 0)
                        END
                    ELSE
                        CASE WHEN s.mkt_platform = 'Mobile' THEN
                            1
                        ELSE
                            0
                        END
                    END AS fator_custo,
                    utm_campaign,
                    utm_term,
                    utm_content,
                    CAST(NULLIF (REPLACE(
                                COST, ',', ''), '') AS numeric(16, 4)) * fator_custo AS
                    COST,
                    NULLIF (side, '') AS side
                FROM
                    city_group_share_rules sr
            CROSS JOIN (
                SELECT
                    1,
                    'Desktop'
            UNION ALL
            SELECT
                2,
                'Mobile'
            UNION ALL
            SELECT
                3,
                'Other') AS s (i,
                mkt_platform))
        SELECT
            cf.origin,
            cf.sk_date,
            cf.account_name,
            cf.campaign_name,
            -- city via manual mapping
            mccc.city_group AS cost_city_group,
            -- city via campaign_name full name written
            CASE WHEN campaign_name_l IN ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre', 'Santos', 'Recife', 'Salvador') THEN
                campaign_name_l
            WHEN cf.campaign_name_l LIKE '%campinas%' THEN
                'Campinas'
            WHEN cf.campaign_name_l LIKE '%s_o_paulo%'
                OR cf.campaign_name_l LIKE '%sp detailed%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE 'sp %' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%all cities%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%rmsp%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%guarulhos%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%abc%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%barueri%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%osasco%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%jundia%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%santo_andr%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%s_o_bernardo%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%s_o_caetano%' THEN
                'RMSP'
            WHEN cf.campaign_name_l LIKE '%rio%de%janeiro%' THEN
                'Rio de Janeiro'
            WHEN cf.campaign_name_l LIKE '%niter_i%' THEN
                'Rio de Janeiro'
            WHEN cf.campaign_name_l LIKE '%bh%'
                OR cf.campaign_name_l LIKE '%belo%h%' THEN
                'Belo Horizonte'
            WHEN cf.campaign_name_l LIKE '%minas_gerais%' THEN
                'Belo Horizonte'
            WHEN cf.campaign_name_l LIKE '%goi_nia%'
                OR cf.campaign_name_l LIKE '%goi_s%' THEN
                'Goiânia'
            WHEN cf.campaign_name_l LIKE '%bras_lia%'
                OR cf.campaign_name_l LIKE '%distrito_federal%' THEN
                'Brasília'
            WHEN cf.campaign_name_l LIKE '%porto%alegre%' THEN
                'Porto Alegre'
            WHEN cf.campaign_name_l LIKE '%curitiba%'
                OR cf.campaign_name_l LIKE '%paran_%' THEN
                'Curitiba'
            WHEN cf.campaign_name_l LIKE '%florian_polis%'
                OR cf.campaign_name_l LIKE '%santa_catarina%' THEN
                'Florianópolis'
            WHEN cf.campaign_name_l LIKE '%poa%' THEN
                'Porto Alegre'
            WHEN cf.campaign_name_l LIKE '%ctba%' THEN
                'Curitiba'
            WHEN cf.campaign_name_l LIKE '%fln%' THEN
                'Florianópolis'
            WHEN cf.campaign_name_l LIKE '%cps%' THEN
                'Campinas'
            WHEN cf.campaign_name_l LIKE '%bsb%' THEN
                'Brasília'
            WHEN cf.campaign_name_l LIKE '%rj%' THEN
                'Rio de Janeiro'
            WHEN cf.campaign_name_l LIKE '%santos%' THEN
                'Santos'
            WHEN cf.campaign_name_l LIKE '%recife%' THEN
                'Recife'
            WHEN cf.campaign_name_l LIKE '%salvador%' THEN
                'Salvador'
            END AS city_campaign_mapping_rule,
            -- city via campaign_name name convention
            CASE WHEN campaign_city IN ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre', 'Santos', 'Recife', 'Salvador') THEN
                campaign_city
            WHEN campaign_city = 'campinas' THEN
                'Campinas'
            WHEN campaign_city IN ('sp', 'jui', 'santo_andre', 'guarulhos', 'osasco', 'sao_caetano', 'sao_bernardo', 'barueri', 'rmsp') THEN
                'RMSP'
            WHEN campaign_city IN ('rj', 'niteroi', 'rio_de_janeiro', 'rio') THEN
                'Rio de Janeiro'
            WHEN campaign_city IN ('bh', 'belo_horizonte') THEN
                'Belo Horizonte'
            WHEN campaign_city = 'goiania' THEN
                'Goiânia'
            WHEN campaign_city IN ('poa', 'porto_alegre') THEN
                'Porto Alegre'
            WHEN campaign_city = 'curitiba' THEN
                'Curitiba'
            WHEN campaign_city IN ('fln', 'florianopolis') THEN
                'Florianópolis'
            WHEN campaign_city IN ('bsb', 'brasilia') THEN
                'Brasília'
            WHEN campaign_city = 'santos' THEN
                'Santos'
            WHEN campaign_city = 'recife' THEN
                'Recife'
            WHEN campaign_city = 'salvador' THEN
                'Salvador'
            END AS campaign_city_matched,
            COALESCE(tp.campaign_origin_aquisition, 'Not Mapped') AS campaign_origin_aquisition,
            COALESCE(tp.mkt_category, 'Not Mapped') AS mkt_category,
            COALESCE(tp.mkt_flow, 'Not Mapped') AS mkt_flow,
            COALESCE(tp.mkt_completion, 'Not Mapped') AS mkt_completion,
            COALESCE(tp.mkt_origin, 'Not Mapped') AS mkt_origin,
            COALESCE(tp.mkt_channel, 'Not Mapped') AS mkt_channel,
            COALESCE(tp.mkt_medium, 'Not Mapped') AS mkt_medium,
            COALESCE(tp.mkt_source, 'Not Mapped') AS mkt_source,
            COALESCE(tp.mkt_platform, 'Not Mapped') AS mkt_platform,
            tp.fator_custo,
            cf.utm_campaign,
            cf.utm_term,
            cf.utm_content,
            CASE WHEN total_cost IS NULL THEN
                CASE WHEN tp.mkt_platform = 'Mobile' THEN
                    mobile_cost
                WHEN tp.mkt_platform = 'Desktop' THEN
                    desktop_cost
                WHEN tp.mkt_platform = 'Other' THEN
                    other_cost
                WHEN tp.mkt_platform IS NULL
                    AND total_cost IS NULL THEN
                    COALESCE(mobile_cost, 0) + COALESCE(desktop_cost, 0) + COALESCE(other_cost, 0)
                END
            ELSE
                total_cost
            END * CAST(COALESCE(tp.fator_custo, '1') AS numeric(3, 2)) AS
            COST,
            -- Funnel side is extracted FROM taxonomy
            COALESCE(tp.side, 'Not Mapped') AS side
        FROM
            campaigns_full cf
        LEFT JOIN datalake_raw.gsheets_marketing_cost_campaign_city AS mccc ON LOWER(mccc.campaign_name) = cf.campaign_name_l
        LEFT JOIN taxonomy_by_platform AS tp ON COALESCE(cf.account_name, '') = COALESCE(tp.account_name, '')
            AND COALESCE(cf.report_type, '') = COALESCE(tp.report_type, '')
            AND COALESCE(cf.ad_type, '') = COALESCE(tp.ad_type, '')
            AND cf.fact_cost = tp.fact_cost
            AND cf.origin = tp.origin
            AND cf.campaign_origin_aquisition = tp.campaign_origin_aquisition
            -- Append manual costs
        UNION
        SELECT
            *
        FROM
            manual_shared_costs
    WHERE
        COST > 0
    UNION
    -- Append Name Convetion costs
    SELECT
        *
    FROM
        name_convention_shared_costs
    WHERE
        COST > 0
),
kenshoo_raw AS (
    SELECT
        ct.sk_date,
        ct.side AS funnel_side,
        tp.account_name AS account_name,
        NULL::varchar(256) AS campaign_name,
        cost_city_group,
        city_campaign_mapping_rule,
        campaign_city_matched,
        tp.mkt_category,
        tp.mkt_flow,
        tp.mkt_completion,
        tp.mkt_origin,
        tp.mkt_channel,
        tp.mkt_medium,
        tp.mkt_source,
        tp.mkt_platform,
        NULL::varchar(256) AS utm_campaign,
        NULL::varchar(256) AS utm_term,
        NULL::varchar(256) AS utm_content,
        (ct.cost * CAST(k.rate AS float) * tp.fator_custo)::numeric(12, 4) AS
        COST
    FROM
        cost_taxonomy ct
        JOIN datalake_raw.gsheets_marketing_kenshoo_configuration k ON ct.mkt_source = k.mkt_source
            AND ct.mkt_medium = k.mkt_medium
            AND ct.sk_date BETWEEN CAST(TO_CHAR(TO_DATE(k.date_FROM, 'MM/DD/YYYY'), 'YYYYMMDD') AS integer)
            AND CAST(TO_CHAR(TO_DATE(k.date_until, 'MM/DD/YYYY'), 'YYYYMMDD') AS integer)
        LEFT JOIN taxonomy_by_platform AS tp ON tp.origin = 'kenshoo'
            AND tp.side = ct.side
            AND tp.campaign_origin_aquisition = ct.campaign_origin_aquisition
),
kenshoo AS (
    SELECT
        sk_date,
        funnel_side,
        account_name,
        campaign_name,
        cost_city_group,
        city_campaign_mapping_rule,
        campaign_city_matched,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_term,
        utm_content,
        SUM(
            COST) AS
        COST
    FROM
        kenshoo_raw
GROUP BY
    sk_date,
    funnel_side,
    account_name,
    campaign_name,
    cost_city_group,
    city_campaign_mapping_rule,
    campaign_city_matched,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    utm_campaign,
    utm_term,
    utm_content
),
final_costs AS (
    SELECT
        sk_date,
        side AS funnel_side,
        account_name::varchar(512),
        campaign_name,
        cost_city_group,
        city_campaign_mapping_rule,
        campaign_city_matched,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_term,
        utm_content,
        COST::numeric(16,
            4)
    FROM
        cost_taxonomy
    UNION ALL
    SELECT
        sk_date,
        funnel_side,
        account_name::varchar(512),
        campaign_name,
        cost_city_group,
        city_campaign_mapping_rule,
        campaign_city_matched,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_platform,
        utm_campaign,
        utm_term,
        utm_content,
        COST::numeric(16,
            4)
    FROM
        kenshoo
)
SELECT
    sk_date,
    funnel_side,
    account_name,
    campaign_name,
    -- consolidating final city_group
    COALESCE(cost_city_group, city_campaign_mapping_rule, campaign_city_matched, 'Not Mapped') AS city_group_final,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    utm_campaign,
    utm_term,
    utm_content,
    COST,
    getdate () AS ts_load
FROM
    final_costs
WHERE
    mkt_source NOT IN ('Facebook', 'Google')
    OR (mkt_source = 'Google'
        AND sk_date > 20210116)
    OR (mkt_source = 'Facebook'
        AND sk_date > 20201210)
UNION ALL
SELECT
    *
FROM
    marketing_costs.fact_marketing_daily_costs_old_facebook
UNION ALL
SELECT
    *
FROM
    marketing_costs.fact_marketing_daily_costs_old_google
