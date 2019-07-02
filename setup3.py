from setuptools import setup, find_packages

with open('requirements3.txt') as f:
    install_requires = [line for line in f.read().splitlines() if len(line) > 0]

exclude_libs = ['python-logger==0.1.3']

for library in exclude_libs:
    install_requires.remove(library)

setup(
    name='bi-etl-ejuice',
    version='0.1.0',
    description='bi-etl-ejuice module',
    author='Data Engineering Team',
    packages=find_packages(),
    install_requires=install_requires,
    dependency_links=[
        'https://quintoandar.github.io/python-package-server/'
    ]
)
