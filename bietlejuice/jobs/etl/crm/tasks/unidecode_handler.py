import json
from datetime import datetime

from unidecode import unidecode


class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.isoformat(' ') if obj.year >= 1900 else obj.replace(year=obj.year + 2000)

        return unidecode(unicode(str(obj)))
