-- Criar coluna com o último status da versão?
-- Criar coluna 

WITH house_aud AS (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made                                                --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    SELECT
        CAST(FROM_UNIXTIME(CAST(rev.ts_revision AS BIGINT)/1000) AS TIMESTAMP) AS revision_time,
        CAST(FROM_UNIXTIME(CAST(rev.ts_revision AS BIGINT)/1000) AS DATE) AS status_date,
        rev.id_user,
        rev.reason,
        lag(h.status) OVER(PARTITION BY h.id_house ORDER BY h.rev) AS previous_status,
        lag(h.rent) OVER(PARTITION BY h.id_house ORDER BY h.rev) AS previous_rent_price,
        h.status,
        h.rent,
        h.id_house,
        h.rev,
        h.mod_status,
        h.mod_rent,
        h.dt_first_publication
    FROM
      datalake_ebdb_clean.house_aud AS h
    INNER JOIN 
      datalake_ebdb_clean.user_revision_entity AS rev
        ON rev.id = h.rev
),
max_status_order AS ( 
--------------------------------------------------------------------------------------------------------
-- Identify the last status to each version                                                           --
--------------------------------------------------------------------------------------------------------
    SELECT
        id_house,
        listing_version,
        MAX(state_order) AS max_order_status
    FROM
      datalake_ebdb_listing.lbc_status_version_order
    GROUP BY
      id_house, listing_version
),
house_status_version_last_status AS (
    SELECT
        lbc_vo.id_house,
        lbc_vo.status,
        LAG(status) OVER(PARTITION BY lbc_vo.id_house ORDER BY lbc_vo.ts_state_started) AS previous_status,
        lbc_vo.status_reason,
        lbc_vo.ts_state_started,
        lbc_vo.ts_state_ended,
        lbc_vo.days_in_state,
        lbc_vo.days_in_status,
        lbc_vo.trigger_new_version,
        lbc_vo.listing_version,
        lbc_vo.state_order,
        lbc_vo.max_state_order,
        lbc_vo.country_code,
        MAX(
          CASE
              WHEN lbc_vo.status IN ('despublicado', 'UNPUBLISHED')
              THEN ts_state_started
          END
        ) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS ts_last_unpublished,
        IF(ms_o.max_order_status IS NOT NULL, lbc_vo.status, NULL) AS last_status,
        MAX(lbc_vo.state_order) OVER(PARTITION BY lbc_vo.id_house, lbc_vo.listing_version) AS max_order_status_version
    FROM 
      datalake_ebdb_listing.lbc_status_version_order lbc_vo
    LEFT JOIN 
      max_status_order AS ms_o
        ON lbc_vo.id_house = ms_o.id_house
        AND lbc_vo.listing_version = ms_o.listing_version
        AND lbc_vo.state_order = ms_o.max_order_status
    
),
status_change_version AS (
--------------------------------------------------------------------------------------------------------
-- Identify the status that made it changes to a new version                                          --
-- This status is important to define which category the listing will have                            --
--------------------------------------------------------------------------------------------------------
    select
        id_house,
        listing_version,
        MAX(status) OVER(PARTITION BY id_house, listing_version) AS category_change
    FROM 
      house_status_version_last_status
    WHERE 
      trigger_new_version = 1
),
house_listing_plain as (
--------------------------------------------------------------------------------------------------------
-- Create listings column according to version                                                        --
-- Create column to identify category (using column from join with status_change_version              --
-- Keep only the version changes                                                                      --
--------------------------------------------------------------------------------------------------------
    SELECT
        hs_v.id_house,
        hs_v.country_code,
        hs_v.listing_version AS version,
        sc_v.category_change AS change_version_status,
        hs_v.ts_last_unpublished,
        MAX(hs_v.previous_status) AS status_history,
        MAX(hs_v.ts_state_started) AS ts_status_changed,
        MAX(hs_v.last_status) AS status,
        MIN(hs_v.ts_state_started) AS ts_listing_version_start,
        MAX(COALESCE(hs_v.ts_state_ended, CAST('2200-01-01 12:00:00' AS TIMESTAMP))) AS ts_listing_version_end
    FROM
      house_status_version_last_status AS hs_v
    LEFT JOIN 
      status_change_version AS sc_v
        ON hs_v.id_house = sc_v.id_house
        AND hs_v.listing_version = sc_v.listing_version
    GROUP BY 1, 2, 3, 4, 5
), 
house_listing_full AS (
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
    SELECT
        CAST(CAST(id_house AS STRING)||'00'||CAST(version AS STRING) AS BIGINT) AS id_house_listing,
        id_house,
        country_code,
        version,
        CASE WHEN version = 0 then null
             WHEN version = 1 then 'First Listing'
             WHEN version <> 0 AND LAG(change_version_status) OVER(PARTITION BY id_house ORDER BY version) IN ('alugado', 'RENTED') then 'Re-Listing'
             WHEN version <> 0 AND LAG(change_version_status) OVER(PARTITION BY id_house ORDER BY version) IN ('despublicado', 'UNPUBLISHED') THEN 'Recovered'
             ELSE NULL 
        END AS listing_category,
        status,
        status_history,
        ts_status_changed,
        ts_listing_version_start,
        NULLIF(CAST(ts_listing_version_end AS TIMESTAMP), CAST('2200-01-01 12:00:00' AS TIMESTAMP)) AS ts_listing_version_end,
        ts_last_unpublished
    FROM 
      house_listing_plain
),
house_rent_history as (
--------------------------------------------------------------------------------------------------------------------
-- Create rent_price_history: for each house show all rent price changes, with start and end of each rent price   --
--------------------------------------------------------------------------------------------------------------------
    select
        id_house,
        rev,
        mod_rent,
        revision_time as ts_rent_price_changed,
        rent as rent_price_history,
        lead(revision_time) over(partition by id_house order by rev) as ts_next_rent_price_change,
        row_number() over(partition by id_house order by rev) as order_rent_price,
        max(revision_time) over(partition by id_house) as max_ts_rent_price_changed
    from house_aud
    where (rent <> previous_rent_price or previous_rent_price is null)
),
house_rent_max as (
    select
        hlf.id_house_listing,
        hlf.id_house,
        hlf.country_code,
        hlf.version,
        rh.rev,
        rh.rent_price_history,
        rh.order_rent_price,
        max(rh.order_rent_price) over(partition by hlf.id_house, hlf.version) as max_order_status_version
    from house_listing_full hlf
    join house_rent_history rh
        on hlf.id_house = rh.id_house
        and ((rh.ts_rent_price_changed between hlf.ts_listing_version_start and coalesce(hlf.ts_listing_version_end - interval '1' second, current_timestamp))
        or (coalesce(rh.ts_next_rent_price_change,current_timestamp) between hlf.ts_listing_version_start and coalesce(hlf.ts_listing_version_end - interval '1' second, current_timestamp))
        or (rh.max_ts_rent_price_changed <= hlf.ts_listing_version_start))
),
listing_rent_last as (
    select
        id_house_listing,
        max(case when max_order_status_version = order_rent_price then rent_price_history end) as rent
    from house_rent_max
    group by 1
),
special_conditions_prev as (
-- filter multiple changes in a single day
-- example:
-- ----------------------------------------------------------------------------------------------------------------------------------
-- |     id      |  special_condition_type  |       ts_opted_in      |       ts_opted_out      |    special_condition_status_mod    |
-- ----------------------------------------------------------------------------------------------------------------------------------
-- |    33713    |       Exclusivity	    |   2019-04-24 21:01:08	 |           null          |                1 (opt-in)          | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:01:08	 |    2019-04-24 21:01:10  |                1 (opt-out)         | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:05:17	 |           null          |                1 (opt-in)          | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:05:17	 |    2019-04-24 21:05:35  |                1 (opt-out)         |
-- ----------------------------------------------------------------------------------------------------------------------------------
    select
        id_special_condition,
        special_condition_type,
        date(ts_opted_in) as dt_opted_in,
        max(date(ts_opted_out)) as dt_opted_out
    from datalake_ebdb_clean.special_condition_aud
    where special_condition_status in ('OptedIn', 'OptedOut')
        and special_condition_type in ('Exclusivity', 'OriginalsReady', 'OriginalsReno', 'ORent', 'IRent')
    group by 1, 2, 3
),
special_conditions as (
--------------------------------------------------------------------------------------------------------
-- Include flags of special condition (exclusivity and originals)                                     --
--------------------------------------------------------------------------------------------------------
    select
        hsc.id_house,
        scp.special_condition_type,
        scp.dt_opted_in,
        max(scp.dt_opted_out) as dt_opted_out
    from datalake_ebdb_clean.house_special_condition hsc
    join datalake_ebdb_clean.special_condition sc
        on hsc.id_special_condition = sc.id
    join special_conditions_prev scp
        on scp.id_special_condition = sc.id
    group by 1, 2, 3
),
listing_special_conditions as (
-- selecting the last time a listing had its special condition changed on its version
-- example:
-- ----------------------------------------------------------------------------------
-- |  id_house_listing  |  special_condition_type  |  dt_opted_in  |  dt_opted_out  |
-- ----------------------------------------------------------------------------------
-- |    892812943001    |      OriginalsReady      |   2019-03-04  |   2019-05-12   | -> will be removed
-- |    892812943001    |      OriginalsReady      |   2019-05-13  |      null      |
-- ----------------------------------------------------------------------------------
    select
        hl.id_house_listing,
        hl.country_code,
        sc.special_condition_type,
        max(sc.dt_opted_in) as dt_opted_in,
        max(sc.dt_opted_out) as dt_opted_out
    from house_listing_full hl
    join special_conditions sc
        on hl.id_house = sc.id_house
        and greatest(sc.dt_opted_in, date(hl.ts_listing_version_start)) >= date(hl.ts_listing_version_start)
        and greatest(sc.dt_opted_in, date(hl.ts_listing_version_start)) < coalesce(date(hl.ts_listing_version_end), date(now()))
        and greatest(coalesce(sc.dt_opted_out, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= coalesce(date(hl.ts_listing_version_end), date(now() - interval '1' day))
        and greatest(coalesce(sc.dt_opted_out, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= date(hl.ts_listing_version_start)
    group by 1, 2, 3
),
multiple_special_conditions as (
-- in case a house listing has more than one Special Condition types: exclusivity, ready and reno on the same version
    select
        id_house_listing,
        country_code,
        special_condition_type,
        dt_opted_in,
        dt_opted_out,
        -- selecting the maximum opt-in/out of a house listing, not considering the Originals' type and ioRents' type
        row_number() over (partition by id_house_listing,
                          case when special_condition_type like 'Originals%' then 'Originals'
                               when special_condition_type like '%Rent' then 'ioRent'
                               else special_condition_type
                          end order by dt_opted_in desc, coalesce(dt_opted_out, date('2100-01-01')) desc) as rn_last,
        row_number() over (partition by id_house_listing,
                          case when special_condition_type like 'Originals%' then 'Originals'
                               when special_condition_type like '%Rent' then 'ioRent'
                               else special_condition_type
                          end order by dt_opted_in asc, coalesce(dt_opted_out, date('2100-01-01')) asc) as rn_first
    from listing_special_conditions
),
last_opt as (
-- select the latest Special Condition type a house listing has entered
    select
        id_house_listing,
        country_code,
        special_condition_type,
        dt_opted_in,
        dt_opted_out
    from multiple_special_conditions
    where rn_last = 1
),
first_opt as (
-- select the oldest Special Condition type a house listing has entered
    select
        id_house_listing,
        country_code,
        special_condition_type,
        dt_opted_in,
        dt_opted_out
    from multiple_special_conditions
    where rn_first = 1
),
listing_special_conditions_dates as (
    select
        fo.id_house_listing,
        fo.country_code,
        lo.special_condition_type, -- important to select special_condition_type from last_op since we want to show LAST special condition type
        fo.dt_opted_in as dt_first_opted_in,
        fo.dt_opted_out as dt_first_opted_out,
        lo.dt_opted_in as dt_last_opted_in,
        lo.dt_opted_out as dt_last_opted_out
    from last_opt lo
    join first_opt fo
         on lo.id_house_listing = fo.id_house_listing
         and (case
                when lo.special_condition_type like 'Originals%' then 'Originals'
                when lo.special_condition_type like '%Rent' then 'ioRent'
                else lo.special_condition_type
              end) =
              (case
                when fo.special_condition_type like 'Originals%' then 'Originals'
                when fo.special_condition_type like '%Rent' then 'ioRent'
                else fo.special_condition_type
              end)
),
house_listing AS (
    select
        hl.id_house_listing,
        hl.id_house,
        hl.country_code,
        hl.version,
        hl.status,
        rent_last.rent,
        hl.listing_category,
        lsc_originals.special_condition_type as last_originals_type,
        lsc_iorent.special_condition_type as last_iorent_type,
        hl.version = max(hl.version) over (partition by hl.id_house) as is_last_version,
        lsc_exclusivity.dt_first_opted_in is not null as is_exclusive,
        ((lsc_originals.dt_last_opted_in is not null and lsc_originals.dt_last_opted_out is null)
            or (lsc_originals.dt_last_opted_in > lsc_originals.dt_last_opted_out)) as is_originals_active,
        ((lsc_iorent.dt_last_opted_in is not null and lsc_iorent.dt_last_opted_out is null)
            or (lsc_iorent.dt_last_opted_in > lsc_iorent.dt_last_opted_out)) as is_iorent_active,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        ts_last_unpublished,
        lsc_exclusivity.dt_last_opted_in as dt_last_exclusive_opted_in,
        lsc_exclusivity.dt_last_opted_out as dt_last_exclusive_opted_out,
        lsc_originals.dt_last_opted_in as dt_last_originals_opted_in,
        lsc_originals.dt_last_opted_out as dt_last_originals_opted_out,
        lsc_iorent.dt_last_opted_in as dt_last_iorent_opted_in,
        lsc_iorent.dt_last_opted_out as dt_last_iorent_opted_out
    from house_listing_full hl
    left join listing_special_conditions_dates lsc_originals
        on hl.id_house_listing = lsc_originals.id_house_listing
        and lsc_originals.special_condition_type like 'Originals%'
    left join listing_special_conditions_dates lsc_exclusivity
        on hl.id_house_listing = lsc_exclusivity.id_house_listing
        and lsc_exclusivity.special_condition_type = 'Exclusivity'
    left join listing_special_conditions_dates lsc_iorent
        on hl.id_house_listing = lsc_iorent.id_house_listing
        and lsc_iorent.special_condition_type like '%Rent'
    left join listing_rent_last rent_last
        on hl.id_house_listing = rent_last.id_house_listing
),
house_listing_latest_contracts AS (
----------------------------------------------------------------------------------------------------------
-- Include information related to contracts (including only active or ended contracts) for each listing --
----------------------------------------------------------------------------------------------------------
    select
      hl.id_house_listing,
      max(c.id) as id_contract,
      dense_rank() over (partition by hl.id_house order by hl.id_house_listing) as order_renting
    from house_listing hl
    join datalake_ebdb_clean.contract c
      on hl.id_house = c.id_house
      and c.ts_signed between coalesce(hl.ts_listing_version_start, '2000-01-01 00:00:00') and coalesce(hl.ts_listing_version_end, current_date)
      and c.status in ('Ativo', 'Finalizado')
    group by 1, hl.id_house
),
house_listing_stranded_status_all AS (
    --select all status FROM each listing, calculate date_to_be_stranded using publication_date AND find IN which status was the stranded date
    SELECT
        hls.id_house_listing,
        hls.status_history,
        hls.ts_status_started,
        COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 day)) AS ts_status_ended,
        hl.ts_listing_version_start,
        (hl.ts_listing_version_start + INTERVAL 8 week) AS ts_to_be_stranded,
        CASE
            WHEN (hl.ts_listing_version_start + INTERVAL 8 week) <= hls.ts_status_started
              OR (hl.ts_listing_version_start + INTERVAL 8 week) <= COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 day))
            THEN 'stranded'
        END AS type_stranded,
        LAG(hls.status_history) OVER(PARTITION BY hls.id_house_listing ORDER BY hls.ts_status_started, COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_status_history
    FROM datalake_ebdb_listing.house_listing_status hls
    LEFT JOIN house_listing hl
      ON hls.id_house_listing = hl.id_house_listing
),
house_listing_stranded_rank_stranded AS (
    --select only status WHERE stranded date already happened
    SELECT
        id_house_listing,
        status_history,
            previous_status_history,
        ts_status_started,
        ts_status_ended,
        ts_listing_version_start,
        ts_to_be_stranded,
        type_stranded,
        ROW_NUMBER() OVER (PARTITION BY id_house_listing, type_stranded ORDER BY ts_status_started) AS rn,
        --calculate min date of all status, because if it is a valid status that is the date that will be used
        MIN(CASE WHEN type_stranded = 'stranded' THEN ts_status_started END) OVER (PARTITION BY id_house_listing) AS min_ts_all_status,
        --calculate min date of valid status to define stranded
        MIN(CASE WHEN type_stranded = 'stranded'
                      AND status_history IN ('publicado','suspenso','edicao','aguardando_publicacao')
                                  AND (previous_status_history <> 'alugado' OR previous_status_history is null)
                 THEN ts_status_started END) over (PARTITION BY id_house_listing) AS min_ts_valid_status,
        MIN(CASE WHEN type_stranded = 'stranded' THEN ts_to_be_stranded END) over (PARTITION BY id_house_listing) AS min_ts_to_be_stranded
    FROM house_listing_stranded_status_all
    WHERE type_stranded IS NOT NULL
),
house_listing_stranded_status AS (
    select
        *,
        case WHEN rn = 1 AND status_history = 'alugado' THEN NULL
             WHEN rn = 1 AND status_history IN ('despublicado','excluido')
               THEN MIN(min_ts_valid_status) over (PARTITION BY id_house_listing)
             WHEN rn = 1 AND status_history IN ('publicado','suspenso','edicao','aguardando_publicacao')
               THEN MIN(min_ts_valid_status) over (PARTITION BY id_house_listing)
             END AS min_ts_stranded
            /*
             * case statement needed IN order to ignore cases where stranded date happened on not valid status
             * (such AS 'alugado', 'despublicado', 'excluido'), but if it was 'despublicado' consider next valid status
             * example 0:
             *  -----------------------------------------------------------------------------------------------------------------
             *  |listing | min_status_date | max_status_date | status    | ts_publication | date_to_be_stranded | stranded_date |
             *  | 001    |   2018-12-06    |  2018-12-13     | publicado |  2018-12-06    |  2019-01-31         | NULL          |
             *  | 001    |   2018-12-13    |  2018-12-14     | suspenso  |  2018-12-06    |  2019-01-31         | NULL          |
             *  | 001    |   2018-12-14    |  2019-03-19     | alugado   |  2018-12-06    |  2019-01-31         | NULL          |
             *  -----------------------------------------------------------------------------------------------------------------
             *
             * 	example 1:
             *  --------------------------------------------------------------------------------------------------------------------
             *  |listing | min_status_date | max_status_date | status       | ts_publication | date_to_be_stranded | stranded_date |
             *  | 002    |   2018-12-05    |  2019-02-12     | publicado    |  2018-12-05    |  2019-01-30         | 2019-01-31    |
             *  | 002    |   2019-02-12    |  2019-02-19     | suspenso     |  2018-12-05    |  2019-01-30         | 2019-01-31    |
             *  | 002    |   2019-02-19    |  2019-03-14     | publicado    |  2018-12-05    |  2019-01-30         | 2019-01-31    |
             *  | 002    |   2019-03-14    |  2019-03-19     | despublicado |  2018-12-05    |  2019-01-30         | 2019-01-31    |
             *  --------------------------------------------------------------------------------------------------------------------
             *
             * 	example 2:
             *  --------------------------------------------------------------------------------------------------------------------
             *  |listing | min_status_date | max_status_date | status       | ts_publication | date_to_be_stranded | stranded_date |
             *  | 003    |   2018-12-06    |  2018-12-07     | publicado    |  2018-12-06    |  2019-01-31         | 2019-02-11    |
             *  | 003    |   2018-12-07    |  2019-02-11     | despublicado |  2018-12-06    |  2019-01-31         | 2019-02-11    |
             *  | 003    |   2019-02-11    |  2019-03-07     | publicado    |  2018-12-06    |  2019-01-31         | 2019-02-11    |
             *  | 003    |   2019-03-07    |  2019-03-19     | despublicado |  2018-12-06    |  2019-01-31         | 2019-02-11    |
             *  --------------------------------------------------------------------------------------------------------------------
             */
    FROM house_listing_stranded_rank_stranded
),
house_listing_stranded_date AS (
    SELECT
        DISTINCT id_house_listing,
        CASE
            WHEN GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01') AS TIMESTAMP), CAST(min_ts_to_be_stranded AS TIMESTAMP)) = '3000-01-01'
            THEN NULL
            ELSE GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01')  AS TIMESTAMP), CAST(min_ts_to_be_stranded AS TIMESTAMP))
        END AS dt_stranded
    FROM house_listing_stranded_status
    WHERE rn = 1
),
house_entrance_history AS (
  SELECT
        hl.id_house_listing,
        ot.name,
        hl.version,
        MAX(heh.rev) OVER(PARTITION BY hl.id_house_listing) = heh.rev AS is_last_status_in_listing,
        heh.ts_entrance_started
  FROM datalake_ebdb_listing.house_entrance_history AS heh
  LEFT JOIN datalake_ebdb_clean.occupant_type AS ot
    ON ot.id = heh.id_occupant
  JOIN house_listing AS hl
    ON heh.id_house = hl.id_house
    AND (heh.ts_entrance_started BETWEEN COALESCE(hl.ts_listing_version_start, DATE('1922-01-01')) AND COALESCE(hl.ts_listing_version_end, DATE('2100-01-01'))
    OR COALESCE(hl.ts_listing_version_start, DATE('1922-01-01')) BETWEEN heh.ts_entrance_started AND COALESCE(heh.ts_entrance_ended, DATE('2100-01-01')))
    AND is_last_status_of_day = True
),
early_relisting_house_state AS (
  SELECT
      bch.id_house,
      bch.status,
      bch.status_reason,
      bch.suspension_reason,
      bch.ts_state_started,
      bch.ts_state_ended,
      ure.id_user,
      TRUE AS is_early_demand
  FROM
    datalake_ebdb_listing.business_context_history AS bch
  JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure
      ON bch.rev = ure.id
  WHERE
      bch.business_context = 'RENT'
      AND bch.status = 'PUBLISHED'
      AND bch.status_reason LIKE 'RELISTING_%'
      AND bch.suspension_reason = 'RELISTING'
      AND ure.id_user != 4299181 --This filters data inputed by a faulty script. This rule will be replaced in the near future.
), early_relisting_dates AS (
  SELECT 
    hl.id_house_listing,
    hl.id_house,
    hs.status,
    hs.status_reason,
    hs.suspension_reason,
    hs.is_early_demand,
    IF(hs.is_early_demand, hs.ts_state_started, NULL) AS ts_early_demand_started,
    IF(hs.is_early_demand, hs.ts_state_ended, NULL) AS ts_early_demand_ended,
    hs.ts_state_started
  FROM 
    early_relisting_house_state AS hs
  JOIN 
    house_listing AS hl 
      ON hl.id_house = hs.id_house
        AND hs.ts_state_started BETWEEN hl.ts_listing_version_start AND COALESCE(hl.ts_listing_version_end, '2700-01-01')
),
early_relisting_date_selection AS (
  SELECT 
    id_house_listing,
    id_house,
    status,
    status_reason,
    suspension_reason,
    is_early_demand, 
    MIN(ts_early_demand_started) AS ts_early_demand_started,
    MIN(ts_early_demand_ended) AS ts_early_demand_ended
  FROM 
    early_relisting_dates
  GROUP BY 
    id_house_listing,
    id_house,
    status,
    status_reason,
    suspension_reason,
    is_early_demand
), 
house_lbc_state AS (
  SELECT 
    id_house,
    status,
    status_reason,
    suspension_reason,
    ts_state_started,
    ts_state_ended,
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_state_started DESC) AS state_order
  FROM 
    datalake_ebdb_listing.business_context_history 
  WHERE 
    business_context = 'RENT'
),
lbc_early_relisting as (
  SELECT 
  ds.id_house_listing,
  ds.id_house,
  IF(hs.status = 'PUBLISHED' and hs.status_reason = 'RELISTING_OFFER' and hs.suspension_reason = 'RELISTING', TRUE, FALSE) AS is_early_demand,
  MAX(ds.ts_early_demand_started) AS ts_early_demand_started
FROM 
  early_relisting_date_selection AS ds
JOIN house_lbc_state AS hs
  ON hs.id_house = ds.id_house
    AND hs.state_order = 1
GROUP BY 
  1,2, hs.status, hs.status_reason, hs.suspension_reason
)
SELECT
    hl.id_house_listing,
    hl.id_house,
    hl_c.id_contract,
    hl.country_code,
    hl.version,
    hl.status,
    hl.rent,
    hl.listing_category,
    hl.last_originals_type,
    hl.last_iorent_type,
    COUNT(c.id) OVER (PARTITION BY c.id_house) AS nr_renting,
    hl_c.order_renting,
    heh.name AS who_is_living,
    IF(lbcer.id_house_listing is not null, TRUE, FALSE) AS is_early_relisting,
    lbcer.is_early_demand,
    hl.is_last_version,
    hl.is_exclusive,
    hl.is_originals_active,
    hl.is_iorent_active,
    CAST(lbcer.ts_early_demand_started AS TIMESTAMP) AS ts_early_demand_started,
    hl.ts_listing_version_start,
    hl.ts_listing_version_end,
    heh.ts_entrance_started,
    hl.ts_last_unpublished,
    hl.dt_last_exclusive_opted_in,
    hl.dt_last_exclusive_opted_out,
    hl.dt_last_originals_opted_in,
    hl.dt_last_originals_opted_out,
    hl.dt_last_iorent_opted_in,
    hl.dt_last_iorent_opted_out,
    hlsd.dt_stranded,
    c.dt_termination AS dt_contract_annulment,
    c.ts_signed AS ts_contract_signed,
    LEAD(c.ts_signed, 1) OVER (PARTITION BY hl.id_house ORDER BY hl.version) AS ts_next_contract_signed
FROM house_listing AS hl
LEFT JOIN house_listing_latest_contracts AS hl_c
    ON hl.id_house_listing = hl_c.id_house_listing
LEFT JOIN datalake_ebdb_clean.contract AS c
    ON hl_c.id_contract = c.id
LEFT JOIN house_listing_stranded_date AS hlsd
    ON hlsd.id_house_listing = hl.id_house_listing
LEFT JOIN house_entrance_history AS heh
    ON heh.id_house_listing = hl.id_house_listing
    AND heh.is_last_status_in_listing = True
LEFT JOIN lbc_early_relisting AS lbcer
    ON lbcer.id_house_listing = hl.id_house_listing