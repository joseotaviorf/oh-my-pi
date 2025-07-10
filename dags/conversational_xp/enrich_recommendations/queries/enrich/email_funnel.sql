WITH email_recommendation AS (
SELECT
    sk_user_dispatch AS id_email,
    sk_user AS id_user,
    CASE
        WHEN
            (
                LOWER(campaign_name) LIKE "%dailyfeed%"
                OR LOWER(campaign_name) LIKE "%daily-feed%"
                /*
                  The following is a temporary solution for the change in recent campaign names.
                  The long-term solution will be to define a standard naming scheme for campaigns
                  such as personalization.<BUSINESS_CONTEXT>.<DISPLAY_TYPE>.<EXPERIMENT>.<VARIANT>
                */
                OR campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm%"
            )
            THEN "daily_feed"
        WHEN
            (LOWER(campaign_name) LIKE "%favorites%")
            THEN "favorites_campaign"
    END AS display_type,
    CASE
        WHEN
            LOWER(campaign_name) LIKE "%rent%" THEN "rent"
        WHEN LOWER(campaign_name) LIKE "%sale%" THEN "sale"
    END AS business_context,
    DATE(ts_email_sent) AS dt_email_sent,
    MAX(ts_email_sent) AS ts_email_sent,
    MAX(DATE(ts_email_delivered)) AS dt_email_delivered,
    MAX(ts_email_delivered) AS ts_email_delivered,
    MAX(DATE(ts_email_first_opened)) AS dt_email_first_opened,
    MAX(ts_email_first_opened) AS ts_email_first_opened,
    MAX(DATE(ts_email_first_clicked)) AS dt_email_first_clicked,
    MAX(ts_email_first_clicked) AS ts_email_first_clicked
FROM dw_braze.fact_campaign_user_dispatch AS fact_campaign_user_dispatch
INNER JOIN
    dw_braze.dim_campaign AS dim_campaign
    ON dim_campaign.sk_campaign = fact_campaign_user_dispatch.sk_campaign
WHERE
    event_channel = "email"
    AND (
        LOWER(campaign_name) LIKE "%dailyfeed%"
        OR LOWER(campaign_name) LIKE "%daily-feed%"
        OR LOWER(campaign_name) LIKE "%favorites%"
        -- Temporary workaround for recent changes on campaign names
        OR campaign_name LIKE "%NEW[CAMPAIGNS.DEMAND] forsale.listing.7day.similar_algorithm%"
    )
    AND DATE(ts_email_sent) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')

GROUP BY id_email, id_user, display_type, business_context, DATE(ts_email_sent)
),

yellow_pages_recommendation_logs_dedup AS (

WITH yellow_pages_recommendation_logs AS (
  SELECT
      id_user,
      business_context,
      display_type,
      experiments,
      experiments_variants,
      ts_log,
      dt_log,
      min(ts_log) Over (PARTITION BY id_user, business_context, display_type, dt_log) AS min_ts_log
  FROM (
      SELECT
          CAST(
              GET_JSON_OBJECT(emlio_logs.inputs, "$.user_id") as string
          ) AS id_user,
          LOWER(
              GET_JSON_OBJECT(
                  emlio_logs.inputs, "$.business_context"
              )
          ) AS business_context,
          LOWER(
              GET_JSON_OBJECT(emlio_logs.inputs, "$.display_type")
          ) AS display_type,
          -- Multiple experiments can be active at the same time
          MAP_KEYS(
            FROM_JSON(
              GET_JSON_OBJECT(inputs, "$.experiment_settings"), "map<string, string>"
            )
          ) AS experiments,
          MAP_VALUES(
            from_json(
              GET_JSON_OBJECT(inputs, "$.experiment_settings"), "map<string, string>"
            )
          ) AS experiments_variants,
          DATE(ts_log) AS dt_log,
          ts_log
      FROM datalake_emlio_clean.emlio_logs AS emlio_logs
      WHERE
          emlio_logs.id_service = "yellow-pages"
          AND MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
  )
)
SELECT DISTINCT *
FROM
    yellow_pages_recommendation_logs
WHERE
    min_ts_log = ts_log
)

SELECT
    r.display_type,
    r.business_context,
    yp.experiments,
    yp.experiments_variants,
    r.dt_email_sent,
    SUM(CASE WHEN ts_email_sent IS NOT NULL THEN 1 ELSE 0 END) AS emails_sent,
    SUM(CASE WHEN dt_email_delivered IS NOT NULL THEN 1 ELSE 0 END) AS  emails_delivered,
    SUM(CASE WHEN dt_email_first_opened IS NOT NULL THEN 1 ELSE 0 END) AS  emails_opened,
    SUM(CASE WHEN dt_email_first_clicked IS NOT NULL THEN 1 ELSE 0 END) AS  emails_clicked
FROM
    email_recommendation AS r
LEFT JOIN
    yellow_pages_recommendation_logs_dedup yp
    ON r.display_type = yp.display_type
        AND r.business_context = yp.business_context
        AND r.dt_email_sent = yp.dt_log
        AND r.id_user = yp.id_user
GROUP BY
    r.display_type, r.business_context, yp.experiments, yp.experiments_variants, r.dt_email_sent
