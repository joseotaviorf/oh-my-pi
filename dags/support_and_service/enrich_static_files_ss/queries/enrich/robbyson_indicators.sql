WITH union_line_indicators AS (
  SELECT
    EXPLODE(MAP(
      "CSAT", MAP(
        "O CSAT é a porcentagem de clientes satisfeitos nas pesquisas de satisfação (CSAT) que enviamos após o atendimento.//
        Este indicador reflete a qualidade do atendimento prestado, baseando-se nas respostas dos clientes.//
        A fórmula de calculo basea-se nos fatores: (tickets_csat_satisfied / tickets_with_csat_score).", 
        ARRAY("tickets_with_csat_score", "tickets_csat_satisfied")
      ),
      "DSAT", MAP(
        "O DSAT é o percentual de clientes insatisfeitos nas pesquisas de satisfação (CSAT) que enviamos após o atendimento.//
        Este indicador destaca a proporção de clientes que não ficaram satisfeitos com o serviço recebido.//
        A fórmula de calculo basea-se nos fatores: (tickets_csat_dissatisfied / tickets_with_csat_score).",
        ARRAY("tickets_with_csat_score", "tickets_csat_dissatisfied")
      ),
      "Resolution Rate", MAP(
        "Índice de resolução no qual os clientes classificam em nossa pesquisa de satisfação (se o problema foi resolvido ou não).//
        A fórmula utilizada é baseda nos fatores (tickets_with_resolution / total_tickets).",
        ARRAY("total_tickets", "tickets_with_resolution")
      ),
      "Recontato", MAP(
        "O objetivo é saber quantos clientes identificados (com sk_user) entram em contato mais que uma vez em um determinado período
        A fórmula de calculo basea-se nos fatores: (total_tickets_recontact / total_tickets).",
        ARRAY("total_tickets", "total_tickets_recontact")
      ),
      "Transferência", MAP(
        "Proporção de atendimentos que geram transferências entre níveis de atendimento.
        A fórmula de calculo basea-se nos fatores: (tickets_transferred / total_tickets).",
        ARRAY("total_tickets", "tickets_transferred")
      ),
      "Reopen", MAP(
        "% de tickets que sofreram reopen (foram 'encerrados' e reabertos pelos clientes em até 2 dias após o encerramento).
        A fórmula de calculo basea-se nos fatores: (ticket_reopenings / total_tickets).",
        ARRAY("total_tickets", "ticket_reopenings")
      ),
      "First Reply", MAP(
        "Primeira resposta do analista durante o atendimento de chat/e-mail
        A fórmula de calculo basea-se nos fatores: (ticket_responses / total_tickets).",
        ARRAY("total_tickets", "ticket_responses")
      ),
      "Backlog Fora do prazo", MAP(
        "São os tickets com status diferente de closed e solved, ou seja, em aberto, e fora do tempo estipulado de atendimento. //
        Para o reporte do indicador, utilizamos sempre a quantidade de backlog do último dia do período reportado, ou seja, no último dia//
        do mês para cada mês, D-1 para o período vigente, e o domingo para a semana. / Utiliza base do metabase porém fazemos ajustes no Databricks.//
        A fórmula de calculo basea-se nos fatores: (backlog_with_exceed_sla, total_tickets).",
        ARRAY("total_tickets", "backlog_with_exceed_sla")
      ),
      "TMA", MAP(
        "Tempo médio de duração do atendimento. A fórmula de calculo basea-se nos fatores: (total_attendance_time, total_tickets).",
        ARRAY("total_tickets", "total_attendance_time")
      ),
      "Produtividade", MAP(
        "Demandas resolvidas do nível de atendimento. A fórmula de calculo basea-se nos fatores: (total_productivity, total_tickets).",
        ARRAY("total_tickets", "total_productivity")
      ),
      "Demanda Recebida", MAP(
        "O volume de demanda que estamos recebend.",
        ARRAY("total_received_demand")
      )
    )) AS (name, attributes),
    "support_and_services" AS context
)
SELECT
  STRING(crc32(name)) AS id_indicator,
  name,
  attributes,
  context,
  NOW() AS ts_load
FROM
  union_line_indicators
