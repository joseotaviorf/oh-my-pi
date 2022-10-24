SELECT 
  id,  
  category_description,
  category_level, 
  deposit_factor,
  factor AS guarantee_factor,
  standalone_factor,
  allow_deposit AS is_deposit_allowed,
  allow_guarantee AS is_guarantee_allowed,
  allow_pro_guarantor AS is_pro_guarantor_allowed,
  allow_standalone AS is_standalone_allowed,
  created_at AS ts_created,
  disabled_at AS ts_disabled,
  enabled_at AS ts_enabled,
  updated_at AS ts_updated
FROM 
  datalake_rental_guarantee_raw.risk_category
