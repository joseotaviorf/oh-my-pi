-- Table to analyse house states based on status and status_reason attributes
WITH lbc_aud AS (
    SELECT
      i.id_house,
      COALESCE(i.business_context, 'Undefined') AS business_context,
      LAG(i.status) OVER(PARTITION BY i.id_house, i.business_context ORDER BY i.rev) AS previous_status, -- previous status ordered by the datetime that happened
      i.status,
      LAG(i.status_reason) OVER(PARTITION BY i.id_house, i.business_context ORDER BY i.rev) AS previous_status_reason,
      i.status_reason,
      rev.ts_revision AS revision_time,
      i.rev,
      i.ts_first_publication,
      i.ts_last_publication
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS i
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS rev
          ON rev.id = i.rev

),
lbc_history AS (
    SELECT
        id_house,
        business_context,
        rev,
        revision_time,
        status,
        status_reason,
        ts_first_publication,
        ts_last_publication,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY rev) AS event_order,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context, DATE(revision_time) ORDER BY rev DESC) = 1 AS is_last_state_of_day
    FROM
          lbc_aud
    WHERE
          (
            status <> previous_status
            OR previous_status IS NULL
          )
        OR (
             status_reason <> previous_status_reason
             OR (previous_status_reason IS NULL AND status_reason IS NOT NULL)
             OR (status_reason IS NULL AND previous_status_reason IS NOT NULL)
           )
)
SELECT
    lbch.id_house,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    COALESCE(NULLIF(lbch.business_context, ''), 'Undefined') AS business_context,
    lbch.status,
    lbch.status_reason,
    lbch.is_last_state_of_day,
    lbch.ts_first_publication,
    lbch.ts_last_publication,
    lbch.revision_time AS ts_state_started,
    lbch2.revision_time AS ts_state_ended
FROM
    lbc_history AS lbch
LEFT JOIN
    lbc_history AS lbch2
        ON lbch2.id_house = lbch.id_house
        AND lbch2.business_context = lbch.business_context
        AND lbch.event_order = lbch2.event_order - 1
LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = lbch.id_house
