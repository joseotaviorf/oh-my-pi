SELECT 
    house_id AS id_house,
    rev,
    revend AS rev_end, 
    CAST(revtype AS INTEGER) AS rev_type, 
    covered_amount,
    covered_amount_mod AS mod_covered_amount
FROM 
    datalake_repairs_raw.instant_approval_preference_aud