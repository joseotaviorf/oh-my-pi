WITH daily_page_metrics AS (
  SELECT
    PARSE_URL(page, 'PATH') AS page_id,
    dt_created,
    SUM(COALESCE(clicks, 0)) AS clicks,
    SUM(COALESCE(impressions, 0)) AS impressions,
    SUM(COALESCE(posimp, 0)) AS posimp
  FROM
    datalake_google_search_console_clean.report_by_page
  WHERE
    dt_created BETWEEN DATE_ADD(DATE('{load_end_date}'), -89)
      AND DATE('{load_end_date}')
    AND MAKE_DATE(year, month, day) BETWEEN DATE_ADD(
      DATE('{load_end_date}'),
      -89
    )
      AND DATE('{load_end_date}')
    AND site_url = 'https://www.quintoandar.com.br'
    AND type = 'WEB'
    AND country = 'bra'
    AND page RLIKE 'quintoandar\\.com\\.br/(comprar|alugar)/imovel/'
  GROUP BY
    PARSE_URL(page, 'PATH'),
    dt_created
),
window_totals AS (
  SELECT
    page_id,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -6)
          THEN clicks
        ELSE 0
      END
    ) AS gsc_7d_click,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -6)
          THEN impressions
        ELSE 0
      END
    ) AS gsc_7d_impression,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -6)
          THEN posimp
        ELSE 0
      END
    ) AS gsc_7d_posimp,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -29)
          THEN clicks
        ELSE 0
      END
    ) AS gsc_30d_click,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -29)
          THEN impressions
        ELSE 0
      END
    ) AS gsc_30d_impression,
    SUM(
      CASE
        WHEN dt_created >= DATE_ADD(DATE('{load_end_date}'), -29)
          THEN posimp
        ELSE 0
      END
    ) AS gsc_30d_posimp,
    SUM(clicks) AS gsc_90d_click,
    SUM(impressions) AS gsc_90d_impression,
    SUM(posimp) AS gsc_90d_posimp
  FROM
    daily_page_metrics
  GROUP BY
    page_id
)
SELECT
  page_id,
  gsc_7d_click,
  gsc_7d_impression,
  CASE
    WHEN gsc_7d_impression > 0
      THEN ROUND(gsc_7d_click / gsc_7d_impression, 8)
    ELSE 0.0
  END AS gsc_7d_ctr,
  CASE
    WHEN gsc_7d_impression > 0
      THEN ROUND(gsc_7d_posimp / gsc_7d_impression, 8)
    ELSE 0.0
  END AS gsc_7d_position,
  gsc_7d_posimp,
  gsc_30d_click,
  gsc_30d_impression,
  CASE
    WHEN gsc_30d_impression > 0
      THEN ROUND(gsc_30d_click / gsc_30d_impression, 8)
    ELSE 0.0
  END AS gsc_30d_ctr,
  CASE
    WHEN gsc_30d_impression > 0
      THEN ROUND(gsc_30d_posimp / gsc_30d_impression, 8)
    ELSE 0.0
  END AS gsc_30d_position,
  gsc_30d_posimp,
  gsc_90d_click,
  gsc_90d_impression,
  CASE
    WHEN gsc_90d_impression > 0
      THEN ROUND(gsc_90d_click / gsc_90d_impression, 8)
    ELSE 0.0
  END AS gsc_90d_ctr,
  CASE
    WHEN gsc_90d_impression > 0
      THEN ROUND(gsc_90d_posimp / gsc_90d_impression, 8)
    ELSE 0.0
  END AS gsc_90d_position,
  gsc_90d_posimp,
  DATE('{load_end_date}') AS ref_date
FROM
  window_totals
