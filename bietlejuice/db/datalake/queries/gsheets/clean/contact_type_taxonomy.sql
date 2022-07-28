SELECT
    contact_motivation_tag,
    contact_theme_tag,
    contact_type_tag,
    customer_type_tag,
    CAST(is_correspondent_contact_type AS BOOLEAN) AS is_correspondent_contact_type
FROM
    datalake_gsheets_raw.contact_type_tag