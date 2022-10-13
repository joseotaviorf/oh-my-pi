with 
    vans_codes as (
        select 
            distinct *
        from (
            select occurrence_code 
            from datalake_vans_clean.boleto 
            union all
            select occurrence_code 
            from datalake_vans_clean.payment 
            union all
            select occurrence_code
            from datalake_vans_clean.payment_boleto
        )
        where occurrence_code is not null
    ),
    cnab as (
        select lpad(string(seq),2,'0') as code 
        from (select explode(sequence(2,93)) as seq)
        where seq not in (31,49,50,58,66,67,68,70,81,84)
    ),
    sispag as (
        select 
            explode(array('00', 'AE', 'AG', 'AH', 'AI', 'AJ', 'AL', 'AM', 'AN', 'EM', 'AO', 
                    'AP', 'AQ', 'AR', 'BC', 'BD', 'BE', 'BI', 'BL', 'CD', 'CE', 'CF', 'CG', 
                    'CH', 'CI', 'CJ', 'CK', 'CL', 'CM', 'CN', 'CO', 'CP', 'CQ', 'CR', 'CS', 
                    'DA', 'DB', 'DC', 'DD', 'DE', 'DF', 'DG', 'DH', 'DI', 'DJ', 'DK', 'DL', 
                    'DL', 'DM', 'DV', 'D0', 'D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8', 
                    'D9', 'EM', 'EX', 'E0', 'E1', 'E2', 'E3', 'E4', 'FC', 'FD', 'HA', 'HM', 
                    'IB', 'IC', 'ID', 'IE', 'IF', 'IG', 'IH', 'II', 'IJ', 'IK', 'IL', 'IM', 
                    'IN', 'IO', 'IP', 'IQ', 'IR', 'IS', 'IT', 'IU', 'IV', 'IX', 'LA', 'LC', 
                    'NA', 'NB', 'NC', 'ND', 'NE', 'NF', 'NG', 'NH', 'NI', 'NR', 'PD', 'RJ', 
                    'RS', 'SS', 'TA', 'TI', 'X1', 'X2', 'X3', 'X4')) as code
    ),
    cnab_desc as (
        select 
            code,
            'cnab' as source,
            case when code = '02' then 'ENTRADA CONFIRMADA COM POSSIBILIDADE DE MENSAGEM (NOTA 20 – TABELA 10)'
            when code = '03' then 'ENTRADA REJEITADA (NOTA 20 – TABELA 1)'
            when code = '04' then 'ALTERAÇÃO DE DADOS – NOVA ENTRADA OU ALTERAÇÃO/EXCLUSÃO DE DADOS ACATADA'
            when code = '05' then 'ALTERAÇÃO DE DADOS – BAIXA'
            when code = '06' then 'LIQUIDAÇÃO NORMAL'
            when code = '07' then 'LIQUIDAÇÃO PARCIAL – COBRANÇA INTELIGENTE (B2B)'
            when code = '08' then 'LIQUIDAÇÃO EM CARTÓRIO'
            when code = '09' then 'BAIXA SIMPLES'
            when code = '10' then 'BAIXA POR TER SIDO LIQUIDADO'
            when code = '11' then 'EM SER (SÓ NO RETORNO MENSAL)'
            when code = '12' then 'ABATIMENTO CONCEDIDO'
            when code = '13' then 'ABATIMENTO CANCELADO'
            when code = '14' then 'VENCIMENTO ALTERADO'
            when code = '15' then 'BAIXAS REJEITADAS (NOTA 20 – TABELA 4)'
            when code = '16' then 'INSTRUÇÕES REJEITADAS (NOTA 20 – TABELA 3)'
            when code = '17' then 'ALTERAÇÃO/EXCLUSÃO DE DADOS REJEITADOS (NOTA 20 – TABELA 2)'
            when code = '18' then 'COBRANÇA CONTRATUAL – INSTRUÇÕES/ALTERAÇÕES REJEITADAS/PENDENTES (NOTA 20 – TABELA 5)'
            when code = '19' then 'CONFIRMA RECEBIMENTO DE INSTRUÇÃO DE PROTESTO'
            when code = '20' then 'CONFIRMA RECEBIMENTO DE INSTRUÇÃO DE SUSTAÇÃO DE PROTESTO /TARIFA'
            when code = '21' then 'CONFIRMA RECEBIMENTO DE INSTRUÇÃO DE NÃO PROTESTAR'
            when code = '23' then 'TÍTULO ENVIADO A CARTÓRIO/TARIFA'
            when code = '24' then 'INSTRUÇÃO DE PROTESTO REJEITADA / SUSTADA / PENDENTE (NOTA 20 – TABELA 7)'
            when code = '25' then 'ALEGAÇÕES DO PAGADOR (NOTA 20 – TABELA 6)'
            when code = '26' then 'TARIFA DE AVISO DE COBRANÇA'
            when code = '27' then 'TARIFA DE EXTRATO POSIÇÃO (B40X)'
            when code = '28' then 'TARIFA DE RELAÇÃO DAS LIQUIDAÇÕES'
            when code = '29' then 'TARIFA DE MANUTENÇÃO DE TÍTULOS VENCIDOS'
            when code = '30' then 'DÉBITO MENSAL DE TARIFAS (PARA ENTRADAS E BAIXAS)'
            when code = '32' then 'BAIXA POR TER SIDO PROTESTADO'
            when code = '33' then 'CUSTAS DE PROTESTO'
            when code = '34' then 'CUSTAS DE SUSTAÇÃO'
            when code = '35' then 'CUSTAS DE CARTÓRIO DISTRIBUIDOR'
            when code = '36' then 'CUSTAS DE EDITAL'
            when code = '37' then 'TARIFA DE EMISSÃO DE BOLETO/TARIFA DE ENVIO DE DUPLICATA'
            when code = '38' then 'TARIFA DE INSTRUÇÃO'
            when code = '39' then 'TARIFA DE OCORRÊNCIAS'
            when code = '40' then 'TARIFA MENSAL DE EMISSÃO DE BOLETO/TARIFA MENSAL DE ENVIO DE DUPLICATA'
            when code = '41' then 'DÉBITO MENSAL DE TARIFAS – EXTRATO DE POSIÇÃO (B4EP/B4OX)'
            when code = '42' then 'DÉBITO MENSAL DE TARIFAS – OUTRAS INSTRUÇÕES'
            when code = '43' then 'DÉBITO MENSAL DE TARIFAS – MANUTENÇÃO DE TÍTULOS VENCIDOS'
            when code = '44' then 'DÉBITO MENSAL DE TARIFAS – OUTRAS OCORRÊNCIAS'
            when code = '45' then 'DÉBITO MENSAL DE TARIFAS – PROTESTO'
            when code = '46' then 'DÉBITO MENSAL DE TARIFAS – SUSTAÇÃO DE PROTESTO'
            when code = '47' then 'BAIXA COM TRANSFERÊNCIA PARA DESCONTO'
            when code = '48' then 'CUSTAS DE SUSTAÇÃO JUDICIAL'
            when code = '51' then 'TARIFA MENSAL REF A ENTRADAS BANCOS CORRESPONDENTES NA CARTEIRA'
            when code = '52' then 'TARIFA MENSAL BAIXAS NA CARTEIRA'
            when code = '53' then 'TARIFA MENSAL BAIXAS EM BANCOS CORRESPONDENTES NA CARTEIRA'
            when code = '54' then 'TARIFA MENSAL DE LIQUIDAÇÕES NA CARTEIRA'
            when code = '55' then 'TARIFA MENSAL DE LIQUIDAÇÕES EM BANCOS CORRESPONDENTES NA CARTEIRA'
            when code = '56' then 'CUSTAS DE IRREGULARIDADE'
            when code = '57' then 'INSTRUÇÃO CANCELADA (NOTA 20 – TABELA 8)'
            when code = '59' then 'BAIXA POR CRÉDITO EM C/C ATRAVÉS DO SISPAG'
            when code = '60' then 'ENTRADA REJEITADA CARNÊ (NOTA 20 – TABELA 1)'
            when code = '61' then 'TARIFA EMISSÃO AVISO DE MOVIMENTAÇÃO DE TÍTULOS (2154)'
            when code = '62' then 'DÉBITO MENSAL DE TARIFA – AVISO DE MOVIMENTAÇÃO DE TÍTULOS (2154)'
            when code = '63' then 'TÍTULO SUSTADO JUDICIALMENTE'
            when code = '64' then 'ENTRADA CONFIRMADA COM RATEIO DE CRÉDITO'
            when code = '65' then 'PAGAMENTO COM CHEQUE – AGUARDANDO COMPENSAÇÃO'
            when code = '69' then 'CHEQUE DEVOLVIDO (NOTA 20 – TABELA 9)'
            when code = '71' then 'ENTRADA REGISTRADA, AGUARDANDO AVALIAÇÃO'
            when code = '72' then 'BAIXA POR CRÉDITO EM C/C ATRAVÉS DO SISPAG SEM TÍTULO CORRESPONDENTE'
            when code = '73' then 'CONFIRMAÇÃO DE ENTRADA NA COBRANÇA SIMPLES – ENTRADA NÃO ACEITA NA COBRANÇA CONTRATUAL'
            when code = '74' then 'INSTRUÇÃO DE NEGATIVAÇÃO EXPRESSA REJEITADA (NOTA 20 – TABELA 11)'
            when code = '75' then 'CONFIRMAÇÃO DE RECEBIMENTO DE INSTRUÇÃO DE ENTRADA EM NEGATIVAÇÃO EXPRESSA'
            when code = '76' then 'CHEQUE COMPENSADO'
            when code = '77' then 'CONFIRMAÇÃO DE RECEBIMENTO DE INSTRUÇÃO DE EXCLUSÃO DE ENTRADA EM NEGATIVAÇÃO EXPRESSA'
            when code = '78' then 'CONFIRMAÇÃO DE RECEBIMENTO DE INSTRUÇÃO DE CANCELAMENTO DE NEGATIVAÇÃO EXPRESSA'
            when code = '79' then 'NEGATIVAÇÃO EXPRESSA INFORMACIONAL (NOTA 20 – TABELA 12)'
            when code = '80' then 'CONFIRMAÇÃO DE ENTRADA EM NEGATIVAÇÃO EXPRESSA – TARIFA'
            when code = '82' then 'CONFIRMAÇÃO DO CANCELAMENTO DE NEGATIVAÇÃO EXPRESSA – TARIFA'
            when code = '83' then 'CONFIRMAÇÃO DE EXCLUSÃO DE ENTRADA EM NEGATIVAÇÃO EXPRESSA POR LIQUIDAÇÃO – TARIFA'
            when code = '85' then 'TARIFA POR BOLETO (ATÉ 03 ENVIOS) COBRANÇA ATIVA ELETRÔNICA'
            when code = '86' then 'TARIFA EMAIL COBRANÇA ATIVA ELETRÔNICA'
            when code = '87' then 'TARIFA SMS COBRANÇA ATIVA ELETRÔNICA'
            when code = '88' then 'TARIFA MENSAL POR BOLETO (ATÉ 03 ENVIOS) COBRANÇA ATIVA ELETRÔNICA'
            when code = '89' then 'TARIFA MENSAL EMAIL COBRANÇA ATIVA ELETRÔNICA'
            when code = '90' then 'TARIFA MENSAL SMS COBRANÇA ATIVA ELETRÔNICA'
            when code = '91' then 'TARIFA MENSAL DE EXCLUSÃO DE ENTRADA DE NEGATIVAÇÃO EXPRESSA'
            when code = '92' then 'TARIFA MENSAL DE CANCELAMENTO DE NEGATIVAÇÃO EXPRESSA'
            when code = '93' then 'TARIFA MENSAL DE EXCLUSÃO DE NEGATIVAÇÃO EXPRESSA POR LIQUIDAÇÃO'
            end as description 
        from cnab
    ),
    sispag_desc as (
        select 
            code,
            'sispag' as source,
            case when code = '00' then 'PAGAMENTO EFETUADO'
            when code = 'AE' then 'DATA DE PAGAMENTO ALTERADA'
            when code = 'AG' then 'NÚMERO DO LOTE INVÁLIDO'
            when code = 'AH' then 'NÚMERO SEQUENCIAL DO REGISTRO NO LOTE INVÁLIDO'
            when code = 'AI' then 'PRODUTO DEMONSTRATIVO DE PAGAMENTO NÃO CONTRATADO'
            when code = 'AJ' then 'TIPO DE MOVIMENTO INVÁLIDO'
            when code = 'AL' then 'CÓDIGO DO BANCO FAVORECIDO INVÁLIDO'
            when code = 'AM' then 'AGÊNCIA DO FAVORECIDO INVÁLIDA'
            when code = 'AN' then 'CONTA CORRENTE DO FAVORECIDO INVÁLIDA / CONTA INVESTIMENTO EXTINTA EM 30/04/2011'
            when code = 'AO' then 'NOME DO FAVORECIDO INVÁLIDO'
            when code = 'AP' then 'DATA DE PAGAMENTO / DATA DE VALIDADE / HORA DE LANÇAMENTO /ARRECADAÇÃO / APURAÇÃO INVÁLIDA'
            when code = 'AQ' then 'QUANTIDADE DE REGISTROS MAIOR QUE 999999'
            when code = 'AR' then 'VALOR ARRECADADO / LANÇAMENTO INVÁLIDO'
            when code = 'BC' then 'NOSSO NÚMERO INVÁLIDO'
            when code = 'BD' then 'PAGAMENTO AGENDADO'
            when code = 'BE' then 'PAGAMENTO AGENDADO COM FORMA ALTEARADA PARA OP'
            when code = 'BI' then 'CNPJ/CPF DO BENEFICIÁRIO INVÁLIDO NO SEGMENTO J-52 ou B INVÁLIDO'
            when code = 'BL' then 'VALOR DA PARCELA INVÁLIDO'
            when code = 'CD' then 'CNPJ / CPF INFORMADO DIVERGENTE DO CADASTRADO'
            when code = 'CE' then 'PAGAMENTO CANCELADO'
            when code = 'CF' then 'VALOR DO DOCUMENTO INVÁLIDO'
            when code = 'CG' then 'VALOR DO ABATIMENTO INVÁLIDO'
            when code = 'CH' then 'VALOR DO DESCONTO INVÁLIDO'
            when code = 'CI' then 'CNPJ / CPF / IDENTIFICADOR / INSCRIÇÃO ESTADUAL / INSCRIÇÃO NO CAD / ICMS INVÁLIDO'
            when code = 'CJ' then 'VALOR DA MULTA INVÁLIDO'
            when code = 'CK' then 'TIPO DE INSCRIÇÃO INVÁLIDA'
            when code = 'CL' then 'VALOR DO INSS INVÁLIDO'
            when code = 'CM' then 'VALOR DO COFINS INVÁLIDO'
            when code = 'CN' then 'CONTA NÃO CADASTRADA'
            when code = 'CO' then 'VALOR DE OUTRAS ENTIDADES INVÁLIDO'
            when code = 'CP' then 'CONFIRMAÇÃO DE OP CUMPRIDA'
            when code = 'CQ' then 'SOMA DAS FATURAS DIFERE DO PAGAMENTO'
            when code = 'CR' then 'VALOR DO CSLL INVÁLIDO'
            when code = 'CS' then 'DATA DE VENCIMENTO DA FATURA INVÁLIDA'
            when code = 'DA' then 'NÚMERO DE DEPEND. SALÁRIO FAMILIA INVALIDO'
            when code = 'DB' then 'NÚMERO DE HORAS SEMANAIS INVÁLIDO'
            when code = 'DC' then 'SALÁRIO DE CONTRIBUIÇÃO INSS INVÁLIDO'
            when code = 'DD' then 'SALÁRIO DE CONTRIBUIÇÃO FGTS INVÁLIDO'
            when code = 'DE' then 'VALOR TOTAL DOS PROVENTOS INVÁLIDO'
            when code = 'DF' then 'VALOR TOTAL DOS DESCONTOS INVÁLIDO'
            when code = 'DG' then 'VALOR LÍQUIDO NÃO NUMÉRICO'
            when code = 'DH' then 'VALOR LIQ. INFORMADO DIFERE DO CALCULADO'
            when code = 'DI' then 'VALOR DO SALÁRIO-BASE INVÁLIDO'
            when code = 'DJ' then 'BASE DE CÁLCULO IRRF INVÁLIDA'
            when code = 'DK' then 'BASE DE CÁLCULO FGTS INVÁLIDA'
            when code = 'DL' then 'FORMA DE PAGAMENTO INCOMPATÍVEL COM HOLERITE '
            when code = 'DM' then 'E-MAIL DO FAVORECIDO INVÁLIDO'
            when code = 'DV' then 'DOC / TED DEVOLVIDO PELO BANCO FAVORECIDO'
            when code = 'D0' then 'FINALIDADE DO HOLERITE INVÁLIDA'
            when code = 'D1' then 'MÊS DE COMPETENCIA DO HOLERITE INVÁLIDA'
            when code = 'D2' then 'DIA DA COMPETENCIA DO HOLETITE INVÁLIDA'
            when code = 'D3' then 'CENTRO DE CUSTO INVÁLIDO'
            when code = 'D4' then 'CAMPO NUMÉRICO DA FUNCIONAL INVÁLIDO'
            when code = 'D5' then 'DATA INÍCIO DE FÉRIAS NÃO NUMÉRICA'
            when code = 'D6' then 'DATA INÍCIO DE FÉRIAS INCONSISTENTE'
            when code = 'D7' then 'DATA FIM DE FÉRIAS NÃO NUMÉRICO'
            when code = 'D8' then 'DATA FIM DE FÉRIAS INCONSISTENTE'
            when code = 'D9' then 'NÚMERO DE DEPENDENTES IR INVÁLIDO'
            when code = 'EM' then 'CONFIRMAÇÃO DE OP EMITIDA'
            when code = 'EX' then 'DEVOLUÇÃO DE OP NÃO SACADA PELO FAVORECIDO'
            when code = 'E0' then 'TIPO DE MOVIMENTO HOLERITE INVÁLIDO'
            when code = 'E1' then 'VALOR 01 DO HOLERITE / INFORME INVÁLIDO'
            when code = 'E2' then 'VALOR 02 DO HOLERITE / INFORME INVÁLIDO'
            when code = 'E3' then 'VALOR 03 DO HOLERITE / INFORME INVÁLIDO'
            when code = 'E4' then 'VALOR 04 DO HOLERITE / INFORME INVÁLIDO'
            when code = 'FC' then 'PAGAMENTO EFETUADO ATRAVÉS DE FINANCIAMENTO COMPROR'
            when code = 'FD' then 'PAGAMENTO EFETUADO ATRAVÉS DE FINANCIAMENTO DESCOMPROR'
            when code = 'HA' then 'ERRO NO HEADER DE ARQUIVO'
            when code = 'HM' then 'ERRO NO HEADER DE LOTE'
            when code = 'IB' then 'VALOR E/OU DATA DO DOCUMENTO INVÁLIDO'
            when code = 'IC' then 'VALOR DO ABATIMENTO INVÁLIDO'
            when code = 'ID' then 'VALOR DO DESCONTO INVÁLIDO'
            when code = 'IE' then 'VALOR DA MORA INVÁLIDO'
            when code = 'IF' then 'VALOR DA MULTA INVÁLIDO'
            when code = 'IG' then 'VALOR DA DEDUÇÃO INVÁLIDO'
            when code = 'IH' then 'VALOR DO ACRÉSCIMO INVÁLIDO'
            when code = 'II' then 'DATA DE VENCIMENTO INVÁLIDA'
            when code = 'IJ' then 'COMPETÊNCIA / PERÍODO REFERÊNCIA / PARCELA INVÁLIDA'
            when code = 'IK' then 'TRIBUTO NÃO LIQUIDÁVEL VIA SISPAG OU NÃO CONVENIADO COM ITAÚ'
            when code = 'IL' then 'CÓDIGO DE PAGAMENTO / EMPRESA /RECEITA INVÁLIDO'
            when code = 'IM' then 'TIPO X FORMA NÃO COMPATÍVEL'
            when code = 'IN' then 'BANCO/AGENCIA NÃO CADASTRADOS'
            when code = 'IO' then 'DAC / VALOR / COMPETÊNCIA / IDENTIFICADOR DO LACRE INVÁLIDO'
            when code = 'IP' then 'DAC DO CÓDIGO DE BARRAS INVÁLIDO'
            when code = 'IQ' then 'DÍVIDA ATIVA OU NÚMERO DE ETIQUETA INVÁLIDO'
            when code = 'IR' then 'PAGAMENTO ALTERADO'
            when code = 'IS' then 'CONCESSIONÁRIA NÃO CONVENIADA COM ITAÚ'
            when code = 'IT' then 'VALOR DO TRIBUTO INVÁLIDO'
            when code = 'IU' then 'VALOR DA RECEITA BRUTA ACUMULADA INVÁLIDO'
            when code = 'IV' then 'NÚMERO DO DOCUMENTO ORIGEM / REFERÊNCIA INVÁLIDO'
            when code = 'IX' then 'CÓDIGO DO PRODUTO INVÁLIDO'
            when code = 'LA' then 'DATA DE PAGAMENTO DE UM LOTE ALTERADA'
            when code = 'LC' then 'LOTE DE PAGAMENTOS CANCELADO'
            when code = 'NA' then 'PAGAMENTO CANCELADO POR FALTA DE AUTORIZAÇÃO'
            when code = 'NB' then 'IDENTIFICAÇÃO DO TRIBUTO INVÁLIDA'
            when code = 'NC' then 'EXERCÍCIO (ANO BASE) INVÁLIDO'
            when code = 'ND' then 'CÓDIGO RENAVAM NÃO ENCONTRADO/INVÁLIDO'
            when code = 'NE' then 'UF INVÁLIDA'
            when code = 'NF' then 'CÓDIGO DO MUNICÍPIO INVÁLIDO'
            when code = 'NG' then 'PLACA INVÁLIDA'
            when code = 'NH' then 'OPÇÃO/PARCELA DE PAGAMENTO INVÁLIDA'
            when code = 'NI' then 'TRIBUTO JÁ FOI PAGO OU ESTÁ VENCIDO'
            when code = 'NR' then 'OPERAÇÃO NÃO REALIZADA'
            when code = 'PD' then 'AQUISIÇÃO CONFIRMADA (EQUIVALE A OCORRÊNCIA 02 NO LAYOUT DE RISCO SACADO)'
            when code = 'RJ' then 'REGISTRO REJEITADO'
            when code = 'RS' then 'PAGAMENTO DISPONÍVEL PARA ANTECIPAÇÃO NO RISCO SACADO – MODALIDADE RISCO SACADO PÓS AUTORIZADO'
            when code = 'SS' then 'PAGAMENTO CANCELADO POR INSUFICIÊNCIA DE SALDO/LIMITE DIÁRIO DE PAGTO'
            when code = 'TA' then 'LOTE NÃO ACEITO - TOTAIS DO LOTE COM DIFERENÇA'
            when code = 'TI' then 'TITULARIDADE INVÁLIDA'
            when code = 'X1' then 'FORMA INCOMPATÍVEL COM LAYOUT 010'
            when code = 'X2' then 'NÚMERO DA NOTA FISCAL INVÁLIDO'
            when code = 'X3' then 'IDENTIFICADOR DE NF/CNPJ INVÁLIDO'
            when code = 'X4' then 'FORMA 32 INVÁLIDA'
            end as description
        from sispag
    ),
    bank_codes as (
        select * from cnab_desc
        union all 
        select * from sispag_desc
    ),
    codes as (
        select 
            coalesce(vc.occurrence_code, bc.code) as sk_occurrence_code,
            coalesce(vc.occurrence_code, bc.code) as name,
            coalesce(source,'sispag') as source_file_type,
            bc.description
        from vans_codes vc
        full outer join bank_codes bc
            on vc.occurrence_code = bc.code
        group by 1,2,3,4
    )
    select
        *,
        regexp_extract(name,'(\\w{{2}})?(\\w{{2}})?(\\w{{2}})', 3) as last_code,
        regexp_extract(name,'(\\w{{2}})?(\\w{{2}})(\\w{{2}})', 2) as second_last_code,
        regexp_extract(name,'(\\w{{2}})(\\w{{2}})(\\w{{2}})', 1) as third_last_code,
        now() as ts_load
    from codes
