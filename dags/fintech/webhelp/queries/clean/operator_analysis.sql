SELECT
    data,
    celular,
    tipo_pa,
    nome_operador,
    max_login,
    max_logout,
    tempo_logado,
    tempo_idle,
    tempo_conversacao,
    tempo_pausa,
    tabulacoes,
    tma,
    acordos,
    transferencias,
    clientes_distintos_acionados
FROM datalake_webhelp_raw.analise_operadores
