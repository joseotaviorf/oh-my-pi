SELECT
    pr.id AS id,
    ST_ASText(pr.`poligono`) AS poligono,
    pr.regiao_id AS regiao_id,
    pr.atualizadoem AS atualizadoEm,
    pr.criadoem AS criadoEm
FROM
    `PoligonoRegiao` pr