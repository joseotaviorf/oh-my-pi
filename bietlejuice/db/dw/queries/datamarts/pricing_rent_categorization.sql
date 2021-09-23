WITH min_rev_house AS (
    SELECT
        ha.id_house,
        MIN(rev) min_rev
    FROM
        datalake_ebdb_clean_prod.house_aud ha
    WHERE ha.rent > 0
        AND dt_first_publication  >= '2021-01-01'
    GROUP BY 1
),
min_price_houses AS (
    SELECT
        DISTINCT ha.id_house,
        ha.dt_first_publication,
        ha.rent
    FROM
        min_rev_house min
    INNER JOIN
        datalake_ebdb_clean_prod.house_aud ha
          ON ha.rev = min_rev
          AND min.id_house = ha.id_house
),
houses_infos AS (
	SELECT
	    DISTINCT min.id_house,
	    min.dt_first_publication,
	    dhl.ts_house_first_publication,
	    min.rent AS first_rent,
	    dhl.house_rent AS last_rent,
	    dhl.house_predicted_price,
	    dhl.house_total_area,
	    dhl.house_type,
	    dhl.is_house_furnished
	FROM
        dim_house_listing dhl
	INNER JOIN
        min_price_houses min
          ON min.id_house = dhl.id_house
	WHERE is_for_rent = true
        AND version > 0
        AND house_total_area > 5
        AND is_b2b <> true
),
regions AS (
    SELECT
        DISTINCT sk_house_listing/1000 AS id_house,
        fl.sk_region,
        dr.macro_name,
        dr.city_name
    FROM
        fact_house_listings fl
    JOIN
        dim_region  dr
          ON dr.sk_region  = fl.sk_region
),
listings_info AS (
	SELECT
        hi.*,
        DATE_TRUNC('month', hi.dt_first_publication) AS month_publication,
        first_rent/house_total_area AS first_price_m2,
        last_rent/house_total_area AS last_price_m2,
        house_predicted_price/house_total_area AS calculator_price_m2,
        reg.sk_region,
        reg.macro_name,
        reg.city_name,
        COUNT(DISTINCT sk_rf) AS rent_flows_em_7_dias,
        COUNT(DISTINCT sk_booking) AS visits_booked_in_7_days,
        COUNT(DISTINCT dem.sk_contract) AS contracts_signed_from_7_days_events,
        AVG(rent) AS avg_rent_contracts_signed_from_7_days_events,
        avg_rent_contracts_signed_from_7_days_events/house_total_area AS avg_rent_contracts_signed_from_7_days_events_m2
	FROM
        houses_infos hi
	LEFT JOIN
        datamarts.performance_marketing_metrics_demand dem
          ON dem.id_house = hi.id_house
          AND DATEDIFF(day, hi.dt_first_publication, dem.dt_event) <= 7
	LEFT JOIN
        dim_contract dc
          ON dc.sk_contract = dem.sk_contract
	JOIN
        regions reg
          ON reg.id_house = hi.id_house
	GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
),
contracts AS (
    SELECT
        sk_contract,
        rent,
        DATE(ts_signature) AS date_signature
    FROM
        dim_contract
    WHERE ts_signature >= '2020-09-01'
),
contract_base AS (
    SELECT
        c.sk_contract,
        f.sk_house_listing,
        LEFT(f.sk_house_listing,9) AS sk_house,
        f.sk_region,
        dr.city_name,
        dr.macro_name,
        c.rent,
        DATE_TRUNC('month', date_signature) AS month,
        d.is_house_furnished,
        d.house_predicted_price,
        d.house_rent,
        d.house_total_area,
        d.house_type,
        c.rent/d.house_total_area AS price_m2
    FROM
        fact_listing_rent_flows f
    INNER JOIN
        contracts c
          ON c.sk_contract = f.sk_contract
    JOIN
        dim_house_listing d
          ON d.sk_house_listing = f.sk_house_listing
    JOIN
        dim_region  dr
          ON dr.sk_region  = f.sk_region
    WHERE house_total_area > 5
        AND is_b2b <> true
),
contracts_full_match AS (
    SELECT
        month,
        macro_name,
        house_type,
        is_house_furnished,
        AVG(price_m2) AS avg_contracts_price_m2,
        COUNT(DISTINCT sk_contract) AS amount_contracts
    FROM
        contract_base
    GROUP BY 1, 2, 3, 4
),
contracts_full_match_avg AS (
    SELECT
        *,
        'region_type_furniture'::VARCHAR AS match_type,
        AVG(avg_contracts_price_m2) OVER (PARTITION BY macro_name,house_type,is_house_furnished ORDER BY macro_name,house_type,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS price_3mon,
        SUM(amount_contracts) OVER (PARTITION BY macro_name,house_type,is_house_furnished ORDER BY macro_name,house_type,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS contracts_3mon
    FROM
        contracts_full_match
),
contracts_region_furn_match AS (
    SELECT
        month,
        macro_name,
        is_house_furnished,
        AVG(price_m2) AS avg_contracts_price_m2,
        COUNT(DISTINCT sk_contract) AS amount_contracts
    FROM
        contract_base
    GROUP BY 1, 2, 3
),
contracts_region_furn_match_avg AS (
    SELECT
        *,
        'region_furniture'::VARCHAR AS match_type,
        AVG(avg_contracts_price_m2) OVER (PARTITION BY macro_name,is_house_furnished ORDER BY macro_name,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS price_3mon,
        SUM(amount_contracts) OVER (PARTITION BY macro_name,is_house_furnished ORDER BY macro_name,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS contracts_3mon
    FROM
        contracts_region_furn_match
),
contracts_city_furn_match AS (
    SELECT
        month,
        city_name,
        is_house_furnished,
        AVG(price_m2) AS avg_contracts_price_m2,
        COUNT(DISTINCT sk_contract) AS amount_contracts
    FROM
        contract_base
    GROUP BY 1, 2, 3
),
contracts_city_furn_match_avg AS (
    SELECT
        *,
        'city_furniture'::VARCHAR AS match_type,
        AVG(avg_contracts_price_m2) OVER (PARTITION BY city_name,is_house_furnished ORDER BY city_name,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS price_3mon,
        SUM(amount_contracts) OVER (PARTITION BY city_name,is_house_furnished ORDER BY city_name,is_house_furnished, month  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS contracts_3mon
    FROM
        contracts_city_furn_match
)
SELECT
	DISTINCT listings_info.id_house AS sk_house,
	listings_info.dt_first_publication,
	listings_info.first_rent AS first_rent_price,
	listings_info.last_rent AS last_rent_price,
	listings_info.house_predicted_price AS calculator_price,
	listings_info.house_total_area,
	listings_info.house_type,
	listings_info.is_house_furnished,
	listings_info.first_price_m2,
	listings_info.last_price_m2,
	listings_info.calculator_price_m2,
	dr.city_name,
	dr.city_group,
	dr.name AS region_name,
	listings_info.rent_flows_em_7_dias AS rent_flows_in_7_days,
	listings_info.visits_booked_in_7_days,
	COALESCE(COALESCE(full_match.price_3mon, reg_furn_match.price_3mon), city_furn_match.price_3mon) AS avg_price_contracts_signed_m2,
	COALESCE(COALESCE(full_match.contracts_3mon, reg_furn_match.contracts_3mon), city_furn_match.contracts_3mon) AS total_contracts_compared,
	COALESCE(COALESCE(full_match.match_type, reg_furn_match.match_type), city_furn_match.match_type) AS match_type,
	(listings_info.first_price_m2-avg_price_contracts_signed_m2)*1.0/avg_price_contracts_signed_m2 AS diff_listing_contracts,
	CASE
	  WHEN diff_listing_contracts < 0 THEN '1. menor'
	  WHEN diff_listing_contracts >= 0 AND diff_listing_contracts < 0.05 THEN '2. até 5% maior'
	  WHEN diff_listing_contracts >= 0.05 AND diff_listing_contracts < 0.1 THEN '3. até 10% maior'
	  WHEN diff_listing_contracts >= 0.1 AND diff_listing_contracts < 0.15 THEN  '4. até 15% maior'
	  WHEN diff_listing_contracts >= 0.15 THEN '5. mais que 15%'
	END AS pricing_group
FROM
	listings_info
LEFT JOIN
	dim_region  dr
	  ON dr.sk_region  = listings_info.sk_region
LEFT JOIN
	contracts_full_match_avg full_match
	  ON full_match.month = listings_info.month_publication
	  AND full_match.macro_name = listings_info.macro_name
	  AND full_match.house_type = listings_info.house_type
	  AND full_match.is_house_furnished = listings_info.is_house_furnished
	  AND full_match.contracts_3mon  >= 5
LEFT JOIN
	contracts_region_furn_match_avg reg_furn_match
	  ON reg_furn_match.month = listings_info.month_publication
	  AND reg_furn_match.macro_name = listings_info.macro_name
	  AND reg_furn_match.is_house_furnished = listings_info.is_house_furnished
	  AND reg_furn_match.contracts_3mon  >= 5
LEFT JOIN
	contracts_city_furn_match_avg city_furn_match
	  ON city_furn_match.month = listings_info.month_publication
	  AND city_furn_match.city_name = listings_info.city_name
	  AND city_furn_match.is_house_furnished = listings_info.is_house_furnished