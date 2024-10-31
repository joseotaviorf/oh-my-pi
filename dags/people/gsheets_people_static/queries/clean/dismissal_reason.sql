SELECT
    variavel AS variable_name,
    valor_original AS original_value,
    valor_final AS final_value,
    ts_load
FROM datalake_gsheets_people_raw.dismissal_reason