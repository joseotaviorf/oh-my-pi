WITH property_fee_aud AS (
  SELECT
    pf.id,
    pf.fee,
    TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000)) AS ts_event,
    LEAD(TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000))) OVER (PARTITION BY pf.id ORDER BY pf.rev) AS ts_next_event
  FROM
    datalake_ebdb_clean.property_fee_aud AS pf
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON pf.rev = ure.id
),
property_fee_assigned_aud AS (
  SELECT
    pfa.id_house,
    pfa.id_contract,
    pfa.id_property_fee,
    TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000)) AS ts_event,
    LEAD(TIMESTAMP(FROM_UNIXTIME(ure.ts_revision/1000))) OVER (PARTITION BY pfa.id_house ORDER BY pfa.rev) AS ts_next_event
  FROM
    datalake_ebdb_clean.property_fee_assigned_aud AS pfa
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON pfa.rev = ure.id
),
minimum_fees AS (
  SELECT
    pfa.id_house,
    MIN(pf.fee) AS fee
  FROM
    datalake_ebdb_clean.property_fee_assigned AS pfa
  LEFT JOIN
    datalake_ebdb_clean.property_fee AS pf
      ON pfa.id_property_fee = pf.id
  GROUP BY 1
),
house_fees AS (
  SELECT
    pfa.id_house,
    COALESCE(fc.monthly_administration_fee, pf_aud.fee, pf.fee) AS administration_fee,
    pfa.ts_event,
    IF(pfa.ts_event = pfa.ts_next_event, NULL, pfa.ts_next_event) AS ts_next_event
  FROM
    property_fee_assigned_aud AS pfa
  LEFT JOIN
    property_fee_aud AS pf_aud
      ON pfa.id_property_fee = pf_aud.id
      AND pfa.ts_event >= pf_aud.ts_event
      AND pfa.ts_event < COALESCE(pf_aud.ts_next_event, NOW())
  LEFT JOIN
    datalake_ebdb_clean.property_fee AS pf
      ON pfa.id_property_fee = pf.id
  LEFT JOIN
    datalake_ebdb_clean.full_contract AS fc
      ON pfa.id_contract = fc.id
),
latest_contract AS (
  SELECT
    hl.id_house_listing,
    MAX(c.id) AS id_contract
  FROM 
    datalake_ebdb_listing.house_listing AS hl
  JOIN 
    datalake_ebdb_clean.contract AS c
      ON hl.id_house = c.id_house
      AND c.ts_created >= COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') 
      AND c.ts_created < COALESCE(hl.ts_listing_version_end, CURRENT_DATE)
      AND c.status in ('Ativo', 'Finalizado')
  GROUP BY hl.id_house_listing, hl.id_house
)

SELECT
  hl.id_house_listing,
  hl.id_house,
  hl.country_code,
  COALESCE(fc.monthly_administration_fee, MIN(hf.administration_fee), mf.fee) AS administration_fee
FROM
  datalake_ebdb_listing.house_listing AS hl
LEFT JOIN
  house_fees AS hf
    ON hf.id_house = hl.id_house
    AND hf.ts_event >= COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') 
    AND hf.ts_event < COALESCE(hl.ts_listing_version_end, CURRENT_DATE)
LEFT JOIN
  latest_contract AS lc
    ON lc.id_house_listing = hl.id_house_listing
LEFT JOIN
  datalake_ebdb_clean.full_contract AS fc
    ON fc.id = lc.id_contract
LEFT JOIN
  minimum_fees AS mf
    ON hl.id_house = mf.id_house
GROUP BY 1, 2, 3, monthly_administration_fee, mf.fee