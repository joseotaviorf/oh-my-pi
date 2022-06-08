SELECT
    INT(NULLIF(sk_contract,'')) AS id_contract,
    INT(NULLIF(sk_ticket,'')) AS id_ticket,
    NULLIF(email,'') AS email,
    NULLIF(status,'') AS status,
    NULLIF(comentarios_vistoriador_devidos,'') AS inspector_comments_due,
    NULLIF(comentarios_vistoriador_total,'') AS total_inspector_comments,
    NULLIF(vistoriador_comentou,'') AS inspector_commented,
    NULLIF(analise_ajustes_devidos_iq,'') AS adjustments_tenant_duty,
    TO_TIMESTAMP(NULLIF(ts_input,''),'M/d/y H:m:s') AS ts_input
FROM
    datalake_gsheets_raw.forms_analise_vistoria