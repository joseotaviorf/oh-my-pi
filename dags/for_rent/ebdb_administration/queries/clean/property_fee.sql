SELECT
  id,
  contractType AS contract_type,
  category,
  regionType AS region_type,
  bodyObservation AS body_observation,
  bodyText AS body_text,
  bodyTitle AS body_title,
  headerSubTitle AS header_subtitle,
  headerTitle AS header_title,
  promotionTag AS promotion_tag,
  promotionUrl AS promotion_url,
  fee,
  promotionalAdmFee AS promotional_adm_fee,
  promotionalPeriod AS promotional_period,
  validFrom AS ts_valid_from,
  validUntil AS ts_valid_until,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.propertyfee