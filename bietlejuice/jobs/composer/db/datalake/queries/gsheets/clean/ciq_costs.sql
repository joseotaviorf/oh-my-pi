SELECT
    city,
    comission_cs_ciq_full,
    comission_cs_ciq_manager,
    comission_listing,
    comission_listing_fs,
    data,
    impostos,
    month,
    other,
    NULLIF(revshare_cs_ciq_full, ' ') AS revshare_cs_ciq_full,
    NULLIF(revshare_cs_ciq_manager, ' ') AS revshare_cs_ciq_manager,
    NULLIF(total_costs_ciq_full_for_rent, ' ') AS total_costs_ciq_full_for_rent,
    NULLIF(total_costs_ciq_full_for_sale, ' ') AS total_costs_ciq_full_for_sale,
    week_start,
    year
FROM
    datalake_gsheets_raw.ciq_costs