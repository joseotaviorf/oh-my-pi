SELECT 
    id, 
    category_level, 
    factor,
    rev,
    revend AS rev_end,
    revtype As rev_type,
    standalone_factor,
    allow_guarantee AS is_guarantee_allowed,
    allow_standalone AS is_standalone_allowed,
    category_level_mod AS mod_category_level,
    factor_mod AS mod_factor, 
    standalone_factor_mod AS mod_standalone_factor,
    allow_guarantee_mod AS mod_is_guarantee_allowed,
    allow_standalone_mod AS mod_is_standalone_allowed,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_rental_guarantee_raw.risk_category_aud
