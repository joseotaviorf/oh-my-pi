WITH lead_base AS (
  SELECT
    house_lead.id_lead_ebdb,
    acquisition.acquisition_campaign
  FROM datalake_rene_descartes_clean.house_lead
  INNER JOIN datalake_rene_descartes_clean.acquisition_misc_data AS acquisition
    ON house_lead.id_acquisition = acquisition.id
  WHERE
    DATE(house_lead.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),

device_ids_from_linked AS (
  SELECT
    id_lead_ebdb AS lead_id,
    EXPLODE(FROM_JSON(GET_JSON_OBJECT(acquisition_campaign, '$.profileTracking.linked_devices'), 'ARRAY<STRING>')) AS device_id
  FROM lead_base
)

SELECT
  lead.lead_id,
  tracking.device_id,
  tracking.attribution_time,
  tracking.gclid,
  tracking.utm_term,
  tracking.utm_source,
  tracking.utm_medium,
  tracking.utm_content,
  tracking.utm_campaign,
  tracking.ts_event,
  tracking.year,
  tracking.month,
  tracking.day
FROM device_ids_from_linked AS lead
INNER JOIN datalake_attribution.tracking_by_device_id AS tracking
  ON tracking.device_id = lead.device_id
