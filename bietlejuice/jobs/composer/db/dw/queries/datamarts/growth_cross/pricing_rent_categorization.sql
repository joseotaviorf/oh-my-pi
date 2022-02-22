WITH rent_modifications AS (
	SELECT
	    DISTINCT ha.id_house,
	    ha.rev,
	    ha.rent,
	    ha.mod_rent,
	    DATE(ha.dt_first_publication) AS first_publication,
	    DATE(FROM_UNIXTIME(ure.ts_revision/1000)) AS modification,
	    dhl.sk_house_listing,
	    dhl.ts_publication,
	    dhl.ts_listing_version_start,
	    dhl.ts_listing_version_end,
	    dhl.rent AS last_rent
	FROM
        datalake_ebdb_clean_prod.house_aud ha
	LEFT JOIN
        datalake_ebdb_clean_prod.user_revision_entity ure
          ON ure.id = ha.rev
	LEFT JOIN
        dim_house_listing dhl
          ON dhl.id_house = ha.id_house
          AND dhl.version > 0
          AND DATE(FROM_UNIXTIME(ure.ts_revision/1000)) BETWEEN DATE(dhl.ts_listing_version_start) AND COALESCE(DATE(dhl.ts_listing_version_end), current_date)
	WHERE (mod_rent = True
        OR modification = first_publication
        OR modification = DATE(dhl.ts_publication))
),
max_min_modification AS (
	SELECT
	    sk_house_listing,
	    MIN(rev) AS min_rev,
	    MAX(rev) AS max_rev
	FROM
        rent_modifications
	GROUP BY 1
),
pricing_changes AS (
	SELECT
	    aml.id_house,
	    aml.sk_house_listing,
	    MAX(aml.first_publication) AS first_publication,
	    MAX(aml.ts_publication) AS ts_publication,
	    MAX(CASE WHEN min_rev = rev THEN aml.rent END) AS first_rent,
	    MAX(CASE WHEN max_rev = rev THEN last_rent END) AS last_rent,
	    MAX(CASE WHEN min_rev = rev THEN modification END) AS dt_first_modification,
	    MAX(CASE WHEN max_rev = rev THEN modification END) AS dt_last_modification
	FROM
        rent_modifications aml
	LEFT JOIN
        max_min_modification mmm
          ON mmm.sk_house_listing = aml.sk_house_listing
          AND (mmm.min_rev = aml.rev OR mmm.max_rev = aml.rev )
	WHERE mmm.sk_house_listing is not null
	GROUP BY 1, 2
),
houses_infos AS (
	SELECT
	    DISTINCT dhl.id_house,
	    dhl.sk_house_listing,
	    pc.first_publication as dt_first_publication,
	    dhl.ts_publication,
	    dhl.ts_house_first_publication,
	    pc.first_rent,
	    pc.last_rent,
	    dhl.house_rent AS last_rent_dim,
	    pc.dt_last_modification AS dt_last_rent,
	    pc.dt_first_modification AS dt_first_rent,
	    dhl.house_predicted_price,
	    dhl.house_total_area,
	    dhl.house_type,
	    dhl.is_house_furnished
	FROM
        dim_house_listing dhl
	INNER JOIN
        pricing_changes pc
          ON pc.sk_house_listing = dhl.sk_house_listing
	WHERE is_for_rent = true
        AND version > 0
        AND house_total_area > 5
        AND is_b2b <> true
),
regions AS (
    SELECT
        DISTINCT sk_house_listing,
        fl.sk_region,
        dr.macro_name,
        dr.city_name
    FROM
        fact_house_listings fl
    JOIN
        dim_region  dr
          ON dr.sk_region  = fl.sk_region
),
listing_to_rented AS (
    SELECT
        sk_house_listing,
        MIN(days_house_listing_to_contract_signed) AS days_house_listing_to_contract_signed
    FROM fact_listing_rent_flows
    GROUP BY 1
),
listings_info AS (
	SELECT
        hi.*,
        DATE_TRUNC('month', hi.ts_publication) AS month_publication,
        first_rent/house_total_area AS first_price_m2,
        last_rent/house_total_area AS last_price_m2,
        house_predicted_price/house_total_area AS calculator_price_m2,
        reg.sk_region,
        reg.macro_name,
        reg.city_name,
        ltr.days_house_listing_to_contract_signed,
        COUNT(DISTINCT CASE WHEN DATEDIFF(day, hi.ts_publication, dem.dt_event) <= 7 THEN dem.sk_rf END) AS rent_flows_em_7_dias,
        COUNT(DISTINCT CASE WHEN DATEDIFF(day, hi.ts_publication, dem.dt_event) <= 7 THEN dem.sk_booking END) AS visits_booked_in_7_days,
        COUNT(DISTINCT dem.sk_contract) AS contracts_signed,
        AVG(rent) AS avg_rent_contracts_signed,
        avg_rent_contracts_signed/house_total_area AS avg_rent_contracts_signed_m2
	FROM
        houses_infos hi
	LEFT JOIN
        datamarts.performance_marketing_metrics_demand dem
          ON dem.sk_house_listing = hi.sk_house_listing
	LEFT JOIN
        dim_contract dc
          ON dc.sk_contract = dem.sk_contract
    LEFT JOIN
    	listing_to_rented ltr
    	  ON ltr.sk_house_listing = hi.sk_house_listing
	JOIN
        regions reg
          ON reg.sk_house_listing = hi.sk_house_listing
	GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
),
 contracts AS (
    SELECT
        sk_contract,
        rent,
        DATE(ts_signature) AS date_signature
    FROM
        dim_contract
    WHERE ts_signature is not null
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
),
first_predicted_price AS (
    SELECT 
        id_house,
        p_10 AS first_prediction_p_10,
        p_20 AS first_prediction_p_20,
        p_30 AS first_prediction_p_30,
        p_40 AS first_prediction_p_40,
        p_50 AS first_prediction_p_50,
        p_60 AS first_prediction_p_60,
        p_70 AS first_prediction_p_70,
        p_80 AS first_prediction_p_80,
        p_90 AS first_prediction_p_90,
        certainty  AS first_prediction_certainty
    FROM datalake_ebdb_clean_prod.house_predicted_price_aud
    WHERE rev_type = 0 AND business_context = 'RENT'
),
last_predicted_price AS (
    SELECT 
        id_house,
        p_10 AS last_prediction_p_10,
        p_20 AS last_prediction_p_20,
        p_30 AS last_prediction_p_30,
        p_40 AS last_prediction_p_40,
        p_50 AS last_prediction_p_50,
        p_60 AS last_prediction_p_60,
        p_70 AS last_prediction_p_70,
        p_80 AS last_prediction_p_80,
        p_90 AS last_prediction_p_90,
        certainty AS last_prediction_certainty
    FROM datalake_ebdb_clean_prod.house_predicted_price
    WHERE business_context = 'RENT'
)
SELECT
	DISTINCT listings_info.sk_house_listing,
	listings_info.id_house AS sk_house,
	listings_info.dt_first_publication,
	DATE(listings_info.ts_publication) AS dt_publication,
	listings_info.first_rent AS first_rent_price,
	listings_info.last_rent AS last_rent_price,
	listings_info.dt_first_rent,
	CASE
	  WHEN listings_info.dt_last_rent = listings_info.dt_first_rent AND listings_info.first_rent = listings_info.last_rent THEN NULL
	  ELSE listings_info.dt_last_rent
	END AS dt_last_rent,
	CASE
	  WHEN listings_info.dt_last_rent = listings_info.dt_first_rent AND listings_info.first_rent = listings_info.last_rent THEN NULL
	  ELSE DATEDIFF(day, listings_info.ts_publication, listings_info.dt_last_rent)
	END AS days_publication_to_last_price_change,
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
	listings_info.contracts_signed AS listing_contracts_signed,
    listings_info.avg_rent_contracts_signed AS avg_rent_listing_contracts_signed,
    listings_info.avg_rent_contracts_signed_m2 AS avg_rent_listing_contracts_signed_m2,
    listings_info.days_house_listing_to_contract_signed,
	COALESCE(COALESCE(full_match.price_3mon, reg_furn_match.price_3mon), city_furn_match.price_3mon) AS avg_price_contracts_signed_m2,
	COALESCE(COALESCE(full_match.contracts_3mon, reg_furn_match.contracts_3mon), city_furn_match.contracts_3mon) AS total_contracts_compared,
	COALESCE(COALESCE(full_match.match_type, reg_furn_match.match_type), city_furn_match.match_type) AS match_type,
	(listings_info.first_price_m2-avg_price_contracts_signed_m2)*1.0/avg_price_contracts_signed_m2 AS diff_first_listing_contracts,
	fpp.first_prediction_p_10,
	fpp.first_prediction_p_20,
	fpp.first_prediction_p_30,
	fpp.first_prediction_p_40,
	fpp.first_prediction_p_50,
	fpp.first_prediction_p_60,
	fpp.first_prediction_p_70,
	fpp.first_prediction_p_80,
	fpp.first_prediction_p_90,
	fpp.first_prediction_certainty,
	lpp.last_prediction_p_10,
	lpp.last_prediction_p_20,
	lpp.last_prediction_p_30,
	lpp.last_prediction_p_40,
	lpp.last_prediction_p_50,
	lpp.last_prediction_p_60,
	lpp.last_prediction_p_70,
	lpp.last_prediction_p_80,
	lpp.last_prediction_p_90,
	lpp.last_prediction_certainty,
	CASE
	  WHEN listings_info.dt_last_rent = listings_info.dt_first_rent AND listings_info.first_rent = listings_info.last_rent THEN NULL
	  ELSE (listings_info.last_price_m2-avg_price_contracts_signed_m2)*1.0/avg_price_contracts_signed_m2
	END AS diff_last_listing_contracts,
	(listings_info.first_price_m2-calculator_price_m2)*1.0/nullif(calculator_price_m2,0) AS diff_first_listing_calculator,
	CASE
	  WHEN listings_info.dt_last_rent = listings_info.dt_first_rent AND listings_info.first_rent = listings_info.last_rent THEN NULL
	  ELSE (listings_info.last_price_m2-calculator_price_m2)*1.0/nullif(calculator_price_m2,0)
	END AS diff_last_listing_calculator,
	CASE
	  WHEN diff_first_listing_contracts < 0 THEN '1. menor'
	  WHEN diff_first_listing_contracts >= 0 AND diff_first_listing_contracts < 0.05 THEN '2. até 5% maior'
	  WHEN diff_first_listing_contracts >= 0.05 AND diff_first_listing_contracts < 0.1 THEN '3. até 10% maior'
	  WHEN diff_first_listing_contracts >= 0.1 AND diff_first_listing_contracts < 0.15 THEN  '4. até 15% maior'
	  WHEN diff_first_listing_contracts >= 0.15 THEN '5. mais que 15%'
	END AS first_pricing_contracts_group,
	CASE
	  WHEN days_publication_to_last_price_change IS NULL THEN NULL
	  WHEN diff_last_listing_contracts < 0 THEN '1. menor'
	  WHEN diff_last_listing_contracts >= 0 AND diff_last_listing_contracts < 0.05 THEN '2. até 5% maior'
	  WHEN diff_last_listing_contracts >= 0.05 AND diff_last_listing_contracts < 0.1 THEN '3. até 10% maior'
	  WHEN diff_last_listing_contracts >= 0.1 AND diff_last_listing_contracts < 0.15 THEN  '4. até 15% maior'
	  WHEN diff_last_listing_contracts >= 0.15 THEN '5. mais que 15%'
	END AS last_pricing_contract_group,
	CASE
	  WHEN diff_first_listing_calculator < 0 THEN '1. menor'
	  WHEN diff_first_listing_calculator >= 0 AND diff_first_listing_calculator < 0.05 THEN '2. até 5% maior'
	  WHEN diff_first_listing_calculator >= 0.05 AND diff_first_listing_calculator < 0.1 THEN '3. até 10% maior'
	  WHEN diff_first_listing_calculator >= 0.1 AND diff_first_listing_calculator < 0.15 THEN  '4. até 15% maior'
	  WHEN diff_first_listing_calculator >= 0.15 THEN '5. mais que 15%'
	END AS first_pricing_calculator_group,
	CASE
	  WHEN days_publication_to_last_price_change IS NULL THEN NULL
	  WHEN diff_last_listing_calculator < 0 THEN '1. menor'
	  WHEN diff_last_listing_calculator >= 0 AND diff_last_listing_calculator < 0.05 THEN '2. até 5% maior'
	  WHEN diff_last_listing_calculator >= 0.05 AND diff_last_listing_calculator < 0.1 THEN '3. até 10% maior'
	  WHEN diff_last_listing_calculator >= 0.1 AND diff_last_listing_calculator < 0.15 THEN  '4. até 15% maior'
	  WHEN diff_last_listing_calculator >= 0.15 THEN '5. mais que 15%'
	END AS last_pricing_calculator_group
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
LEFT JOIN 
	first_predicted_price fpp
	  ON fpp.id_house = listings_info.id_house
LEFT JOIN 
    	last_predicted_price lpp
	  ON lpp.id_house = listings_info.id_house