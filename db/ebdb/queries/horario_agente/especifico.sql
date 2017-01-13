SELECT 
  nome,  
  agente_id,
  data,                
  folga,                           
  disponivel08as09,
  disponivel09as10,
  disponivel10as11,
  disponivel11as12,
  disponivel12as13,
  disponivel13as14,
  disponivel14as15,
  disponivel15as16,
  disponivel16as17,
  disponivel17as18,
  disponivel18as19,
  disponivel19as20
FROM 
(
  SELECT *, MAX(atualizadoEm)
  FROM HorarioEspecificoAgente
  WHERE data < NOW()
  GROUP BY agente_id, data
) AS horarios

LEFT JOIN Usuario u
  ON u.dadosAgente_id = horarios.agente_id

 where
  horarios.agente_id = 120  

ORDER BY data 
DESC;