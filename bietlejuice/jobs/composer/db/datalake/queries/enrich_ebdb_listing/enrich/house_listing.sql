WITH house_aud as (
--------------------------------------------------------------------------------------------------------
-- Bring to IMOVEL_AUD datetime for each revision made                                                --
-- Also creates previous_status column so we can identify status changes                              --
-- (status_MOD = 1 may not work sometimes)                                                            --
--------------------------------------------------------------------------------------------------------
    select
        cast(from_unixtime(cast(rev.ts_revision as bigint)/1000) as timestamp) as revision_time,
        cast(from_unixtime(cast(rev.ts_revision as bigint)/1000) as date) as status_date,
        rev.id_user,
        rev.reason,
        lag(h.status) over(partition by h.id_house order by h.rev) as previous_status,
        lag(h.rent) over(partition by h.id_house order by h.rev) as previous_rent_price,
        h.status,
        h.rent,
        h.id_house,
        h.rev,
        h.mod_status,
        h.mod_rent,
        h.dt_first_publication
    from datalake_ebdb_clean.house_aud h
    inner join datalake_ebdb_clean.user_revision_entity rev
        on rev.id = h.rev
),
max_status_order as (
--------------------------------------------------------------------------------------------------------
-- Identify the last status to each version                                                           --
--------------------------------------------------------------------------------------------------------
    select
        id_house,
        order_version,
        max(order_status) as max_order_status
    from datalake_ebdb_listing.house_status_version_order
    group by id_house, order_version
),
house_status_version_last_status as (
    select
        hs_vo.*,
        max(
        case
            when hs_vo.status_history_new = 'despublicado'
            then ts_status_changed_new
        end
        ) over(partition by hs_vo.id_house, hs_vo.order_version) as ts_last_unpublished,
        case when ms_o.max_order_status is not null then hs_vo.status_history_new end as last_status,
        max(hs_vo.order_status) over(partition by hs_vo.id_house, hs_vo.order_version) as max_order_status_version
    from datalake_ebdb_listing.house_status_version_order hs_vo
    left join max_status_order ms_o
        on hs_vo.id_house = ms_o.id_house
        and hs_vo.order_version = ms_o.order_version
        and hs_vo.order_status = ms_o.max_order_status
),
status_change_version as (
--------------------------------------------------------------------------------------------------------
-- Identify the status that made it changes to a new version                                          --
-- This status is important to define which category the listing will have                            --
--------------------------------------------------------------------------------------------------------
    select
        id_house,
        order_version,
        max(events_change_status) as category_change
    from house_status_version_last_status
    where events_change_status is not null
    group by 1, 2
),
house_listing_plain as (
--------------------------------------------------------------------------------------------------------
-- Create listings column according to version                                                        --
-- Create column to identify category (using column from join with status_change_version              --
-- Keep only the version changes                                                                      --
--------------------------------------------------------------------------------------------------------
    select
        hs_v.id_house,
        hs_v.order_version as version,
        sc_v.category_change as change_version_status,
        hs_v.ts_last_unpublished,
        max(status_history) as status_history,
        max(ts_status_changed) as ts_status_changed,
        max(hs_v.last_status) as status,
        min(cast(hs_v.publication_version_date as timestamp)) as ts_listing_version_start,
        max(coalesce(hs_v.ts_status_changed_next, cast('2200-01-01 12:00:00' as timestamp))) as ts_listing_version_end
    from  house_status_version_last_status hs_v
    left join status_change_version sc_v
        on hs_v.id_house = sc_v.id_house
        and hs_v.order_version = sc_v.order_version
    group by 1, 2, 3, 4
),
house_listing_full as (
--------------------------------------------------------------------------------------------------------
-- Create category                                                                                    --
--------------------------------------------------------------------------------------------------------
    select
        cast(cast(id_house as string)||'00'||cast(version as string) as bigint) as id_house_listing,
        id_house,
        version,
        case when version = 0 then null
             when version = 1 then 'First Listing'
             when version <> 0 and lag(change_version_status) over(partition by id_house order by version) = 'alugado' then 'Re-Listing'
             when version <> 0 and lag(change_version_status) over(partition by id_house order by version) in ('despublicado') then 'Recovered'
        else null end as listing_category,
        status,
        status_history,
        ts_status_changed,
        ts_listing_version_start,
        nullif(cast(ts_listing_version_end as timestamp), cast('2200-01-01 12:00:00' as timestamp)) as ts_listing_version_end,
        ts_last_unpublished
    from house_listing_plain
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
        sc.special_condition_type,
        max(sc.dt_opted_in) as dt_opted_in,
        max(sc.dt_opted_out) as dt_opted_out
    from house_listing_full hl
    join special_conditions sc
        on hl.id_house = sc.id_house
        and greatest(sc.dt_opted_in, date(hl.ts_listing_version_start)) >= date(hl.ts_listing_version_start)
        and greatest(sc.dt_opted_in, date(hl.ts_listing_version_start)) < coalesce(date(hl.ts_listing_version_end), date(now() - interval '1' day))
        and greatest(coalesce(sc.dt_opted_out, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= coalesce(date(hl.ts_listing_version_end), date(now() - interval '1' day))
        and greatest(coalesce(sc.dt_opted_out, date(now() - interval '1' day)), coalesce(date(hl.ts_listing_version_end), date((now() - interval '1' day)))) >= date(hl.ts_listing_version_start)
    group by 1, 2
),
multiple_special_conditions as (
-- in case a house listing has more than one Special Condition types: exclusivity, ready and reno on the same version
    select
        id_house_listing,
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
        special_condition_type,
        dt_opted_in,
        dt_opted_out
    from multiple_special_conditions
    where rn_first = 1
),
listing_special_conditions_dates as (
    select
        fo.id_house_listing,
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
    join datalake_ebdb_contract.contract c
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
      ORDER BY hls.id_house_listing DESC, hls.ts_status_started
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
    ORDER BY id_house_listing desc, ts_status_started
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
    ORDER BY id_house_listing DESC
),
house_listing_stranded_date AS (
    SELECT
        DISTINCT id_house_listing,
        CASE
            WHEN GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01') as TIMESTAMP), min_ts_to_be_stranded) = '3000-01-01'
            THEN NULL
            ELSE GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01')  as TIMESTAMP), min_ts_to_be_stranded)
        END AS dt_stranded
    FROM house_listing_stranded_status
    WHERE rn = 1
)
select
  hl.*,
  hl_c.id_contract,
  count(c.id) over (partition by c.id_house) as nr_renting,
  hl_c.order_renting,
  hlsd.dt_stranded,
  c.dt_termination as dt_contract_annulment,
  c.ts_signed as ts_contract_signed,
  lead(c.ts_signed, 1) over (partition by hl.id_house order by hl.version) as ts_next_contract_signed
from house_listing hl
left join house_listing_latest_contracts hl_c
  on hl.id_house_listing = hl_c.id_house_listing
left join datalake_ebdb_contract.contract c
  on hl_c.id_contract = c.id
left join house_listing_stranded_date hlsd
    ON hlsd.id_house_listing = hl.id_house_listing