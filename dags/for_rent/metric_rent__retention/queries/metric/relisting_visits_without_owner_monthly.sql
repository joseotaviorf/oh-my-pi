WITH
early_demand_ended_rentals AS (
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
eligibility_rules AS (
    SELECT DISTINCT
        hl.ts_listing_version_start,
        CASE
            WHEN hl.rent < 1500 THEN 'LOW'
            WHEN hl.rent < 2500 THEN 'MEDIUM'
            ELSE 'HIGH'
        END AS value_segment,
        hl.country_code,
        CASE
            WHEN hl.first_key_location IN ('OwnerPresent','None') OR hl.first_key_location IS NULL THEN
                (CASE
                    WHEN hldi.doorman_type IN ('horas24', 'Diurno') AND (hldi.id_occupant IS NULL OR hldi.id_occupant IN (1, 4)) THEN 'PP Acompanha - Elegível Com Portaria'
                    WHEN hldi.doorman_type NOT IN ('horas24', 'Diurno') AND hldi.is_for_sale = FALSE AND (hldi.id_occupant IS NULL OR hldi.id_occupant IN (1, 4)) THEN 'PP Acompanha - Elegível CRCC'
                    ELSE 'PP Acompanha - Não Elegível'
                END)
            ELSE 'Entrada Facilitada'
        END AS eligibility,
        CASE
            WHEN hldi4w_ed.id_house_listing IS NOT NULL THEN (
                CASE
                    WHEN COALESCE(hldi4w_ed.key_location, hl.key_location) IN ('OwnerPresent', 'None') OR COALESCE(hldi4w_ed.key_location, hl.key_location) IS NULL THEN
                        (CASE
                            WHEN COALESCE(hldi4w_ed.doorman_type, hl.house_entrance) IN ('horas24', 'Diurno') AND (COALESCE(CAST(hldi4w_ed.id_occupant AS STRING), hl.who_is_living) IS NULL OR COALESCE(CAST(hldi4w_ed.id_occupant AS STRING), hl.who_is_living) IN ('1', '4', 'None', 'Empty')) THEN 'PP Acompanha - Elegível Com Portaria'
                            WHEN COALESCE(hldi4w_ed.doorman_type, hl.house_entrance) not IN ('horas24', 'Diurno') AND COALESCE(hldi4w_ed.is_for_sale, hl.is_for_sale) = FALSE AND (COALESCE(CAST(hldi4w_ed.id_occupant AS STRING), hl.who_is_living) IS NULL OR COALESCE(CAST(hldi4w_ed.id_occupant AS STRING), hl.who_is_living) IN ('1', '4', 'None', 'Empty')) THEN 'PP Acompanha - Elegível CRCC'
                            ELSE 'PP Acompanha - Não Elegível'
                        END)
                    ELSE 'Entrada Facilitada'
                END)
            WHEN hldi4w_ed.id_house_listing IS NULL THEN (
                CASE
                    WHEN COALESCE(hldi4w.key_location, hl.key_location) IN ('OwnerPresent', 'None') OR COALESCE(hldi4w.key_location, hl.key_location) IS NULL THEN
                    (CASE
                        WHEN COALESCE(hldi4w.doorman_type, hl.house_entrance) IN ('horas24', 'Diurno') AND (COALESCE(CAST(hldi4w.id_occupant AS STRING), hl.who_is_living) IS NULL OR COALESCE(CAST(hldi4w.id_occupant AS STRING), hl.who_is_living) IN ('1', '4', 'None', 'Empty')) THEN 'PP Acompanha - Elegível Com Portaria'
                        WHEN COALESCE(hldi4w.doorman_type, hl.house_entrance) not IN ('horas24', 'Diurno') AND COALESCE(hldi4w.is_for_sale, hl.is_for_sale) = FALSE AND (COALESCE(CAST(hldi4w.id_occupant AS STRING), hl.who_is_living) IS NULL OR COALESCE(CAST(hldi4w.id_occupant AS STRING), hl.who_is_living) IN ('1', '4', 'None', 'Empty')) THEN 'PP Acompanha - Elegível CRCC'
                        ELSE 'PP Acompanha - Não Elegível'
                    END)
                ELSE 'Entrada Facilitada'
                END)
        END AS eligibility_4w,
        COUNT(DISTINCT hl.sk_house_listing) AS listings
    FROM
        dw_rent.dim_house_listing AS hl
    LEFT JOIN
        early_demand_ended_rentals AS erc
            ON erc.ed_sk_house_listing = hl.sk_house_listing
    LEFT JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
            ON hldi.year = YEAR(hl.ts_listing_version_start)
            AND hldi.month = MONTH(hl.ts_listing_version_start)
            AND hldi.day = DAY(hl.ts_listing_version_start)
            AND hldi.id_house_listing = hl.sk_house_listing
    LEFT JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi4w
            ON hldi4w.year = YEAR(DATEADD(WEEK, 4, hl.ts_listing_version_start))
            AND hldi4w.month = MONTH(DATEADD(WEEK, 4, hl.ts_listing_version_start))
            AND hldi4w.day = DAY(DATEADD(WEEK, 4, hl.ts_listing_version_start))
            AND hldi4w.id_house_listing = hl.sk_house_listing
    LEFT JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi4w_ed
            ON hldi4w_ed.year = YEAR(DATEADD(WEEK, 4, erc.dt_erc))
            AND hldi4w_ed.month = MONTH(DATEADD(WEEK, 4, erc.dt_erc))
            AND hldi4w_ed.day = DAY(DATEADD(WEEK, 4, erc.dt_erc))
            AND hldi4w_ed.id_house_listing = erc.ed_sk_house_listing
    WHERE
        hl.listing_category_start = 'Re-Listing'
    GROUP BY
      1, 2, 3, 4, 5
),
calculations AS (
    SELECT
        DATE(DATE_TRUNC('MONTH', ts_listing_version_start)) AS dt_reference_month,
        value_segment,
        country_code,
        SUM(IF(eligibility = 'Entrada Facilitada', listings, 0)) AS qtd_easy_entry,
        SUM(IF(eligibility <>'PP Acompanha - Não Elegível', listings, 0)) AS qtd_pp_not_eligible,
        SUM(IF(eligibility_4w = 'Entrada Facilitada', listings, 0)) AS qtd_easy_entry_4w,
        SUM(IF(eligibility_4w = 'Entrada Facilitada' AND ts_listing_version_start <= DATE_ADD(CURRENT_DATE(), -28), listings, 0)) AS qtd_easy_entry_matured_4w,
        SUM(IF(eligibility_4w <>'PP Acompanha - Não Elegível', listings, 0)) AS qtd_pp_not_eligible_4w,
        SUM(IF(eligibility_4w <>'PP Acompanha - Não Elegível' AND ts_listing_version_start <= DATE_ADD(CURRENT_DATE(), -28), listings, 0)) AS qtd_pp_not_eligible_matured_4w,
        SUM(IF(eligibility_4w = 'Entrada Facilitada',listings, 0)) / SUM(IF(eligibility_4w <>'PP Acompanha - Não Elegível', listings, 0))*1.0 conversao_4w
    FROM
        eligibility_rules
    GROUP BY
        1, 2, 3
)

SELECT
    dt_reference_month,
    value_segment,
    country_code,
    qtd_easy_entry,
    qtd_pp_not_eligible,
    qtd_easy_entry / qtd_pp_not_eligible AS pct_rl_easy_entry,
    qtd_easy_entry_4w,
    qtd_pp_not_eligible_4w,
    qtd_easy_entry_4w / qtd_pp_not_eligible_4w AS pct_rl_easy_entry_4w,
    qtd_easy_entry_matured_4w,
    qtd_pp_not_eligible_matured_4w,
    qtd_easy_entry_matured_4w / qtd_pp_not_eligible_matured_4w AS pct_rl_easy_entry_matured_4w
FROM
    calculations

UNION ALL

SELECT
    dt_reference_month,
    'OVERALL' AS value_segment,
    country_code,
    SUM(qtd_easy_entry) AS qtd_easy_entry,
    SUM(qtd_pp_not_eligible) AS qtd_pp_not_eligible,
    SUM(qtd_easy_entry) / SUM(qtd_pp_not_eligible) AS pct_rl_easy_entry,
    SUM(qtd_easy_entry_4w) AS qtd_easy_entry_4w,
    SUM(qtd_pp_not_eligible_4w) AS qtd_pp_not_eligible_4w,
    SUM(qtd_easy_entry_4w) / SUM(qtd_pp_not_eligible_4w) AS pct_rl_easy_entry_4w,
    SUM(qtd_easy_entry_matured_4w) AS qtd_easy_entry_matured_4w,
    SUM(qtd_pp_not_eligible_matured_4w) AS qtd_pp_not_eligible_matured_4w,
    SUM(qtd_easy_entry_matured_4w) / SUM(qtd_pp_not_eligible_matured_4w) AS pct_rl_easy_entry_matured_4w
FROM
    calculations
GROUP BY
    1, 2, 3