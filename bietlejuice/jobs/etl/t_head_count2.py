import gspread
from oauth2client.service_account import ServiceAccountCredentials

scope = ['https://www.googleapis.com/auth/spreadsheets.readonly']

credentials = ServiceAccountCredentials.from_json_keyfile_name('/home/rafael/Downloads/HeadCount-6c92e958296e.json',
                                                               scope)

gc = gspread.authorize(credentials)
sheet_name = '2018-09-28'
wks = gc.open_by_key('1f5Udb3qrhOoN2G6w1N1T0sAmj4QPOxgVOgGh1ewgfPI')  # ("1vOjDG1RYHRozDTtjcodgD9mnrmNqf1e5d0pBXeMiv28")
print wks.worksheets()
try:
    wok = wks.worksheet(sheet_name)
except Exception as e:
    raise Exception(e.message)

print wok.col_values(2)
