SELECT
    NULLIF(city, '') AS city,
    NULLIF(comission_cs_ciq_full, '') AS comission_cs_ciq_full,
    NULLIF(comission_cs_ciq_manager, '') AS comission_cs_ciq_manager,
    NULLIF(comission_listing, '') AS comission_listing,
    NULLIF(comission_listing_fs, '') AS comission_listing_fs,
    NULLIF(data, '')::DATE AS data,
    NULLIF(impostos, '') AS impostos,
    NULLIF(month, '') AS month,
    NULLIF(other, '') AS other,
    NULLIF(revshare_cs_ciq_full, '') AS revshare_cs_ciq_full,
    NULLIF(revshare_cs_ciq_manager, '') AS revshare_cs_ciq_manager,
    NULLIF(total_costs_ciq_full_for_rent, '') AS total_costs_ciq_full_for_rent,
    NULLIF(total_costs_ciq_full_for_sale, '') AS total_costs_ciq_full_for_sale,
    NULLIF(week_start, '') AS week_start,
    NULLIF(year, '') AS year
FROM
    datalake_gsheets_raw.ciq_costs