SELECT
    phone_number,
    optin AS opt_in,
    optin_mod AS mod_opt_in,
    rev,
    revtype AS rev_type,
    revend AS rev_end
FROM
    datalake_wololo_raw.whatsapp_aud