WITH
media_plan AS (--Importing main tables
    SELECT
        id_rule_city_group,
        id_insertion_order,
        media,
        network,
        short_region_name,
        city_name,
        channel,
        program,
        program_frequency,
        program_hour_started,
        program_hour_ended,
        program_genre,
        program_daypart,
        creative_name,
        ad_description,
        ad_type,
        cost,
        grp,
        trp,
        dt_insertion_order,
        dt_started,
        dt_ended
    FROM
        datalake_gsheets_clean.media_plan_current_quarter
    UNION ALL
    SELECT
        id_rule_city_group,
        id_insertion_order,
        media,
        network,
        short_region_name,
        city_name,
        channel,
        program,
        frequency AS program_frequency,
        hour_started AS program_hour_started,
        hour_ended AS program_hour_ended,
        genre AS program_genre,
        daypart AS program_daypart,
        creative AS creative_name,
        ad_description,
        ad_type,
        cost,
        grp,
        trp,
        dt_insertion_order,
        dt_started,
        dt_ended
    FROM
        datalake_media_plan_clean.media_plan
),
city_group_rules AS ( --Importing city_group share rules
    SELECT
        id_rule_city_group,
        city_group,
        share
    FROM
        datalake_marketing_offline_costs_clean.marketing_offline_manual_share_city_group
),
apply_city_group_share AS ( --Applying city_group share
    SELECT
        MONOTONICALLY_INCREASING_ID() AS id_aux,
        mp.id_insertion_order,
        mp.media,
        CASE
            WHEN mp.media = 'INTERNET'
                THEN 'Influencer'
            WHEN mp.media = 'TV ABERTA'
                THEN 'OpenTV'
            WHEN mp.media = 'TV PAGA'
                THEN 'PayTV'
            WHEN mp.media = 'OUT OF HOME'
                THEN 'OOH'
            WHEN mp.media = 'RÁDIO'
                THEN 'Rádio'
            WHEN mp.media = 'JORNAL'
                THEN 'Jornal/Revista'
            WHEN mp.media = 'REVISTA'
                THEN 'Jornal/Revista'
                ELSE mp.media
        END AS media_mmm,
        mp.network,
        mp.short_region_name,
        COALESCE(cgr.city_group, dr.city_group) AS city_group,
        mp.city_name,
        mp.channel,
        mp.program,
        CASE 
            WHEN LOWER(program) LIKE '%produ__o%'
                THEN TRUE
                ELSE FALSE
        END AS is_production,
        mp.program_frequency,
        mp.program_hour_started,
        mp.program_hour_ended,
        mp.program_genre,
        mp.program_daypart,
        mp.creative_name,
        mp.ad_description,
        mp.ad_type,
        mp.cost*COALESCE(cgr.share, 1) AS cost,
        mp.grp*COALESCE(cgr.share, 1) AS grp,
        mp.trp*COALESCE(cgr.share, 1) AS trp,
        mp.dt_insertion_order,
        DATE(COALESCE(mp.dt_started, mp.dt_insertion_order)) AS dt_started,
        DATE(COALESCE(mp.dt_ended, mp.dt_insertion_order)) AS dt_ended
    FROM
        media_plan mp
    LEFT JOIN
        city_group_rules cgr
    ON
        mp.id_rule_city_group = cgr.id_rule_city_group
    LEFT JOIN
        datalake_region.region dr
    ON
        SF_REMOVE_ACCENTUATION(TRIM(LOWER(mp.city_name))) = SF_REMOVE_ACCENTUATION(TRIM(LOWER(dr.name)))
        AND dr.level = 'Cidade'
),
date_range AS ( --Creating a dim_date with the used dates
    SELECT 
        EXPLODE(
            SEQUENCE(
            MIN(dt_started),
            MAX(dt_ended),
            interval 1 day
            )
        ) AS dt
        FROM
            apply_city_group_share
        WHERE
            is_production = FALSE
),
aux_date_range AS ( --Exploding dates and calculating the days of campaign duration for non-production entries
    SELECT
        dr.dt,
        INT(DATE_FORMAT(DATE(dr.dt), 'yyyyMMdd')) AS id_date,
        mp.id_aux,
        COUNT(dr.dt) OVER(PARTITION BY mp.id_aux) AS days_duration
    FROM
        apply_city_group_share mp
    JOIN
        date_range dr
    ON
        dr.dt BETWEEN mp.dt_started AND mp.dt_ended
        AND mp.is_production = FALSE
),
media_plan_wo_production AS ( --Exploding media plan and applying share for non-production entries
    SELECT
        adr.id_date,
        adr.dt,
        acgs.*,
        acgs.cost/adr.days_duration AS daily_cost,
        acgs.grp/adr.days_duration AS daily_grp,
        acgs.trp/adr.days_duration AS daily_trp
    FROM
        apply_city_group_share acgs
    JOIN
        aux_date_range adr
    ON
        acgs.id_aux = adr.id_aux
        AND acgs.is_production = FALSE
),
aux_ooh_cost AS ( --Aux table to explode production rows, based on OOH entries
    SELECT 
        mpwop.id_date,
        mpwop.city_group,
        SUM(acgs.cost) AS daily_cost
    FROM 
        media_plan_wo_production mpwop
    JOIN
        apply_city_group_share acgs
    ON
        mpwop.city_group = acgs.city_group
        AND acgs.is_production
    WHERE 
        mpwop.media_mmm = 'OOH'
        AND CAST(mpwop.dt AS DATE) between acgs.dt_started AND acgs.dt_ended
    GROUP BY
        1,2
),
share_ooh_cost AS (--Exploding production rows and calculating share
  SELECT 
      id_date,
      city_group,
      daily_cost/sum(daily_cost) OVER(PARTITION BY city_group) AS share
  FROM 
      aux_ooh_cost
),
media_plan_production AS ( --Exploding media plan and applying share for production entries
    SELECT
        soc.id_date,
        acgs.*,
        acgs.cost*soc.share AS daily_cost,
        acgs.grp*soc.share AS daily_grp,
        acgs.trp*soc.share AS daily_trp
    FROM
        apply_city_group_share acgs
    JOIN
        share_ooh_cost soc
    ON
        acgs.city_group = soc.city_group
        AND acgs.is_production
)
SELECT
    id_date,
    id_insertion_order,
    media,
    media_mmm,
    network,
    short_region_name,
    city_group,
    city_name,
    channel,
    program,
    program_frequency,
    program_hour_started,
    program_hour_ended,
    program_genre,
    program_daypart,
    creative_name,
    ad_description,
    ad_type,
    daily_cost,
    daily_grp,
    daily_trp,
    dt_insertion_order,
    dt_started,
    dt_ended
FROM
    media_plan_wo_production
UNION ALL
SELECT
    id_date,
    id_insertion_order,
    media,
    media_mmm,
    network,
    short_region_name,
    city_group,
    city_name,
    channel,
    program,
    program_frequency,
    program_hour_started,
    program_hour_ended,
    program_genre,
    program_daypart,
    creative_name,
    ad_description,
    ad_type,
    daily_cost,
    daily_grp,
    daily_trp,
    dt_insertion_order,
    dt_started,
    dt_ended
FROM
    media_plan_production