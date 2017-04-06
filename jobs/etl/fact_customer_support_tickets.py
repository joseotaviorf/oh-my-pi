from zenpy.lib.api_objects import Ticket, User
from zenpy import Zenpy
from datetime import datetime, timedelta

# Create a Zenpy instance
zenpy_client = Zenpy(subdomain='quintoandar', email='compras@quintoandar.com.br', password='o5aelpc.')

start_time = datetime.strptime('2017-03-09 17:21:00', '%Y-%m-%d %H:%M:%S')
tickets = zenpy_client.tickets.events(start_time=start_time)

for t in tickets:
    print(t.ticket)

