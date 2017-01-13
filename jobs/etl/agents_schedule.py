import datetime
import petl
from jobs.base.base_etl import BaseETL, EnumDb, EnumDbType

# ################ PROVISORIO #################
descredenciados = {
    95: datetime.datetime(2016, 9, 16).date(),  # Igor Pinto Alli
    115: datetime.datetime(2016, 10, 25).date(),  # Carlos Santos Goncalves
    117: datetime.datetime(2016, 10, 25).date(),  # Marli Martins Pedreira
    123: datetime.datetime(2016, 11, 8).date(),  # Jessika Gomes Pires Silva
    136: datetime.datetime(2016, 11, 8).date(),  # Ricardo Lima Viana
    141: datetime.datetime(2016, 12, 8).date()}  # Regiane Santana Izidoro
# #############################################

db = BaseETL.get_connection(db_enum=EnumDb.QuintoAndar_ebdb)

cursor = db.cursor()

cursor.execute("""
SELECT  agente_id,
        atualizadoEm,
        diaDaSemana,
        horarios_disponivel08as09,
        horarios_disponivel09as10,
        horarios_disponivel10as11,
        horarios_disponivel11as12,
        horarios_disponivel12as13,
        horarios_disponivel13as14,
        horarios_disponivel14as15,
        horarios_disponivel15as16,
        horarios_disponivel16as17,
        horarios_disponivel17as18,
        horarios_disponivel18as19,
        horarios_disponivel19as20
FROM HorarioSemanalAgente_AUD
ORDER BY agente_id, diaDaSemana, atualizadoEm ASC
""")

horario_semanal = []
for row in cursor.fetchall():
    horario_semanal.append([])
    for element in row:
        horario_semanal[-1].append(element)

horarios = {}

current_agent = -1
current_weekday = -1
last_update = 0
current_date = 0
for index in range(len(horario_semanal)):
    row = horario_semanal[index]

    if current_date == 0:
        current_weekday = row[2]
        current_agent = row[0]
        last_update = row[1]
        current_date = row[1] + datetime.timedelta(
            days=current_weekday + 7*(last_update.weekday()+1 > current_weekday) - (last_update.weekday() + 1))
        continue

    if current_weekday != row[2] or current_agent != row[0]:

        limit = 0
        if current_agent in descredenciados:
            limit = descredenciados[current_agent]
        else:
            limit = datetime.datetime.today().date()

        while current_date.date() < limit:
            last = horario_semanal[index-1]
            horarios[(current_agent, current_date.date())] = last[3:]
            current_date += datetime.timedelta(days=7)

    else:

        limit = 0
        if current_agent in descredenciados:
            limit = descredenciados[current_agent]
        else:
            limit = row[1].date()

        while current_date.date() < limit:
            last = horario_semanal[index - 1]
            horarios[(current_agent, current_date.date())] = last[3:]
            current_date += datetime.timedelta(days=7)

    current_agent = row[0]
    current_weekday = row[2]
    last_update = row[1]
    current_date = last_update + datetime.timedelta(
        days=current_weekday + 7*(last_update.weekday()+1 > current_weekday) - (last_update.weekday() + 1))


cursor.execute("""
SELECT  agente_id,
        data,
        folga,
        disponivel8as9,
        disponivel9as10,
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
FROM HorarioEspecificoAgente
""")

for row in cursor.fetchall():
    key = (row[0], row[1])
    if key in horarios:
        if row[2]:
            horarios[key] = [0] * 12
        else:
            horarios[key] = row[3:]

list_horarios = []
for key, value in horarios.iteritems():
    temp = [key[0], key[1]]
    temp.extend(value)
    list_horarios.append(temp)

table = petl.pushheader(list_horarios, [
    'agente_id',
    'data',
    'disponivel08as09',
    'disponivel09as10',
    'disponivel10as11',
    'disponivel11as12',
    'disponivel12as13',
    'disponivel13as14',
    'disponivel14as15',
    'disponivel15as16',
    'disponivel16as17',
    'disponivel17as18',
    'disponivel18as19',
    'disponivel19as20'
])

BaseETL.bulk_insert(
    table=table,
    table_name='agent_schedule',
    db_enum=EnumDb.BI_ODS,
    append=False,
    commit=True
)

db.close()
