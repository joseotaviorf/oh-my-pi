WITH lbc_aud AS (
    SELECT
      i.id_house,
      rev.id_user AS id_user_modified_by,
      COALESCE(i.business_context, 'Undefined') AS business_context,
      LAG(i.status) OVER(PARTITION BY i.id_house, i.business_context ORDER BY i.rev) AS previous_status, -- previous status ordered by the datetime that happened
      i.status,
      LAG(i.status_reason) OVER(PARTITION BY i.id_house, i.business_context ORDER BY i.rev) AS previous_status_reason, -- previous status_reason ordered by the datetime that happened
      i.status_reason,
      LAG(i.suspension_reason) OVER(PARTITION BY i.id_house, i.business_context ORDER BY i.rev) AS previous_suspension_reason, -- previous suspension_reason ordered by the datetime that happened
      i.suspension_reason,
      FROM_UNIXTIME(CAST(rev.ts_revision AS BIGINT)/1000) AS revision_time, 
      i.rev
    FROM 
        datalake_ebdb_clean.listing_business_context_aud AS i
    INNER JOIN 
        datalake_ebdb_clean.user_revision_entity AS rev
          ON rev.id = i.rev
      
),
lbc_history AS (
    SELECT
        id_house,
        id_user_modified_by,
        business_context,
        rev,
        revision_time,
        status,
        status_reason,
        suspension_reason,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY rev) AS event_order
    FROM 
          lbc_aud
    WHERE 
          (
            status <> previous_status 
            OR previous_status IS NULL
          ) 
        OR (
             suspension_reason <> previous_suspension_reason 
             OR (previous_suspension_reason IS NULL AND suspension_reason IS NOT NULL) 
             OR (suspension_reason IS NULL AND previous_suspension_reason IS NOT NULL)
           )
        OR (
             status_reason <> previous_status_reason 
             OR (previous_status_reason IS NULL AND status_reason IS NOT NULL) 
             OR (status_reason IS NULL AND previous_status_reason IS NOT NULL)
           )
)
SELECT 
    lbch.id_house,
    lbch.id_user_modified_by,
    lbch.rev,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    lbch.business_context,
    lbch.status,
    lbch.status_reason,
    lbch.suspension_reason,
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