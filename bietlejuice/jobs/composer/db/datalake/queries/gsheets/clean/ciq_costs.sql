SELECT
    NULLIF(city, '') AS city,
    FLOAT(NULLIF(comission_cs_ciq_full, '')) AS comission_cs_ciq_full,
    FLOAT(NULLIF(comission_cs_ciq_manager, '')) AS comission_cs_ciq_manager,
    FLOAT(NULLIF(comission_listing, '')) AS comission_listing,
    FLOAT(NULLIF(comission_listing_fs, '')) AS comission_listing_fs,
    FLOAT(NULLIF(impostos, '')) AS impostos,
    FLOAT(NULLIF(other, '')) AS other,
    FLOAT(NULLIF(revshare_cs_ciq_full, '')) AS revshare_cs_ciq_full,
    FLOAT(NULLIF(revshare_cs_ciq_manager, '')) AS revshare_cs_ciq_manager,
    FLOAT(NULLIF(total_costs_ciq_full_for_rent, '')) AS total_costs_ciq_full_for_rent,
    FLOAT(NULLIF(total_costs_ciq_full_for_sale, '')) AS total_costs_ciq_full_for_sale,
    DATE(data) AS data,
    DATE(week_start) AS week_start,
    NULLIF(year, '') AS year,
    NULLIF(month, '') AS month
FROM
    datalake_gsheets_raw.ciq_costs