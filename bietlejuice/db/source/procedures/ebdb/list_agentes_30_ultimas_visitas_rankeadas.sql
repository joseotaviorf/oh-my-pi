CREATE PROCEDURE list_agentes_30_ultimas_visitas_rankeadas()
BEGIN
SELECT
`Dia`,
`Hora visita`,
`Dia avaliação`,
`Código`,
`Bairro`,
`Visitante`,
`Email do visitante`,
`Agente`,
`Status`,
`FUP`,
`Avaliação`,
`Pontualidade`,
`Corretor bem informado`,
`Gentileza`,
`Imóvel igual ao anúncio`,
`Outro motivo (por favor, conte abaixo) (Bom)`,
`Corretor se atrasou`,
`Corretor sem informações`,
`Corretor não foi gentil`,
`Imóvel não corresponde ao anúncio`,
`Outro motivo (por favor, conte abaixo) (Ruim)`,
`Outros`
FROM
(
	select
	*,
    @num:=if(@agente = agente_id, @num+1, 1) as posicao_visita,
    @agente:=agente_id as 'Nome Agente'
	from
	(
		SELECT DISTINCT V.dia AS 'Dia', V.slot AS 'Slot', V.agente_id,V.id
		,DATE_FORMAT(date_add(date_add(A.data, INTERVAL FLOOR(((A.slotDia * 15) / 60) + 8) HOUR), INTERVAL((A.slotDia * 15) % 60) MINUTE), '%H:%i') AS 'Hora visita'
		,CONVERT_TZ(R.criadoEm, 'UTC', 'America/Sao_Paulo') AS 'Dia avaliação'
		,V.codigo AS 'Código',I.bairro AS 'Bairro',U.nome AS 'Visitante',U.email AS 'Email do visitante'
-- 		,(SELECT U2.nome
-- 		FROM Agendamento A
-- 		INNER JOIN Usuario U2 ON U2.dadosAgente_id = A.agente_id
-- 		WHERE A.visita_id = V.id
-- 		AND status='Realizado'
-- 		LIMIT 1) AS 'Agente'
		,(SELECT U2.nome from Usuario U2 WHERE U2.id = V.agente_id) as 'Agente'
		,(SELECT U2.email from Usuario U2 WHERE U2.id = V.agente_id) as 'Agente_email',
		(SELECT da.ativo from Usuario U2 left join DadosAgente da on U2.dadosAgente_id = da.id WHERE U2.id = V.agente_id) as 'Agente_ativo',
		A.STATUS AS 'Status',
		A.fupVisita AS 'FUP'
		,CASE
		WHEN R.rating < 0
		THEN 'Visita não aconteceu.'
		ELSE CONCAT (
		""
		,R.rating
		)
		END AS 'Avaliação'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Pontualidade') AS 'Pontualidade'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Corretor bem informado') AS 'Corretor bem informado'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Gentileza') AS 'Gentileza'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Imóvel igual ao anúncio') AS 'Imóvel igual ao anúncio'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Outro motivo (por favor, conte abaixo)'
		AND RL.ratingReference >= 4) AS 'Outro motivo (por favor, conte abaixo) (Bom)'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Corretor se atrasou') AS 'Corretor se atrasou'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Corretor sem informações') AS 'Corretor sem informações'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Corretor não foi gentil') AS 'Corretor não foi gentil'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Imóvel não corresponde ao anúncio') AS 'Imóvel não corresponde ao anúncio'
		,(SELECT COUNT(*)
		FROM RealEstateAgentRating_RatingLabel RR
		INNER JOIN RatingLabel RL ON RL.id = RR.ratingLabels_id
		WHERE RealEstateAgentRating_id = V.realEstateAgentRating_id
		AND RL.label = 'Outro motivo (por favor, conte abaixo)'
		AND RL.ratingReference <= 3) AS 'Outro motivo (por favor, conte abaixo) (Ruim)'
		,R.complementaryInfo AS 'Outros'
		FROM Visita V
		INNER JOIN Usuario U ON U.id = V.visitante_id
		INNER JOIN RealEstateAgentRating R ON R.id = V.realEstateAgentRating_id
		INNER JOIN Device D ON D.usuario_id = V.visitante_id
		INNER JOIN Agendamento A ON A.visita_id = V.id
		INNER JOIN Imovel I ON I.id = A.imovel_id
		WHERE V.realEstateAgentRating_id IS NOT NULL
		AND A.status='Realizado'
		AND D.mobileApp = 'Inquilinos' AND A.fupVisita = 'VaiNegociar' AND R.rating >= 0
	) tmp
	cross join
		(select @num:=0, @agente:='') as dummy
	where `Imóvel não corresponde ao anúncio`=0
	ORDER BY agente_id, Dia desc, Slot desc
) x
where x.posicao_visita <=30;
END