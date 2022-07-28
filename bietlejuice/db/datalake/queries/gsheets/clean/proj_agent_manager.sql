SELECT
    CAST(IdUser AS BIGINT) AS id_user,
    CAST(IdUserSupervisor AS BIGINT) AS id_user_supervisor,
    Condicao AS condition,
    StatusMentoria AS mentorship_status,
    MotivoAbandono AS abandonment_reason,
    AnalistaResponsavel AS responsible_analyst,
    CAST(Semanas AS SMALLINT) AS weeks,
    TO_DATE(DataInicioCarteira,'dd/MM/yyyy') AS dt_started,
    TO_DATE(DataEntradaCarteira,'dd/MM/yyyy') AS dt_entrance,
    TO_DATE(NULLIF(DataSaidaCarteira,''),'dd/MM/yyyy') AS dt_ended,
    TO_DATE(DataFimMentoriaNH,'dd/MM/yyyy') AS dt_mentorship_nh_ended
FROM
    datalake_gsheets_raw.estrutura_gerente_corretor
