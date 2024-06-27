WITH  
house_aud AS (
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
        LAG(h.status) OVER(PARTITION BY h.id_house ORDER BY h.rev) AS previous_status,
        LAG(h.rent) OVER(PARTITION BY h.id_house ORDER BY h.rev) AS previous_rent_price,
        h.status,
        h.rent,
        h.id_house,
        h.rev,
        h.mod_status,
        h.mod_rent,
        h.dt_first_publication,
        rev.reason AS revision_reason
    FROM
      datalake_ebdb_clean.house_aud AS h
    INNER JOIN 
      datalake_ebdb_clean.user_revision_entity AS rev
        ON rev.id = h.rev
),
house_rent_history AS (
--------------------------------------------------------------------------------------------------------------------
-- Create rent_price_history: for each house show all rent price changes, with start and end of each rent price   --
--------------------------------------------------------------------------------------------------------------------
    SELECT
      id_house,
      rev,
      mod_rent,
      revision_time AS ts_rent_price_changed,
      rent AS rent_price_history,
      LEAD(revision_time) OVER(PARTITION BY id_house ORDER BY rev) AS ts_next_rent_price_change,
      ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY rev) AS order_rent_price,
      MAX(revision_time) OVER(PARTITION BY id_house) AS max_ts_rent_price_changed
    FROM
      house_aud
    WHERE
      (rent <> previous_rent_price OR previous_rent_price IS NULL)
),
house_rent_max AS (
    SELECT
        hlf.id_house_listing,
        hlf.id_house,
        hlf.country_code,
        hlf.version,
        rh.rev,
        rh.rent_price_history,
        rh.order_rent_price,
        MAX(rh.order_rent_price) OVER(PARTITION BY hlf.id_house, hlf.version) AS max_order_status_version
    FROM
      datalake_ebdb_listing.house_listing_category AS hlf
    JOIN
      house_rent_history rh
        ON hlf.id_house = rh.id_house
          AND ((rh.ts_rent_price_changed BETWEEN hlf.ts_listing_version_start AND COALESCE(hlf.ts_listing_version_end - INTERVAL '1' SECOND, CURRENT_TIMESTAMP))
          OR (COALESCE(rh.ts_next_rent_price_change,CURRENT_TIMESTAMP) BETWEEN hlf.ts_listing_version_start and COALESCE(hlf.ts_listing_version_end - INTERVAL '1' SECOND, CURRENT_TIMESTAMP))
          OR (rh.max_ts_rent_price_changed <= hlf.ts_listing_version_start))
),
listing_rent_last AS (
    SELECT
      id_house_listing,
      MAX(CASE WHEN max_order_status_version = order_rent_price THEN rent_price_history END) AS rent
    FROM 
      house_rent_max
    GROUP BY 1
),
last_opt AS (
-- select the latest Special Condition type a house listing has entered
    SELECT
      id_house_listing,
      country_code,
      special_condition_type,
      dt_opted_in,
      dt_opted_out
    FROM 
      datalake_ebdb_listing.house_listing_special_conditions
    WHERE
      rn_last_special_condition = 1
),
first_opt AS (
-- select the oldest Special Condition type a house listing has entered
    SELECT
      id_house_listing,
      country_code,
      special_condition_type,
      dt_opted_in,
      dt_opted_out
    FROM
      datalake_ebdb_listing.house_listing_special_conditions
    WHERE
      rn_first_special_condition = 1
),
listing_special_conditions_dates AS (
    SELECT
      fo.id_house_listing,
      fo.country_code,
      lo.special_condition_type, -- important to select special_condition_type from last_op since we want to show LAST special condition type
      fo.dt_opted_in AS dt_first_opted_in,
      fo.dt_opted_out AS dt_first_opted_out,
      lo.dt_opted_in AS dt_last_opted_in,
      lo.dt_opted_out AS dt_last_opted_out
    FROM 
      last_opt AS lo
    JOIN 
      first_opt AS fo
        ON lo.id_house_listing = fo.id_house_listing
        AND (CASE
              WHEN lo.special_condition_type LIKE 'Originals%' THEN 'Originals'
              WHEN lo.special_condition_type LIKE '%Rent' THEN 'ioRent'
              ELSE lo.special_condition_type
            END) =
            (CASE
              WHEN fo.special_condition_type LIKE 'Originals%' THEN 'Originals'
              WHEN fo.special_condition_type LIKE '%Rent' THEN 'ioRent'
              ELSE fo.special_condition_type
            END)
),
sale AS (
  SELECT 
    lbc.*,
    COALESCE(ch.country_code, 'Undefined') AS country_code
  FROM 
    datalake_ebdb_clean.listing_business_context AS lbc
  LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = lbc.id_house
  WHERE 
    lbc.business_context = 'SALE'
), 
sale_only AS (
  SELECT 
    sale.*
  FROM
    sale
  LEFT JOIN 
    datalake_ebdb_listing.lbc_status_version_order AS lbc_version
      ON lbc_version.id_house = sale.id_house
  WHERE 
    lbc_version.id_house IS NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY sale.id_house ORDER BY sale.ts_updated DESC) = 1
),
house_listing AS (
    SELECT
      CAST(CAST(sa.id_house AS STRING)||'000' AS BIGINT) AS id_house_listing,
      sa.id_house,
      sa.country_code,
      0 AS version,
      sa.status,
      sa.status_reason,
      NULL AS revision_reason,
      NULL AS rent,
      NULL AS listing_category,
      NULL AS last_originals_type,
      NULL AS last_iorent_type,
      TRUE AS is_last_version,
      FALSE AS is_exclusive,
      FALSE AS is_extended_rental,
      FALSE AS is_brokerage_only_decommissioned,
      FALSE AS is_originals_active,
      FALSE AS is_iorent_active,
      sa.ts_created AS ts_listing_version_start,
      NULL AS ts_listing_version_end,
      NULL AS ts_last_unpublished,
      NULL AS dt_last_exclusive_opted_in,
      NULL AS dt_last_exclusive_opted_out,
      NULL AS dt_last_originals_opted_in,
      NULL AS dt_last_originals_opted_out,
      NULL AS dt_last_iorent_opted_in,
      NULL AS dt_last_iorent_opted_out
    FROM
      sale_only AS sa

    UNION ALL

    SELECT
        hl.id_house_listing,
        hl.id_house,
        hl.country_code,
        hl.version,
        hl.status,
        hl.status_reason,
        hl.revision_reason,
        rent_last.rent,
        hl.listing_category,
        lsc_originals.special_condition_type AS last_originals_type,
        lsc_iorent.special_condition_type AS last_iorent_type,
        hl.version = MAX(hl.version) OVER (PARTITION BY hl.id_house) AS is_last_version,
        lsc_exclusivity.dt_first_opted_in IS NOT NULL AS is_exclusive,
        hl.is_extended_rental,
        hl.is_brokerage_only_decommissioned,
        ((lsc_originals.dt_last_opted_in IS NOT NULL and lsc_originals.dt_last_opted_out IS NULL)
            OR (lsc_originals.dt_last_opted_in > lsc_originals.dt_last_opted_out)) AS is_originals_active,
        ((lsc_iorent.dt_last_opted_in IS NOT NULL and lsc_iorent.dt_last_opted_out IS NULL)
            OR (lsc_iorent.dt_last_opted_in > lsc_iorent.dt_last_opted_out)) AS is_iorent_active,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end,
        ts_last_unpublished,
        lsc_exclusivity.dt_last_opted_in AS dt_last_exclusive_opted_in,
        lsc_exclusivity.dt_last_opted_out AS dt_last_exclusive_opted_out,
        lsc_originals.dt_last_opted_in AS dt_last_originals_opted_in,
        lsc_originals.dt_last_opted_out AS dt_last_originals_opted_out,
        lsc_iorent.dt_last_opted_in AS dt_last_iorent_opted_in,
        lsc_iorent.dt_last_opted_out AS dt_last_iorent_opted_out
    FROM
      datalake_ebdb_listing.house_listing_category AS hl
    LEFT JOIN
      listing_special_conditions_dates AS lsc_originals
        ON hl.id_house_listing = lsc_originals.id_house_listing
        AND lsc_originals.special_condition_type LIKE 'Originals%'
    LEFT JOIN
      listing_special_conditions_dates AS lsc_exclusivity
        ON hl.id_house_listing = lsc_exclusivity.id_house_listing
        AND lsc_exclusivity.special_condition_type = 'Exclusivity'
    LEFT JOIN
      listing_special_conditions_dates AS lsc_iorent
        ON hl.id_house_listing = lsc_iorent.id_house_listing
        AND lsc_iorent.special_condition_type LIKE '%Rent'
    LEFT JOIN
      listing_rent_last AS rent_last
        ON hl.id_house_listing = rent_last.id_house_listing
),
house_listing_latest_contracts AS (
----------------------------------------------------------------------------------------------------------
-- Include information related to contracts (including only active or ended contracts) for each listing --
----------------------------------------------------------------------------------------------------------
    SELECT
      hl.id_house_listing,
      MAX(c.id) AS id_contract,
      DENSE_RANK() OVER (PARTITION BY hl.id_house ORDER BY hl.id_house_listing) AS order_renting
    FROM
      house_listing AS hl
    JOIN
      datalake_ebdb_clean.contract AS c
        ON hl.id_house = c.id_house
          AND c.ts_signed BETWEEN COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, CURRENT_DATE)
          AND c.status IN ('Ativo', 'Finalizado')
    GROUP BY 1, hl.id_house
),
house_listing_stranded_status_all AS (
    --select all status FROM each listing, calculate date_to_be_stranded using publication_date AND find IN which status was the stranded date
    SELECT
        hls.id_house_listing,
        hls.status_history,
        hls.status_change_reason AS status_reason,
        hls.ts_status_started,
        COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 day)) AS ts_status_ended,
        hl.ts_listing_version_start,
        (hl.ts_listing_version_start + INTERVAL 8 WEEK) AS ts_to_be_stranded,
        CASE
            WHEN (hl.ts_listing_version_start + INTERVAL 8 WEEK) <= hls.ts_status_started
              OR (hl.ts_listing_version_start + INTERVAL 8 WEEK) <= COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 day))
            THEN 'stranded'
        END AS type_stranded,
        LAG(hls.status_history) OVER(PARTITION BY hls.id_house_listing ORDER BY hls.ts_status_started, COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_status_history,
        LAG(hls.status_change_reason) OVER(PARTITION BY hls.id_house_listing ORDER BY hls.ts_status_started, COALESCE(hls.ts_status_ended, (CURRENT_TIMESTAMP - INTERVAL 1 DAY))) AS previous_status_reason
    FROM 
      datalake_ebdb_listing.house_listing_status AS hls
    LEFT JOIN 
      house_listing AS hl
        ON hls.id_house_listing = hl.id_house_listing
),
house_listing_stranded_rank_stranded AS (
    --select only status WHERE stranded date already happened
    SELECT
        id_house_listing,
        status_history,
        status_reason,
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
                      AND status_history IN ('publicado','suspenso','edicao','aguardando_publicacao', 'PUBLISHED', 'SUSPENDED', 'EDITING')
                                  AND (
                                      (previous_status_history <> 'alugado' AND 
                                        (previous_status_history <> 'SUSPENDED' AND previous_status_reason <> 'RENTED')
                                      ) OR previous_status_history IS NULL)
                 THEN ts_status_started END) OVER (PARTITION BY id_house_listing) AS min_ts_valid_status,
        MIN(CASE WHEN type_stranded = 'stranded' THEN ts_to_be_stranded END) OVER (PARTITION BY id_house_listing) AS min_ts_to_be_stranded
    FROM 
      house_listing_stranded_status_all
    WHERE 
      type_stranded IS NOT NULL
),
house_listing_stranded_status AS (
    SELECT
        *,
        CASE
          WHEN rn = 1 AND status_history = 'alugado' OR (status_history = 'SUSPENDED' AND status_reason = 'RENTED') THEN NULL
          WHEN rn = 1 AND status_history IN ('despublicado','excluido', 'UNPUBLISHED')
            THEN MIN(min_ts_valid_status) OVER (PARTITION BY id_house_listing)
          WHEN rn = 1 AND status_history IN ('publicado','suspenso','edicao','aguardando_publicacao', 'PUBLISHED', 'SUSPENDED', 'EDITING') AND status_reason <> 'RENTED'
            THEN MIN(min_ts_valid_status) OVER (PARTITION BY id_house_listing)
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
    FROM 
      house_listing_stranded_rank_stranded
),
house_listing_stranded_date AS (
    SELECT
      DISTINCT id_house_listing,
      CASE
          WHEN GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01') AS TIMESTAMP), CAST(min_ts_to_be_stranded AS TIMESTAMP)) = '3000-01-01'
          THEN NULL
          ELSE GREATEST(CAST(COALESCE(min_ts_stranded,'3000-01-01') AS TIMESTAMP), CAST(min_ts_to_be_stranded AS TIMESTAMP))
      END AS dt_stranded
    FROM 
      house_listing_stranded_status
    WHERE 
      rn = 1
),
house_entrance_history AS (
  SELECT
        hl.id_house_listing,
        ot.name,
        hl.version,
        MAX(heh.rev) OVER(PARTITION BY hl.id_house_listing) = heh.rev AS is_last_status_in_listing,
        heh.ts_entrance_started
  FROM 
    datalake_ebdb_listing.house_entrance_history AS heh
  LEFT JOIN 
    datalake_ebdb_clean.occupant_type AS ot
      ON ot.id = heh.id_occupant
  JOIN 
    house_listing AS hl
      ON heh.id_house = hl.id_house
        AND (heh.ts_entrance_started BETWEEN COALESCE(hl.ts_listing_version_start, DATE('1922-01-01')) AND COALESCE(hl.ts_listing_version_end, DATE('2100-01-01'))
        OR COALESCE(hl.ts_listing_version_start, DATE('1922-01-01')) BETWEEN heh.ts_entrance_started AND COALESCE(heh.ts_entrance_ended, DATE('2100-01-01')))
        AND is_last_status_of_day = TRUE
),
first_publication AS (
  SELECT
    id_house,
    CAST(MIN(ts_state_started) AS TIMESTAMP) AS ts_first_publication
  FROM
    datalake_ebdb_listing.lbc_status_version_order
  WHERE
    status IN ('PUBLISHED', 'publicado')
  GROUP BY
    id_house
)
SELECT
    hl.id_house_listing,
    hl.id_house,
    hl_c.id_contract,
    hl.country_code,
    hl.version,
    hl.status,
    hl.status_reason,
    CASE
      WHEN
        hl.status = 'SUSPENDED' 
        AND status_reason = 'RENTED' 
        AND hl.revision_reason = 'TERMINATION_CANCELED'
      THEN 'OLD_CONTRACT_RESUMED'
      WHEN
        (
          hl.status = 'SUSPENDED' 
          AND status_reason = 'RENTED' 
          AND (hl.revision_reason <> 'TERMINATION_CANCELED' OR hl.revision_reason IS NULL)
        )
        OR hl.status = 'alugado'
      THEN 'NEW_CONTRACT_STARTED'
      ELSE 'NOT_RENTED'
    END AS rent_type,
    hl.rent,
    hl.listing_category,
    hl.last_originals_type,
    hl.last_iorent_type,
    COUNT(c.id) OVER (PARTITION BY c.id_house) AS nr_renting,
    hl_c.order_renting,
    heh.name AS who_is_living,
    IF(hled.id_house_listing IS NOT NULL, TRUE, FALSE) AS is_early_relisting,
    hled.is_early_demand,
    hl.is_last_version,
    hl.is_exclusive,
    hl.is_extended_rental,
    hl.is_brokerage_only_decommissioned,
    hl.is_originals_active,
    hl.is_iorent_active,
    CAST(hled.ts_early_demand_started AS TIMESTAMP) AS ts_early_demand_started,
    hl.ts_listing_version_start,
    hl.ts_listing_version_end,
    fp.ts_first_publication,
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
FROM 
  house_listing AS hl
LEFT JOIN 
  house_listing_latest_contracts AS hl_c
    ON hl.id_house_listing = hl_c.id_house_listing
LEFT JOIN 
  datalake_ebdb_clean.contract AS c
    ON hl_c.id_contract = c.id
LEFT JOIN 
  house_listing_stranded_date AS hlsd
    ON hlsd.id_house_listing = hl.id_house_listing
LEFT JOIN 
  house_entrance_history AS heh
    ON heh.id_house_listing = hl.id_house_listing
      AND heh.is_last_status_in_listing = True
LEFT JOIN 
  datalake_ebdb_listing.house_listing_early_demand AS hled
    ON hled.id_house_listing = hl.id_house_listing
LEFT JOIN 
  first_publication AS fp
    ON fp.id_house = hl.id_house