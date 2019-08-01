#!/usr/bin/env python
import os
import re

from jinja2 import Template

CURR_FOLDER = os.path.realpath(os.path.curdir)


def add_file(task_name):
    file_path = os.path.join(CURR_FOLDER, '{{ cookiecutter.dag_slug }}/spark_jobs', '{}.py'.format(task_name))
    t = Template(os.path.join(CURR_FOLDER, '{{ cookiecutter.dag_slug }}/spark_jobs/job_template.py'))
    with open(file_path, "w+") as f:
        f.write(t.render(task_name=task_name))


if __name__ == '__main__':

    task_names = "{{ cookiecutter.task_names}}.strip().replace(' ', '_').replace('-', '_').split(',')" or []
    for task_name in task_names:
        if re.match(r'^[a-z]\w*', task_name):
            add_file(task_name)

    os.remove(os.path.join(CURR_FOLDER, '{{ cookiecutter.dag_slug }}/spark_jobs/job_template.py'))
