SELECT
    id,
    idempresa AS id_company,
    idacordo AS id_agreement,
    processo AS process,
    status,
    usuario_cancelamento AS cancellation_user,
    usuario_quitacao AS discharge_user,
    forma_pagto AS payment_type,
    parcela AS installment,
    valor AS value,
    valorbkp AS backup_value,
    data_quitacao AS dt_discharge,
    data_vencto AS dt_due,
    data_cancelamento AS dt_cancellation,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_acordo_neg
