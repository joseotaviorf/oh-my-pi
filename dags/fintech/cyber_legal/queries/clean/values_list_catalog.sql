SELECT
    LVID AS id_value,
    LVFIELD AS field_with_predefined_values,
    LVLENGTH AS max_length,
    LVNAME AS name,
    LVTYPE AS field_data_type
FROM
    datalake_cyber_raw.lov
