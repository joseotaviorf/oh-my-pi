SELECT a.DadosAgente_id as DadosAgente_id,
        a.regioes_id as regiao_id,
        FROM_UNIXTIME(floor(b.timestamp/1000)) as dt,
        a.REVTYPE
    FROM DadosAgente_Regiao_AUD a
     LEFT JOIN UsuarioRevisionEntity b
         ON a.rev = b.id
    WHERE FROM_UNIXTIME(floor(b.timestamp/1000)) >= TIMESTAMP('{}')
        and FROM_UNIXTIME(floor(b.timestamp/1000)) < TIMESTAMP('{}')