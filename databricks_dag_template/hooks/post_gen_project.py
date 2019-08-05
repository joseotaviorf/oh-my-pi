#!/usr/bin/env python
import fileinput
import os
import re
from shutil import copyfile

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("post_gen_project")

CURR_FOLDER = os.path.realpath(os.path.curdir)


@logger
def add_file(task_name):
    dest_path = os.path.join(CURR_FOLDER, "spark_jobs", "{}.py".format(task_name))
    source_path = os.path.join(CURR_FOLDER, "spark_jobs/job_template.py")
    copyfile(source_path, dest_path)

    with fileinput.input(dest_path, inplace=True) as f:
        for line in f:
            print(line.replace('"JOB_NAME"', f'"{task_name}"'), end="")


if __name__ == "__main__":

    task_names = (
        "{{ cookiecutter.task_names }}".strip()
        .replace(" ", "_")
        .replace("-", "_")
        .split(",")
        or []
    )
    for task_name in task_names:
        if re.match(r"^[a-z]\w*", task_name):
            add_file(task_name)

    os.remove(os.path.join(CURR_FOLDER, "spark_jobs/job_template.py"))
