WITH house as (
  WITH source_data AS (
    SELECT
      id AS id_house,
      status AS status_origin,
      CAST(dt_creation - INTERVAL '3' HOUR AS DATE) AS dt_creation,
      city,
      zipcode,
      address,
      number,
      neighborhood,
      complement AS complemento_bruto,
      address || ', ' || number || CASE WHEN complement IS NULL OR complement = '' THEN '' ELSE ', ' || complement END || ' - ' || neighborhood || ' - ' || city || ' - ' || zipcode AS address_full
    FROM datalake_ebdb_clean.house
  ),        
  normalized_input AS (
    SELECT
        id_house,
        status_origin,
        dt_creation,
        address_full,
        city,
        zipcode,
        address,
        number,
        neighborhood,
        complemento_bruto,
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        LOWER(
                            TRANSLATE(
                                COALESCE(complemento_bruto, ''),
                                'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
                                'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
                            )
                        ),
                        '[^a-z0-9\\s]', ' '
                    ),
                    '\\b(de|da|das|do|dos)\\b', ' '
                ),
                '\\s+', ' '
            )
        ) AS norm
    FROM 
      source_data
  ),
  classified_complements AS (
    SELECT
      id_house,
      status_origin,
      dt_creation,
      address_full,
      city,
      zipcode,
      address,
      number,
      neighborhood,
      complemento_bruto,
      norm,
      CASE
        WHEN regexp_like(norm,'(bloco|torre|bl|blc|b|t|tr)\\s*unic(o|a)\\b') THEN 'regra_bloco_unico'
        WHEN regexp_like(TRIM(norm), '^\\d+$') THEN 'regra_apenas_numeros'
        WHEN regexp_like(TRIM(norm),'^\\b(casa|cs|csa|c|cobertura|sobrado|garden)\\b$') THEN 'regra_apenas_casa'
        WHEN regexp_like(TRIM(norm),'^\\b(casa|cs|csa|c|cobertura|sobrado|garden)\\b\\s+(frente|fundos?|cima|baixo)$') THEN 'regra_casa_dir'
        WHEN regexp_like(norm, '^\\b(casa|cs|csa|c|cobertura|sobrado|garden)\\b\\s+(\\d+)$') THEN 'regra_casa_numero'
        WHEN regexp_like(TRIM(norm),'^\\b(casa|cs|csa|c|cobertura|sobrado|garden)\\b\\s+([a-z])$') THEN 'regra_casa_letra'
        WHEN regexp_like(TRIM(norm),'^\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9][a-z0-9 ]*)\\s+\\b(apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b\\s+(\\d+)$') THEN 'regra_m1'
        WHEN regexp_like(TRIM(norm),'^\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9][a-z0-9 ]*)\\s+(\\d+)$') THEN 'regra_m2'
        WHEN regexp_like(TRIM(norm),'^\\b(apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b\\s+(\\d+)\\s+\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9][a-z0-9 ]*)$') THEN 'regra_m3'
        WHEN regexp_like(TRIM(norm),'^(\\d+)\\s+\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9][a-z0-9 ]*)$') THEN 'regra_m4'
        WHEN regexp_like(TRIM(norm),'^(\\d+)\\s*(bloco|torre|bl|blc|b|t|tr)\\s*([0-9a-z])\\s*$') THEN 'regra_m_nb'
        WHEN regexp_like(TRIM(norm), '^(\\d+[a-z]|[a-z]\\d+)$') THEN 'regra_letra_numero'
        WHEN regexp_like(TRIM(norm), '^\\d+\\s+[a-z]$') THEN 'regra_numero_letra_separada'
        WHEN regexp_like(norm,'\\b(apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b\\s*(\\d+)') THEN 'regra_fallback_apt'
        WHEN regexp_like(norm,'\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s*([0-9a-z]+)') THEN 'regra_fallback_bloco'
        WHEN regexp_like(norm, '(\\d+)') THEN 'regra_fallback_numero'        
        ELSE 'sem_regra'
      END AS matching_rule
    FROM 
      normalized_input
  ),        
  base_raw as (
      SELECT
        id_house,
        status_origin,
        dt_creation,
        address_full,
        city,
        zipcode,
        address,
        number,
        neighborhood,
        complemento_bruto,
        matching_rule,
        CASE
          WHEN matching_rule = 'regra_bloco_unico' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)', 1)), '')
          WHEN matching_rule = 'regra_apenas_numeros' THEN COALESCE(ltrim('0', norm), '0')
          WHEN matching_rule IN ('regra_apenas_casa', 'regra_casa_dir') THEN ''
          WHEN matching_rule = 'regra_casa_numero' THEN COALESCE(ltrim('0', regexp_extract(norm, '^\\b(casa|cs|csa|c|cobertura|sobrado|garden)\\b\\s+(\\d+)$', 2)), '0')
          WHEN matching_rule = 'regra_casa_letra' THEN CAST(ascii(regexp_extract(norm, '([a-z])$', 1)) - 96 AS STRING)
          WHEN matching_rule = 'regra_m1' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)$', 1)), '0')
          WHEN matching_rule = 'regra_m2' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)$', 1)), '0')
          WHEN matching_rule = 'regra_m3' THEN COALESCE(ltrim('0', regexp_extract(norm, '^\\b(apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b\\s+(\\d+)', 2)), '0')
          WHEN matching_rule = 'regra_m4' THEN COALESCE(ltrim('0', regexp_extract(norm, '^(\\d+)', 1)), '0')
          WHEN matching_rule = 'regra_m_nb' THEN COALESCE(ltrim('0', regexp_extract(norm, '^(\\d+)', 1)), '0')
          WHEN matching_rule = 'regra_letra_numero' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)', 1)), '0')
          WHEN matching_rule = 'regra_numero_letra_separada' THEN COALESCE(ltrim('0', regexp_extract(norm, '^(\\d+)', 1)), '0')
          WHEN matching_rule = 'regra_fallback_apt' THEN COALESCE(ltrim('0', regexp_extract(norm, '\\b(apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b\\s*(\\d+)', 2)), '0')
          WHEN matching_rule = 'regra_fallback_bloco' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)', 1)), '')
          WHEN matching_rule = 'regra_fallback_numero' THEN COALESCE(ltrim('0', regexp_extract(norm, '(\\d+)', 1)), '0')
          ELSE ''
        END AS numero,
        CASE
          WHEN matching_rule = 'regra_casa_dir' THEN regexp_extract(norm, '(frente|fundos?|cima|baixo)$', 1)              
          WHEN matching_rule = 'regra_m1' THEN
              CASE
                  WHEN 
                      length(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\b(?:apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b', 1))) = 1 
                      AND regexp_like(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\b(?:apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b', 1)), '^[a-z]$')
                  THEN 
                      CAST(ascii(NULLIF(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\b(?:apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b', 1)), '')) - 96 AS STRING)
                  ELSE 
                      TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\b(?:apartamento|apto|apt|ap|kitnet|kit|studio|unidade|und|un)\\b', 1))
              END              
          WHEN matching_rule = 'regra_m2' THEN
              CASE
                  WHEN 
                      length(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\d+$', 1))) = 1 
                      AND regexp_like(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\d+$', 1)), '^[a-z]$')
                  THEN 
                      CAST(ascii(NULLIF(TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\d+$', 1)), '')) - 96 AS STRING)
                  ELSE 
                      TRIM(regexp_extract(norm, '^\\b(?:bloco|torre|bl|blc|b|t|tr)\\b\\s+(.*?)\\s+\\d+$', 1))
              END              
          WHEN matching_rule IN ('regra_m3', 'regra_m4') THEN
              CASE
                  WHEN 
                      length(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9].*)$', 2)) = 1 
                      AND regexp_like(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9].*)$', 2), '^[a-z]$')
                  THEN 
                      CAST(ascii(NULLIF(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z])$', 2), '')) - 96 AS STRING)
                  ELSE 
                      TRIM(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s+([a-z0-9].*)$', 2))
              END               
          WHEN matching_rule = 'regra_m_nb' THEN
              CASE
                  WHEN 
                      regexp_like(regexp_extract(norm, '([0-9a-z])\\s*$', 1), '^[a-z]$')
                  THEN 
                      CAST(ascii(NULLIF(regexp_extract(norm, '([a-z])\\s*$', 1), '')) - 96 AS STRING)
                  ELSE 
                      regexp_extract(norm, '([0-9])\\s*$', 1)
              END              
          WHEN matching_rule = 'regra_letra_numero' THEN CAST(ascii(NULLIF(regexp_extract(norm, '([a-z])', 1), '')) - 96 AS STRING)              
          WHEN matching_rule = 'regra_numero_letra_separada' THEN CAST(ascii(NULLIF(regexp_extract(norm, '([a-z])$', 1), '')) - 96 AS STRING)              
          WHEN matching_rule = 'regra_fallback_apt' THEN COALESCE(CAST(ascii(NULLIF(regexp_extract(norm, '\\d+\\s*([a-z])$', 1), '')) - 96 AS STRING), '')              
          WHEN matching_rule = 'regra_fallback_bloco' THEN
              CASE
                  WHEN 
                      regexp_like(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s*([a-z0-9]+)', 2), '^[a-z]$')
                  THEN 
                      CAST(ascii(NULLIF(regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s*([a-z])', 2), '')) - 96 AS STRING)
                  ELSE 
                      regexp_extract(norm, '\\b(bloco|torre|bl|blc|b|t|tr)\\b\\s*([0-9a-z]+)', 2)
              END              
          ELSE ''
        END AS raw_extra
      FROM 
        classified_complements
  )
  SELECT
    id_house,
    status_origin,
    dt_creation,
    address_full,
    city,
    zipcode,
    address,
    number,
    neighborhood,
    complemento_bruto AS complement,
    matching_rule,
    numero AS number_complement,
    CASE
      WHEN regexp_like(raw_extra, '^\\d+$') THEN COALESCE(ltrim(raw_extra, '0'), '0')
      ELSE raw_extra
    END AS extra_complement,
    number_complement || CASE WHEN extra_complement IS NULL OR extra_complement = '' THEN '' ELSE ', ' || extra_complement END as complement_parsed
  FROM 
    base_raw
), 
house_parsed as (
  SELECT
    h.id_house,
    h.address || ', ' || h.number || CASE 
      WHEN h.complement IS NULL OR h.complement = '' THEN '' 
      ELSE ', ' || h.complement 
    END || ' - ' || h.neighborhood || ' - ' || h.zipcode AS address_full,
    h.address || ', ' || h.number || CASE 
      WHEN h.complement_parsed IS NULL OR h.complement_parsed = '' THEN '' 
      ELSE ', ' || h.complement_parsed 
    END AS address_parsed_short  
  FROM 
    house h
  WHERE
    h.status_origin != 'excluido'
    AND h.city NOT IN ('Ciudad del México', 'Tlalnepantla', 'Ciudad López Mateos', 'Naucalpan de Juárez', 'Tlalnepantla de Baz')
),
listing_info AS (
  SELECT
    id_house,
    MAX(CASE WHEN lbc.business_context = 'RENT' THEN lbc.status ELSE NULL END) AS status_rent,
    MAX(CASE WHEN lbc.business_context = 'SALE' THEN lbc.status ELSE NULL END) AS status_sale,
    MAX(CASE WHEN lbc.business_context = 'RENT' THEN lbc.user_listing_registrant_rent ELSE NULL END) AS user_listing_registrant_rent,
    MAX(CASE WHEN lbc.business_context = 'SALE' THEN lbc.user_listing_registrant_sale ELSE NULL END) AS user_listing_registrant_sale,
    MAX(CASE WHEN lbc.business_context = 'RENT' THEN lbc.ts_first_listing ELSE NULL END) AS ts_first_listing_rent,
    MAX(CASE WHEN lbc.business_context = 'SALE' THEN lbc.ts_first_listing ELSE NULL END) AS ts_first_listing_sale,
    LEAST(ts_first_listing_rent, ts_first_listing_sale) AS ts_first_listing
  FROM
    datalake_ebdb_listing.listing_business_context AS lbc
  GROUP BY 1
),
rent_contract AS (
  SELECT
    id_house,
    COALESCE(ts_signed, ts_created) AS ts_signed,
    "RENT" AS business_context
  FROM
    datalake_ebdb_contract.contract
  WHERE
    status IN ('Ativo', 'Finalizado')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_signed ASC) = 1
),
sale_contract AS (
  SELECT
    id_house,
    dt_sale_agreement_signed AS ts_signed,
    "SALE" AS business_context
  FROM
    datalake_offer.sale_offer
  WHERE
    offer_status = 'OFFER_ACCEPTED'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY dt_sale_agreement_signed ASC) = 1
),
supply_source_info_by_context AS (
  SELECT
    id_house,
    MAX(CASE WHEN business_context = 'RENT' THEN supply_source ELSE NULL END) AS supply_source_rent,
    MAX(CASE WHEN business_context = 'SALE' THEN supply_source ELSE NULL END) AS supply_source_sale
  FROM
    datalake_supply_flows.conversion_lookup
  GROUP BY ALL
),
supply_source_info AS (
  SELECT
    cl.id_house,
    cl.supply_source
  FROM
    datalake_supply_flows.conversion_lookup AS cl
  LEFT JOIN
    listing_info AS li
      ON cl.id_house = li.id_house
      AND li.ts_first_listing IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY cl.id_house 
      ORDER BY
        LEAST(li.ts_first_listing_rent, li.ts_first_listing_sale),
        IF(cl.supply_source = 'CIQ', 1, 2),
        cl.supply_source
    ) = 1
),
listings_full_info AS (
  SELECT
    h.id_house,
    h.address_full,
    h.address_parsed_short,
    li.user_listing_registrant_rent,
    li.user_listing_registrant_sale,
    CASE 
        WHEN COUNT(*) OVER(PARTITION BY h.address_parsed_short) > 1 THEN TRUE 
        ELSE FALSE 
    END AS is_duplicated,
    ssi.supply_source,
    ssibc.supply_source_rent,
    ssibc.supply_source_sale,
    li.ts_first_listing_sale,
    li.ts_first_listing_rent,
    li.ts_first_listing,
    ROW_NUMBER() OVER (PARTITION BY h.address_parsed_short ORDER BY li.ts_first_listing) AS first_listing_order,
    first_listing_order = 1 AND is_duplicated AS is_first_listing_in_duplicates,
    rc.ts_signed AS ts_contract_signed_rent,
    sc.ts_signed AS ts_contract_signed_sale
  FROM 
    house_parsed AS h
  INNER JOIN
    listing_info AS li
      ON h.id_house = li.id_house
      AND li.ts_first_listing IS NOT NULL
  LEFT JOIN
    rent_contract AS rc
      ON h.id_house = rc.id_house
  LEFT JOIN
    sale_contract AS sc
      ON h.id_house = sc.id_house
  LEFT JOIN
    supply_source_info_by_context AS ssibc
      ON h.id_house = ssibc.id_house
  LEFT JOIN
    supply_source_info AS ssi
      ON h.id_house = ssi.id_house
  WHERE
    h.address_parsed_short IS NOT NULL
)
SELECT
  MD5(lfi.address_parsed_short) AS id_address_parsed_short,
  lfi.id_house,
  lfi_dup.id_house AS id_house_duplicated,
  lfi.user_listing_registrant_rent AS id_user_listing_registrant_rent,
  lfi.user_listing_registrant_sale AS id_user_listing_registrant_sale,
  lfi.address_full,
  lfi.address_parsed_short,
  lfi.supply_source,
  lfi.supply_source_rent,
  lfi.supply_source_sale,
  lfi.first_listing_order,
  lfi.is_duplicated,
  lfi.is_first_listing_in_duplicates,
  lfi.ts_first_listing_sale,
  lfi.ts_first_listing_rent,
  lfi.ts_first_listing,
  lfi.ts_contract_signed_rent,
  lfi.ts_contract_signed_sale
FROM 
  listings_full_info AS lfi
LEFT JOIN
  listings_full_info AS lfi_dup
    ON lfi_dup.address_parsed_short = lfi.address_parsed_short
    AND lfi_dup.first_listing_order - 1 = lfi.first_listing_order 