DROP TABLE IF EXISTS public.agent_region_hist;

CREATE TABLE IF NOT EXISTS public.agent_region_hist (
DadosAgente_id INT,
regiao_id INT,
dt_start DATETIME,
dt_end DATETIME,
revtype INT,
dt DATETIME,
PRIMARY KEY (DadosAgente_id, regiao_id, dt_start)
);
