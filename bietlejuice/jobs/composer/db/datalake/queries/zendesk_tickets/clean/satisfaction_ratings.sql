WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_zendesk_tickets_raw.satisfaction_ratings
    GROUP BY 1
)
SELECT 
  sr.id,
  ticket_id AS id_ticket,
  reason_id AS id_reason,
  group_id AS id_group,
  assignee_id AS id_assignee,
  requester_id AS id_requester,
  score,
  url AS satisfaction_rating_url,
  reason,
  CAST(created_at AS TIMESTAMP) AS ts_created,
  CAST(updated_at AS TIMESTAMP) AS ts_updated,
  NOW() AS ts_load,
  YEAR(CAST(sr.updated_at AS DATE)) AS year,
  MONTH(CAST(sr.updated_at AS DATE)) AS month,
  DAY(CAST(sr.updated_at AS DATE)) AS day
FROM 
  datalake_zendesk_tickets_raw.satisfaction_ratings sr
JOIN
    max_stitch_data max_sd
        ON max_sd.id = sr.id
        AND max_sd.max_updated_at = CAST(sr.updated_at AS TIMESTAMP)