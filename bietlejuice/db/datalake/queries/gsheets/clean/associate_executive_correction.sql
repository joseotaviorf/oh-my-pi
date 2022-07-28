SELECT
    id_associate_executive,
    incorrect_associate_executive,
    associate_executive,
    executive_position,
    hub,
    CAST(dt_month_ref AS DATE) AS dt_month_ref
FROM
    datalake_gsheets_raw.associate_executive_correction
