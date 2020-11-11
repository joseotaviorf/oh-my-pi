/*
*   Description:
*       These CTEs collect information from several marketing campaign source tables and share the costs between city groups,
*       funnel side (e.g., demand, supply) and platform (e.g., mobile, Desktop, other) grouping by date.
*       The rules to share costs between city groups, funnel side and platform depends on marketing source and are
*       defined in each specific CTE.
*/
-- Google daily costs (Manual and Fact)
with google_consolidated_cost as (
    with t_google as (
        select
            fg.sk_date,
            coalesce(dgk.campaign_name, dga.campaign_name, dgc.campaign_name) as campaign_name,
            coalesce(dgk.account_name, dga.account_name, dgc.account_name) as account_name,
            case when fg.sk_keyword <> -1 then
                dgk.keyword_name || '_' || lower(left(dgk.match_type, 1))
                else cast(dga.adgroup_name as varchar) end
                as utm_term,
            cast(dga.ad_id as varchar) as utm_content,
            fg.desktop_cost,
            fg.mobile_cost
        from marketing.fact_google_daily_cost_attributions fg
        left join marketing.dim_google_keyword dgk
            on dgk.sk_keyword = fg.sk_keyword
        left join marketing.dim_google_ad dga
            on dga.sk_ad = fg.sk_ad
        left join marketing.dim_google_campaign dgc
            on dgc.sk_campaign = fg.sk_campaign
        where dgk.is_test_campaign is not true
          and dga.is_test_campaign is not true
          and dgc.is_test_campaign is not true
    ),
    manual_google_costs as (
        with t_prep as (
            select
                replace(replace(lower(f_remove_accentuation(account_name)), ' - ', '_'), ' ', '_') as prep_account_name,
                campaign_name,
                to_char(cast(g.date as date), 'yyyyMMdd')::integer as sk_date,
                cast(replace(desktop_cost, ',', '') as numeric(12,2)) as desktop_cost,
                cast(replace(mobile_cost, ',', '') as numeric(12,2)) as mobile_cost,
                cast(replace(tablet_cost, ',', '') as numeric(12,2)) as tablet_cost
            from datalake_raw.gsheets_marketing_manual_costs_google g
        )
        select
            case when prep_account_name = 'quintoandar_display_and_video' then 'quintoandar_dra'
                else prep_account_name end as account_name,
            *
            from t_prep
    )
    select
        coalesce(m.sk_date, g.sk_date) as sk_date,
        case when m.sk_date is not null then m.campaign_name
            else g.campaign_name end
            as campaign_name,
        case when m.sk_date is not null then m.account_name
            else g.account_name end
            as account_name,
        case when m.sk_date is not null then m.campaign_name
            else g.campaign_name end
            as utm_campaign,
        case when m.sk_date is null then g.utm_term end
            as utm_term,
        case when m.sk_date is null then g.utm_content end
            as utm_content,
        case when m.sk_date is not null then m.desktop_cost
            else g.desktop_cost end
            as desktop_cost,
        case when m.sk_date is not null then m.mobile_cost
            else g.mobile_cost end
            as mobile_cost
    from t_google g
    full outer join manual_google_costs m
        on m.sk_date = g.sk_date
        and m.account_name = g.account_name
        and m.campaign_name = g.campaign_name
    where coalesce(m.sk_date, g.sk_date) >= 20180101
),
formatted_historic_affiliates_national_campaigns_cost as (
    select
       cast(to_char(to_date(cost_date, 'MM/DD/YYYY'), 'YYYYMMDD') as integer) as sk_cost_date,
       campaign,
       cast(replace(cost, ',', '') as numeric(16,4)) as cost,
       city_group
    from
        datalake_raw.gsheets_affiliates_historic_national_costs
),
fb_hist_list_affiliates as (
    select
        distinct
            ff.sk_date,
            df.campaign_name,
            hist.campaign
    from marketing.fact_facebook_daily_cost_attributions ff
    join marketing.dim_facebook_ad df
        on ff.sk_ad = df.sk_ad and df.is_test_campaign is not true
    join formatted_historic_affiliates_national_campaigns_cost hist
        on lower(df.campaign_name) = lower(hist.campaign)
        and ff.sk_date = hist.sk_cost_date
    where ff.sk_date >= 20190101
),
facebook_info as (
    select
        distinct
            campaign_name,
            account_name
    from marketing.dim_facebook_ad
),
gg_hist_list_affiliates as (
    select
        distinct
            gcc.sk_date,
            gcc.campaign_name,
            hist.campaign
    from google_consolidated_cost gcc
    join formatted_historic_affiliates_national_campaigns_cost hist
        on lower(gcc.campaign_name) = lower(hist.campaign)
        and gcc.sk_date = hist.sk_cost_date
    where gcc.sk_date >= 20190101
),
google_info as (
    select
        distinct
            campaign_name,
            account_name
    from google_consolidated_cost
    where sk_date >= 20190101
),
-- Affiates Costs
affiliates_cost as (
    select
        hist.sk_cost_date,
        'facebook' as origin,
        'fact_facebook_daily_cost_attributions' as fact_cost,
        hist.campaign,
        hist.city_group as campaign_city,
        df.account_name,
        lower(hist.campaign) as campaign_name_l,
        lower(df.account_name) as account_name_l,
        hist.campaign as utm_campaign,
        null::varchar as utm_term,
        null::varchar as utm_content,
        hist.cost as desktop_cost,
        null::numeric(16,4) as mobile_cost,
        null::numeric(16,4) as other_cost,
        null::numeric(16,4) as total_cost
    from formatted_historic_affiliates_national_campaigns_cost hist
    -- Filter in affiliate_costs of national-campaigns with manual-historic costs
    join fb_hist_list_affiliates hl
        on hl.sk_date = hist.sk_cost_date
        and hl.campaign = hist.campaign
    left join facebook_info df
        on lower(df.campaign_name) = lower(hist.campaign)
    UNION ALL
    select
        hist.sk_cost_date,
        'google' as origin,
        'fact_google_daily_cost_attributions' as fact_cost,
        hist.campaign,
        hist.city_group as campaign_city,
        gi.account_name,
        lower(hist.campaign) as campaign_name_l,
        lower(gi.account_name) as account_name_l,
        hist.campaign as utm_campaign,
        null::varchar as utm_term,
        null::varchar as utm_content,
        hist.cost as desktop_cost,
        null::numeric(16,4) as mobile_cost,
        null::numeric(16,4) as other_cost,
        null::numeric(16,4) as total_cost
    from formatted_historic_affiliates_national_campaigns_cost hist
    -- Filter in affiliate_costs of national-campaigns with manual-historic costs
    join gg_hist_list_affiliates hl
        on hl.sk_date = hist.sk_cost_date
        and hl.campaign = hist.campaign
    left join google_info gi
        on lower(gi.campaign_name) = lower(hist.campaign)
),
-- Share costs from campaigns for all sources
campaigns_full as (
  WITH sources_to_be_shared AS (
      -- Get Sources Costs and Rule ID from campaign name
      WITH sources AS (
        -- FACEBOOK
            select
                ff.sk_date,
                'facebook'::varchar  as origin,
                'fact_facebook_daily_cost_attributions'::varchar as fact_cost,
                df.campaign_name,
                lower(SPLIT_PART(df.campaign_name, '.', 4)) as campaign_city,
                df.account_name,
                lower(df.campaign_name) as campaign_name_l,
                lower(df.account_name) as account_name_l,
                df.campaign_name as utm_campaign,
                df.adset_name as utm_term,
                df.ad_name as utm_content,
                ff.desktop_spend as desktop_cost,
                ff.mobile_spend as mobile_cost,
                ff.other_spend as other_cost,
                null::numeric(16,4) as total_cost
            from marketing.fact_facebook_daily_cost_attributions ff
                join marketing.dim_facebook_ad df
                    on ff.sk_ad = df.sk_ad and df.is_test_campaign is not true
                left join fb_hist_list_affiliates hl
                    on hl.sk_date = ff.sk_date
                    and df.campaign_name = hl.campaign_name
            where ff.sk_date >= 20180101
            -- Filter out affiliate_costs of national-campaigns with manual-historic costs
            and hl.sk_date is null
        -- GOOGLE
        UNION
            select
            gcc.sk_date,
            'google'::varchar as origin,
            'fact_google_daily_cost_attributions'::varchar as fact_cost,
            gcc.campaign_name,
            lower(case when SPLIT_PART(gcc.campaign_name, '.', 2) ~ '^[0-9]+$' then
                SPLIT_PART(gcc.campaign_name, '.', 3)
                else
                SPLIT_PART(gcc.campaign_name, '.', 2)
                end)
            as campaign_city,
            gcc.account_name,
            lower(gcc.campaign_name) as campaign_name_l,
            lower(gcc.account_name) as account_name_l,
            cast(gcc.utm_campaign as varchar) as utm_campaign,
            cast(gcc.utm_term as varchar) as utm_term,
            cast(gcc.utm_content as varchar) as utm_content,
            gcc.desktop_cost as desktop_cost,
            gcc.mobile_cost as mobile_cost,
            null::numeric(16,4) as other_cost,
            null::numeric(16,4) as total_cost
            from google_consolidated_cost gcc
            left join gg_hist_list_affiliates hl
                on hl.sk_date = gcc.sk_date
                and gcc.campaign_name = hl.campaign_name
            where
                -- Filter out affiliate_costs of national-campaigns with manual-historic costs
                hl.sk_date is null
        -- FACEBOOK & GOOGLE AFFILIATES' HISTORIC COST
        UNION
            select
                *
            from
                affiliates_cost
        --TROVIT
        UNION
            select
                ftc.sk_date,
                'trovit'::varchar as origin,
                'fact_trovit_daily_cost_attributions'::varchar as fact_cost,
                dtc.campaign_name,
                null::varchar as campaign_city,
                account_name,
                lower(dtc.campaign_name) as campaign_name_l,
                null::varchar(512) as account_name_l,
                dtc.campaign_name as utm_campaign,
                null::varchar(512) as utm_term,
                null::varchar(512) as utm_content,
                ftc.desktop_cost as desktop_cost,
                ftc.mobile_cost as mobile_cost,
                null::numeric(16,4) as other_cost,
                null::numeric(16,4) as total_cost
            from
                marketing.fact_trovit_daily_cost_attributions ftc
            left join
                marketing.dim_trovit_campaign dtc
                    on ftc.sk_trovit_campaign = dtc.sk_trovit_campaign
            where
                ftc.sk_date >= 20180101

        -- MITULA
        UNION
            select
                fm.sk_date,
                'mitula'::varchar as origin,
                'fact_mitula_daily_cost_attributions'::varchar as fact_cost,
                campaign_name,
                null::varchar as campaign_city,
                account_name,
                lower(campaign_name) as campaign_name_l,
                null::varchar(512) as account_name_l,
                campaign_name as utm_campaign,
                null::varchar(512) as utm_term,
                null::varchar(512) as utm_content,
                fm.desktop_cost as desktop_cost,
                fm.mobile_cost as mobile_cost,
                null::numeric(16,4) as other_cost,
                null::numeric(16,4) as total_cost
            from
                marketing.fact_mitula_daily_cost_attributions fm
            join marketing.dim_mitula_campaign dm
                on fm.sk_mitula_campaign = dm.sk_mitula_campaign
            where fm.sk_date >= 20180101
        -- CRITEO
        UNION
            SELECT
                fct.sk_date,
                'criteo'::varchar AS origin,
                'fact_criteo_daily_cost_attributions'::varchar AS fact_cost,
                dct.campaign_name,
                null AS campaign_city,
                advertiser_name AS account_name,
                lower(dct.campaign_name) AS campaign_name_l,
                lower(advertiser_name) AS account_name_l,
                dct.campaign_name AS utm_campaign,
                null::varchar(512) AS utm_term,
                null::varchar(512) AS utm_content,
                null::numeric(16,4) AS desktop_cost,
                null::numeric(16,4) AS mobile_cost,
                null::numeric(16,4) AS other_cost,
                fct.cost AS total_cost
            FROM marketing_costs.fact_criteo_daily_cost_attributions fct
                LEFT JOIN marketing_costs.dim_criteo_campaign dct
                ON fct.sk_criteo_campaign = dct.sk_criteo_campaign
            WHERE fct.sk_date >= 20180101
        -- RTB
        UNION
            select
                frt.sk_date,
                'rtb'::varchar as origin,
                'fact_rtb_daily_cost_attributions'::varchar as fact_cost,
                drt.campaign_name,
                null::varchar as campaign_city,
                drt.account_name as account_name,
                lower(drt.campaign_name) as campaign_name_l,
                lower(drt.account_name) as account_name_l,
                drt.campaign_name as utm_campaign,
                null::varchar(512) as utm_term,
                null::varchar(512) as utm_content,
                null::numeric(16,4) as desktop_cost,
                null::numeric(16,4) as mobile_cost,
                null::numeric(16,4) as other_cost,
                sum(cost) as total_cost
            from marketing.fact_rtb_daily_cost_attributions frt
            left join marketing.dim_rtb_sub_campaign drt
                on frt.sk_sub_campaign = drt.sk_sub_campaign
            where frt.sk_date >= 20180101
            group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14
        -- TWITTER
        UNION
            select
                ftw.sk_date,
                'twitter'::varchar as origin,
                'fact_twitter_daily_cost_attributions'::varchar as fact_cost,
                dtwc.campaign_name,
                null as campaign_city,
                dtwc.account_name as account_name,
                lower(dtwc.campaign_name) as campaign_name_l,
                lower(dtwc.account_name) as account_name_l,
                replace(dtwc.campaign_name, ' ', '_') as utm_campaign,
                upper(dtag.ad_group_name) as utm_term,
                null::varchar(512) as utm_content,
                sum(desktop_cost) as desktop_cost,
                sum(mobile_cost) as mobile_cost,
                sum(other_cost) as other_cost,
                null::numeric(16,4) as total_cost
            from marketing.fact_twitter_daily_cost_attributions ftw
            join marketing.dim_twitter_campaign dtwc
                on ftw.sk_campaign = dtwc.sk_campaign
            join marketing.dim_twitter_ad_group dtag
                on ftw.sk_ad_group = dtag.sk_ad_group
            where ftw.sk_date >= 20180101
            group by 1,2,3,4,5,6,7,8,9,10,11
        -- LINKEDIN
        UNION
            select
                fli.sk_date,
                'linkedin'::varchar as origin,
                'fact_linkedin_daily_cost_attributions'::varchar as fact_cost,
                dlc.campaign_name,
                null as campaign_city,
                dlcc.account_name as account_name,
                lower(dlc.campaign_name) as campaign_name_l,
                lower(dlcc.account_name) as account_name_l,
                dlc.campaign_name as utm_campaign,
                null::varchar as utm_term,
                null::varchar as utm_content,
                null::numeric(16,4) as desktop_cost,
                null::numeric(16,4) as mobile_cost,
                null::numeric(16,4) as other_cost,
                sum(total_cost) as total_cost
            from marketing.fact_linkedin_daily_cost_attributions fli
            join marketing.dim_linkedin_campaign dlc
                on dlc.sk_campaign = fli.sk_campaign
            join marketing.dim_linkedin_campaign_group dlcc
                on dlcc.sk_campaign_group = fli.sk_campaign_group
            group by 1,2,3,4,5,6,7,8,9,10,11

      )
      SELECT NULLIF(REGEXP_SUBSTR(campaign_name,'^([[:alpha:]]\\d{3}[[:alpha:]])'), '')::varchar as rule_id, * FROM sources
  ),
  shared_costs AS (
      SELECT
        sh.sk_date,
        origin,
        fact_cost,
        campaign_name,
        coalesce(r.city_group, sh.campaign_city) as campaign_city,
        account_name,
        campaign_name_l,
        account_name_l,
        utm_campaign,
        utm_term,
        utm_content,
        -- Desktop Cost Shared
        sh.desktop_cost * coalesce(r.share, 1)  as desktop_cost,
        -- Mobile Cost Shared
        sh.mobile_cost * coalesce(r.share, 1)  as mobile_cost,
        -- Other Cost Shared
        sh.other_cost * coalesce(r.share, 1)  as other_cost,
        -- Total Cost Shared
        sh.total_cost * coalesce(r.share, 1)  as total_cost
      FROM sources_to_be_shared sh
        LEFT JOIN staging.sharing_rules_marketing_daily_costs r
            ON sh.sk_date = r.sk_date
                AND sh.rule_id = r.rule_id
  )
  select
    sk_date,
    origin,
    fact_cost,
    campaign_name,
    campaign_city,
    account_name,
    campaign_name_l,
    CASE
      when campaign_name_l like '%calc%' then 'Calculator'
      else 'Other'
    end as campaign_origin_aquisition,
    account_name_l,
    utm_campaign,
    utm_term,
    utm_content,
    desktop_cost,
    mobile_cost,
    other_cost,
    total_cost
  from shared_costs
),
taxonomy_by_platform as (
    select
        txmc.*,
        s.mkt_platform,
        cast(coalesce(nullif(trim(SPLIT_PART(txmc.cost_factor, ';', s.i)), ''), '1.0') as float) as fator_custo
        from datalake_raw.gsheets_taxonomy_mkt_cost txmc
        cross join (
            select 1::integer, 'Desktop'::varchar
            union all
            select 2::integer, 'Mobile'::varchar
            union all
            select 3::integer, 'Other'::varchar
        ) as s(i, mkt_platform)
),
cost_taxonomy as (
    with manual_shared_costs as (
        SELECT
            NULL::varchar AS origin,
            to_char(NULLIF(dt, '')::date, 'yyyyMMdd')::integer as sk_date,
            NULLIF(account_name, '') AS account_name,
            NULLIF(campaign_name, '') AS campaign_name,
            NULLIF(city_group, '') AS cost_city_group,
            NULL AS city_campaign_mapping_rule,
            NULL AS campaign_city_matched,
            CASE
              when lower(NULLIF(campaign_name, '')) like '%calc%' then 'Calculator'
              else 'Other'
            end::varchar campaign_origin_aquisition,
            'Inbound'::varchar AS mkt_category,
            'Self-Service'::varchar AS mkt_flow,
            'Full Self-Service'::varchar AS mkt_completion,
            NULLIF(mkt_origin, '') AS mkt_origin,
            NULLIF(mkt_channel, '') AS mkt_channel,
            NULLIF(mkt_medium, '') AS mkt_medium,
            NULLIF(mkt_source, '') AS mkt_source,
            NULLIF(s.mkt_platform, '') AS mkt_platform,
            CASE WHEN  (coalesce(cast(nullif(cost_share_mobile, '') as numeric(12,2)), 0) +
                        coalesce(cast(nullif(cost_share_desktop, '') as numeric(12,2)), 0) +
                        coalesce(cast(nullif(cost_share_other, '') as numeric(12,2)), 0)) = 1 THEN
                            CASE WHEN s.mkt_platform = 'Mobile' THEN
                                coalesce(cast(nullif(cost_share_mobile, '') as numeric(12,2)), 0)
                            WHEN s.mkt_platform = 'Desktop' THEN
                                coalesce(cast(nullif(cost_share_desktop, '') as numeric(12,2)), 0)
                            WHEN s.mkt_platform = 'Other' THEN
                                coalesce(cast(nullif(cost_share_other, '') as numeric(12,2)), 0)
                            END
             ELSE
                CASE WHEN s.mkt_platform = 'Mobile' THEN 1::numeric(12,2) ELSE 0::numeric(12,2) END
            END AS fator_custo,
            NULLIF(campaign_name, '') AS utm_campaign,
            NULLIF(utm_term, '') AS utm_term,
            NULLIF(utm_content, '') AS utm_content,
            CAST(NULLIF(replace(cost, ',', ''), '') as numeric(12,2)) * fator_custo AS cost,
            NULLIF(side, '') AS side
        FROM
            datalake_raw.marketing_manual_shared_costs
        cross join (
            select 1::integer, 'Desktop'::varchar
            union all
            select 2::integer, 'Mobile'::varchar
            union all
            select 3::integer, 'Other'::varchar
        ) as s(i, mkt_platform)
    ),
    name_convention_shared_costs as (
        with city_group_share_rules as (
            SELECT
                NULL AS origin,
                replace(nullif(s.dt,''),'-','')::int AS sk_date,
                NULLIF(account_name, '') AS account_name,
                NULLIF(campaign_name, '') AS campaign_name,
                NULLIF(r.city_group, '') AS cost_city_group,
                NULL AS city_campaign_mapping_rule,
                NULL AS campaign_city_matched,
                CASE WHEN lower(NULLIF(campaign_name, '')) LIKE '%calc%'  THEN 'Calculator' ELSE 'Other'
                    END AS campaign_origin_aquisition,
                'Inbound' AS mkt_category,
                'Self-Service' AS mkt_flow,
                'Full Self-Service' AS mkt_completion,
                NULLIF(mkt_origin, '') AS mkt_origin,
                NULLIF(mkt_channel, '') AS mkt_channel,
                NULLIF(mkt_medium, '') AS mkt_medium,
                NULLIF(mkt_source, '') AS mkt_source,
                NULLIF(campaign_name, '') AS utm_campaign,
                NULLIF(utm_term, '') AS utm_term,
                NULLIF(utm_content, '') AS utm_content,
                CAST(NULLIF(replace(cost, ',', ''), '') AS numeric(16,4)) * r.share AS cost,
                NULLIF(side, '') AS side,
                cost_share_desktop,
                cost_share_mobile,
                cost_share_other
            FROM datalake_raw.marketing_name_convention_shared_costs s
                INNER JOIN staging.sharing_rules_marketing_daily_costs r
                    ON replace(nullif(s.dt,''),'-','')::int = r.sk_date
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
            /*  Cost factor  if share costs from platforms (mobile, desktop, other) sums to 1, then it means that the sharing is defined to
            *   platforms and needs to be used to share costs, otherwise, all sharing will attributed to Mobile platform.
            */
            CASE
                WHEN  (coalesce(cast(nullif(cost_share_mobile, '') as numeric(12,2)), 0) +
                            coalesce(cast(nullif(cost_share_desktop, '') as numeric(12,2)), 0) +
                            coalesce(cast(nullif(cost_share_other, '') as numeric(12,2)), 0)) = 1 THEN
                                CASE WHEN s.mkt_platform = 'Mobile' THEN
                                    coalesce(cast(nullif(cost_share_mobile, '') as numeric(12,2)), 0)
                                WHEN s.mkt_platform = 'Desktop' THEN
                                    coalesce(cast(nullif(cost_share_desktop, '') as numeric(12,2)), 0)
                                WHEN s.mkt_platform = 'Other' THEN
                                    coalesce(cast(nullif(cost_share_other, '') as numeric(12,2)), 0)
                                END
                ELSE
                    CASE WHEN s.mkt_platform = 'Mobile' THEN 1 ELSE 0 END
            END AS fator_custo,
            utm_campaign,
            utm_term,
            utm_content,
            CAST(NULLIF(replace(cost, ',', ''), '') as numeric(16,4)) * fator_custo AS cost,
            NULLIF(side, '') AS side
        FROM city_group_share_rules sr
        CROSS JOIN (
            SELECT 1, 'Desktop'
            UNION ALL
            SELECT 2, 'Mobile'
            UNION ALL
            SELECT 3, 'Other')
        AS s(i, mkt_platform)
    )
    select
        cf.origin,
        cf.sk_date,
        cf.account_name,
        cf.campaign_name,
        -- city via manual mapping
        mccc.city_group as cost_city_group,
        -- city via campaign_name full name written
        case
            when campaign_name_l in ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre')
                then campaign_name_l
            when cf.campaign_name_l like '%campinas%' then 'Campinas'
            when cf.campaign_name_l like '%s_o_paulo%' or cf.campaign_name_l like '%sp detailed%' then 'RMSP'
            when cf.campaign_name_l like 'sp %' then 'RMSP'
            when cf.campaign_name_l like '%all cities%' then 'RMSP'
            when cf.campaign_name_l like '%rmsp%' then 'RMSP'
            when cf.campaign_name_l like '%guarulhos%' then 'RMSP'
            when cf.campaign_name_l like '%abc%' then 'RMSP'
            when cf.campaign_name_l like '%barueri%' then 'RMSP'
            when cf.campaign_name_l like '%osasco%' then 'RMSP'
            when cf.campaign_name_l like '%jundia%' then 'RMSP'
            when cf.campaign_name_l like '%santo_andr%' then 'RMSP'
            when cf.campaign_name_l like '%s_o_bernardo%' then 'RMSP'
            when cf.campaign_name_l like '%s_o_caetano%' then 'RMSP'
            when cf.campaign_name_l like '%rio%de%janeiro%' then 'Rio de Janeiro'
            when cf.campaign_name_l like '%niter_i%' then 'Rio de Janeiro'
            when cf.campaign_name_l like '%bh%' or cf.campaign_name_l like '%belo%h%' then 'Belo Horizonte'
            when cf.campaign_name_l like '%minas_gerais%' then 'Belo Horizonte'
            when cf.campaign_name_l like '%goi_nia%' or cf.campaign_name_l like '%goi_s%' then 'Goiânia'
            when cf.campaign_name_l like '%bras_lia%' or cf.campaign_name_l like '%distrito_federal%' then 'Brasília'
            when cf.campaign_name_l like '%porto%alegre%' then 'Porto Alegre'
            when cf.campaign_name_l like '%curitiba%' or cf.campaign_name_l like '%paran_%' then 'Curitiba'
            when cf.campaign_name_l like '%florian_polis%' or cf.campaign_name_l like '%santa_catarina%' then 'Florianópolis'
            when cf.campaign_name_l like '%poa%' then 'Porto Alegre'
            when cf.campaign_name_l like '%ctba%' then 'Curitiba'
            when cf.campaign_name_l like '%fln%' then 'Florianópolis'
            when cf.campaign_name_l like '%cps%' then 'Campinas'
            when cf.campaign_name_l like '%bsb%' then 'Brasília'
            when cf.campaign_name_l like '%rj%' then 'Rio de Janeiro'
        end as city_campaign_mapping_rule,
        -- city via campaign_name name convention
        case
             when campaign_city in ('Florianópolis', 'Curitiba', 'Goiânia', 'Rio de Janeiro', 'RMSP', 'Belo Horizonte', 'Brasília', 'Campinas', 'Porto Alegre')
                then campaign_city
             when campaign_city = 'campinas' then 'Campinas'
             when campaign_city in ('sp', 'jui', 'santo_andre', 'guarulhos', 'osasco', 'sao_caetano', 'sao_bernardo', 'barueri', 'rmsp') then 'RMSP'
             when campaign_city in ('rj', 'niteroi', 'rio_de_janeiro', 'rio') then 'Rio de Janeiro'
             when campaign_city in ('bh', 'belo_horizonte') then 'Belo Horizonte'
             when campaign_city = 'goiania' then 'Goiânia'
             when campaign_city in ('poa', 'porto_alegre') then 'Porto Alegre'
             when campaign_city = 'curitiba' then 'Curitiba'
             when campaign_city in ('fln', 'florianopolis') then 'Florianópolis'
             when campaign_city in ('bsb', 'brasilia') then 'Brasília'
        end as campaign_city_matched,
        tp.campaign_origin_aquisition,
        tp.mkt_category,
        tp.mkt_flow,
        tp.mkt_completion,
        tp.mkt_origin,
        tp.mkt_channel,
        tp.mkt_medium,
        tp.mkt_source,
        tp.mkt_platform,
        tp.fator_custo,
        cf.utm_campaign,
        cf.utm_term,
        cf.utm_content,
        case
            when total_cost is null then
                case when tp.mkt_platform = 'Mobile' then mobile_cost
                     when tp.mkt_platform = 'Desktop' then desktop_cost
                     when tp.mkt_platform = 'Other' then other_cost
                end
            else total_cost
        end * cast(coalesce(tp.fator_custo, '0') as numeric(3,2)) as cost,
        -- Funnel side is extracted from taxonomy
        tp.side
    from campaigns_full cf
        left join datalake_raw.gsheets_marketing_cost_campaign_city as mccc
            on lower(mccc.campaign_name) = cf.campaign_name_l
        left join taxonomy_by_platform as tp
            on coalesce(cf.account_name, '') = coalesce(tp.account_name, '')
                and cf.fact_cost = tp.fact_cost
                and cf.origin = tp.origin
        and cf.campaign_origin_aquisition = tp.campaign_origin_aquisition
    -- Append manual costs
    union
    SELECT
        *
    FROM manual_shared_costs
    WHERE cost > 0
    UNION
    -- Append Name Convetion costs
    SELECT
        *
    FROM name_convention_shared_costs
    WHERE cost > 0
),
kenshoo_raw as (
    select
        ct.sk_date,
        ct.side as funnel_side,
        tp.account_name as account_name,
        null::VARCHAR(256) as campaign_name,
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
        null::VARCHAR(256) as utm_campaign,
        null::VARCHAR(256) as utm_term,
        null::VARCHAR(256) as utm_content,
        (ct.cost * cast(k.rate as float) * tp.fator_custo)::numeric(12,4) as cost
    from cost_taxonomy ct
    join datalake_raw.gsheets_marketing_kenshoo_configuration k
        on	ct.mkt_source = k.mkt_source
        and ct.mkt_medium = k.mkt_medium
        and ct.sk_date between
            cast(to_char(to_date(k.date_from, 'MM/DD/YYYY'), 'YYYYMMDD') as integer)
                and
                    cast(to_char(to_date(k.date_until, 'MM/DD/YYYY'), 'YYYYMMDD') as integer)
    left join taxonomy_by_platform as tp
        on tp.origin = 'kenshoo'
        and tp.side = ct.side
        and tp.campaign_origin_aquisition = ct.campaign_origin_aquisition
),
kenshoo as (
    select
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
        sum(cost) as cost
    from kenshoo_raw
    group by
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
final_costs as (
    select
        sk_date,
        side as funnel_side,
        account_name::VARCHAR(512),
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
        cost::NUMERIC(16,4)
    from cost_taxonomy
    union all
    select
        sk_date,
        funnel_side,
        account_name::VARCHAR(512),
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
        cost::NUMERIC(16,4)
    from kenshoo

)

SELECT
    sk_date,
    funnel_side,
    account_name,
    campaign_name,
    -- consolidating final city_group
    COALESCE(cost_city_group,
        city_campaign_mapping_rule,
        campaign_city_matched,
        'Not Mapped') AS city_group_final,
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
    cost,
    getdate() as ts_load
FROM
    final_costs
