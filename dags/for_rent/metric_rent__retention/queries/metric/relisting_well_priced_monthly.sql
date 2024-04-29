WITH
ed_ended_rentals AS (
    SELECT
        dhl.sk_house_listing AS ed_sk_house_listing,
        dhl.id_house,
        COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment) AS dt_erc
    FROM
        dw_retention.fact_owner_retention AS fct
    JOIN
        dw_rent.dim_house_listing AS dhl
          ON dhl.sk_house_listing = fct.sk_house_listing + 1
    JOIN
        dw_rent.dim_contract AS dc
            ON dc.sk_contract = fct.sk_contract
    WHERE
        dhl.ts_early_demand_started IS NOT NULL
        AND dc.status = 'Finalizado'
), 
rev_base AS (
    SELECT
        r.id_house,
        r.rev,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_revision,
        r.p_90,
        r.certainty
    FROM
        datalake_ebdb_clean.house_predicted_price_aud AS r
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = r.rev
    WHERE
        r.business_context = 'RENT'
), 
pub_rev_base AS ( -- Last calculator revision before listing publication - Not Early Demand
    select
        dhl.sk_house_listing,
        MAX(r.rev) AS rev
    FROM
        dw_rent.dim_house_listing AS dhl
    LEFT JOIN
        rev_base AS r
            ON r.id_house = dhl.id_house
              AND DATE(r.ts_revision) <= DATE(dhl.ts_listing_version_start)
    WHERE
        dhl.ts_early_demand_started IS NULL
    GROUP BY
      1
), 
four_week_rev_base AS ( -- Last calculator revision 4 weeks after listing publication - Not Early Demand
    SELECT
        dhl.sk_house_listing,
        MAX(r.rev) AS rev
    FROM
        dw_rent.dim_house_listing AS dhl
    LEFT JOIN
        rev_base AS r
            ON r.id_house = dhl.id_house
              AND DATE(r.ts_revision) <= DATEADD(WEEK, 4, dhl.ts_listing_version_start)
    WHERE
        dhl.ts_early_demand_started IS NULL
    GROUP BY
      1
), 
ed_four_week_rev_base AS ( -- Last calculator revision 4 weeks after ended rental of the house - Early Demand
    SELECT
        erc.ed_sk_house_listing,
        MAX(r.rev) AS rev
    FROM
        ed_ended_rentals AS erc
    LEFT JOIN
        rev_base AS r
            ON r.id_house = erc.id_house
              AND DATE(r.ts_revision) <= DATE(DATEADD(WEEK, 4, erc.dt_erc))
    GROUP BY
      1
),
db AS (
  SELECT DISTINCT
      DATE(DATE_TRUNC('MONTH', hl.ts_listing_version_start)) AS dt_month_reference,
      hl.country_code,
      hl.listing_category_start,
      aud.certainty,
      IF(
        hldi.rent > aud.p_90
        , TRUE
        , FALSE
      ) AS is_mispriced_p90,
      IF(
        erc.ed_sk_house_listing IS NOT NULL
        , aud_fw_ed.certainty
        , aud_fw.certainty
      ) AS certainty_4w,
      IF(
        erc.ed_sk_house_listing IS NOT NULL
        ,IF(
          COALESCE(hldi4w_ed.rent, hl.rent) > aud_fw_ed.p_90
          , TRUE
          , FALSE
        )
        ,IF(
          COALESCE(hldi4w.rent, hl.rent) > aud_fw.p_90
          , TRUE
          , FALSE
        )
      ) AS is_mispriced_4w_p90,
      COUNT(DISTINCT hl.sk_house_listing) AS listings
  FROM
      dw_rent.dim_house_listing AS hl
  LEFT JOIN
      ed_ended_rentals AS erc
          ON erc.ed_sk_house_listing = hl.sk_house_listing
    LEFT JOIN
      datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
          ON hldi.year = YEAR(hl.ts_listing_version_start)
            AND hldi.month = MONTH(hl.ts_listing_version_start)
            AND hldi.day = DAY(hl.ts_listing_version_start)
            AND hldi.id_house_listing = hl.sk_house_listing
  LEFT JOIN
      datalake_rental_historical_follow_up.house_listings_daily_info AS hldi4w
          ON hldi4w.year = YEAR(DATE(DATEADD(WEEK, 4, hl.ts_listing_version_start)))
            AND hldi4w.month = MONTH(DATE(DATEADD(WEEK, 4, hl.ts_listing_version_start)))
            AND hldi4w.day = DAY(DATE(DATEADD(WEEK, 4, hl.ts_listing_version_start)))
            AND hldi4w.id_house_listing = hl.sk_house_listing
  LEFT JOIN
      datalake_rental_historical_follow_up.house_listings_daily_info AS hldi_ed
          ON hldi_ed.year = YEAR(erc.dt_erc)
            AND hldi_ed.month = MONTH(erc.dt_erc)
            AND hldi_ed.day = DAY(erc.dt_erc)
            AND hldi_ed.id_house_listing = ed_sk_house_listing
  LEFT JOIN
      datalake_rental_historical_follow_up.house_listings_daily_info AS hldi4w_ed
          ON hldi4w_ed.year = YEAR(DATE(DATEADD(WEEK, 4, erc.dt_erc)))
            AND hldi4w_ed.month = MONTH(DATE(DATEADD(WEEK, 4, erc.dt_erc)))
            AND hldi4w_ed.day = DAY(DATE(DATEADD(WEEK, 4, erc.dt_erc)))
            ANd hldi4w_ed.id_house_listing = erc.ed_sk_house_listing
  LEFT JOIN
      pub_rev_base AS prb
          ON prb.sk_house_listing = hl.sk_house_listing
  LEFT JOIN
      four_week_rev_base AS fwrb
          ON fwrb.sk_house_listing = hl.sk_house_listing        
  LEFT JOIN
      datalake_ebdb_clean.house_predicted_price_aud AS aud
          ON aud.rev = prb.rev
            AND aud.business_context = 'RENT'
  LEFT JOIN
      datalake_ebdb_clean.house_predicted_price_aud AS aud_fw
          ON aud_fw.rev = fwrb.rev
            AND aud_fw.business_context = 'RENT'
  LEFT JOIN
      ed_four_week_rev_base AS edfwrb
          ON edfwrb.ed_sk_house_listing = hl.sk_house_listing        
  LEFT JOIN
      datalake_ebdb_clean.house_predicted_price_aud AS aud_fw_ed
          ON aud_fw_ed.rev = edfwrb.rev
            AND aud_fw_ed.business_context = 'RENT'
  WHERE
      hl.id_house NOT IN (
        SELECT DISTINCT
          aud.id_house
        FROM
          datalake_ebdb_clean.listing_business_context_aud AS aud
        INNER JOIN
          datalake_ebdb_user.user_revision_entity AS r
            ON r.id = aud.rev
              AND r.id_user = 2879298
              AND DATE(r.ts_revision) BETWEEN DATE('2024-03-15') AND DATE('2024-03-16') 
        WHERE
          mod_status = '1'
          AND status = 'PUBLISHED'
      )
  GROUP BY 
    1,2,3,4,5,6,7
)

SELECT 
    dt_month_reference,
    country_code,
    CAST(
      SUM(
        IF(
          is_mispriced_p90 = FALSE 
          AND (certainty = 'MEDIUM' OR certainty = 'HIGH') 
          AND listing_category_start = 'Re-Listing'
          , listings
          , 0
        )
      ) AS DOUBLE 
    ) 
    / 
    SUM(
      IF( 
        (certainty = 'MEDIUM' OR certainty = 'HIGH') 
        AND listing_category_start = 'Re-Listing'
        , listings
        , 0
      )
    ) * 1.0 AS pct_well_priced,
    CAST(
      SUM(
        IF( 
          is_mispriced_4w_p90 = FALSE 
          AND (certainty_4w = 'MEDIUM' OR certainty_4w = 'HIGH') 
          AND listing_category_start = 'Re-Listing'
          , listings
          , 0
        )
      ) AS DOUBLE 
    ) 
    / 
    SUM(
      IF( 
        (certainty_4w = 'MEDIUM' OR certainty_4w = 'HIGH') 
        AND listing_category_start = 'Re-Listing'
        , listings
        , 0
      )
    ) * 1.0 AS pct_well_priced_4w
FROM 
    db
GROUP BY 
    1, 2