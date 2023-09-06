WITH condos AS (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY dt_created) AS id,
        MD5(CONCAT(
            COALESCE(INITCAP(address_type || ' ' || address), 'N/A'), 
            COALESCE(number, 'N/A'),
            COALESCE(neighborhood, 'N/A'),
            COALESCE(zipcode, 'N/A'),
            COALESCE(city, 'N/A')
        )) AS id_address,
        INITCAP(condo_name) AS condo,
        condo_cnpj AS cnpj,
        INITCAP(address_type || ' ' || address) AS address,
        number,
        neighborhood,
        zipcode AS zip_code,
        city,
        state,
        CASE has_elevator
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_elevator,
        CASE has_entrance_hall
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_entrance_hall,
        CASE has_grill_area
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_grill_area,
        CASE has_swim_pool
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_swim_pool,
        CASE has_sports_court
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_sports_court,
        CASE has_gym
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_gym,
        CASE has_party_hall
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_party_hall,
        CASE has_sauna
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_sauna,
        CASE has_laundry
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_laundry,
        CASE has_piped_gas
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_piped_gas,
        CASE has_gourmet_area
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_gourmet_area,
        CASE has_metro_or_train_close
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_metro_or_train_close,
        CASE has_toy_library
            WHEN 'Sim' THEN TRUE
            WHEN 'Não' THEN FALSE
            ELSE NULL
        END AS has_toy_library,
        dt_created AS ts_updated
    FROM
        datalake_gsheets_clean.vespucio_condo_golden_set
)
SELECT
    c.id,
    d.id_dejavu,
    c.id_address,
    d.id_region,
    c.condo,
    c.cnpj,
    c.address,
    c.number,
    c.neighborhood,
    c.zip_code,
    c.city,
    c.state,
    d.latitude AS lat,
    d.longitude AS lng,
    c.has_elevator,
    c.has_entrance_hall,
    c.has_grill_area,
    c.has_swim_pool,
    c.has_sports_court,
    c.has_gym,
    c.has_party_hall,
    c.has_sauna,
    c.has_laundry,
    c.has_piped_gas,
    c.has_gourmet_area,
    c.has_metro_or_train_close,
    c.has_toy_library,
    c.ts_updated
FROM 
    condos AS c
LEFT JOIN 
    datalake_vespucio.dejavu AS d
        USING (id_address)