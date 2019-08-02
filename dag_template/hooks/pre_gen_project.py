import re
import sys
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("pren_gen_project")

NAME_REGEX = r"^[a-z]\w*"

dag_slug = "{{ cookiecutter.dag_slug }}"
if not dag_slug or not re.match(NAME_REGEX, dag_slug):
    logger.error("msg=The dag_slug (%s) is invalid. It must match the regexp `%s`." % (dag_slug, NAME_REGEX))
    sys.exit(1)

task_names = "{{ cookiecutter.task_names }}".replace(' ', '_').replace('-', '_').split(',')
for task_name in task_names:
    if not task_name or not re.match(NAME_REGEX, task_name):
        logger.error(
            "msg=The name of task (%s) is invalid. It must match the regexp %s. "
            "Separate task names with a comma (,)" % (task_name, NAME_REGEX)
        )
        sys.exit(1)

dag_start_date = "{{ cookiecutter.dag_start_date }}"
try:
    datetime.strptime(dag_start_date, '%Y-%m-%d')
except ValueError as e:
    logger.error(
        "msg=The start date of the dag (%s) is invalid. Follow format YYYY-MM-DD." % dag_start_date)
    sys.exit(1)

dag_max_active_runs = "{{ cookiecutter.dag_max_active_runs }}"
try:
    int(dag_max_active_runs)
except ValueError as e:
    logger.error("msg=The value of max active runs (%s) is invalid. It must be an integer." % dag_max_active_runs)
    sys.exit(1)

dag_catchup = "{{ cookiecutter.dag_catchup }}"
if dag_catchup not in ("False", "True"):
    logger.error("msg=The value of dag catchup (%s) is invalid. It must be True or False." % dag_catchup)
    sys.exit(1)
