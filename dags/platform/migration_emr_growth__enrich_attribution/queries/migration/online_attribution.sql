WITH lead_base AS (
  SELECT
    house_lead.id_lead_ebdb AS id_lead,
    house_lead.ts_created AS ts_created,
    GET_JSON_OBJECT(acquisition_misc_data.acquisition_campaign, '$.deviceId') AS root_id_device,
    EXPLODE(
      FROM_JSON(
        COALESCE(
          GET_JSON_OBJECT(acquisition_misc_data.acquisition_campaign, '$.profileTracking.linked_devices'),
          '[null]'
        ),
        'ARRAY<STRING>'
      )
    ) AS id_device /* It's necessary to use COALESCE to handle the case where the linked_devices array is null and results */ /* in no lines instead of a line with a null id_device */
  FROM datalake_rene_descartes_clean.house_lead AS house_lead
  INNER JOIN datalake_rene_descartes_clean.acquisition_misc_data AS acquisition_misc_data
    ON house_lead.id_acquisition = acquisition_misc_data.id
  WHERE
    CAST(house_lead.ts_created AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
), lead_devices AS (
  SELECT
    id_lead,
    ts_created,
    id_device
  FROM lead_base
  WHERE
    NOT id_device IS NULL
  UNION
  SELECT
    id_lead,
    ts_created,
    root_id_device AS id_device
  FROM lead_base
  WHERE
    NOT root_id_device IS NULL
)
SELECT
  id_lead,
  id_device,
  utm_source,
  utm_medium,
  utm_campaign,
  utm_content,
  utm_term,
  ts_utm_attribution_start,
  ts_utm_attribution_end
FROM (
  SELECT
    lead_devices.id_lead,
    tracking.id_device,
    tracking.utm_source,
    tracking.utm_medium,
    tracking.utm_campaign,
    tracking.utm_content,
    tracking.utm_term,
    tracking.ts_utm_attribution_start,
    tracking.ts_utm_attribution_end,
    ROW_NUMBER() OVER (PARTITION BY lead_devices.id_lead ORDER BY tracking.ts_utm_attribution_start DESC) AS _w
  FROM lead_devices
  INNER JOIN datalake_attribution.tracking_by_device AS tracking
    ON tracking.id_device = lead_devices.id_device
    AND tracking.ts_utm_attribution_start <= lead_devices.ts_created
) AS _t
WHERE
  _w = 1
