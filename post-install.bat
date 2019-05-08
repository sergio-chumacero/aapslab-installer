@echo off
REM = """
CALL conda install --channel conda-forge --file %cd%\conda_requirements.txt -y
CALL pip install --requirement %cd%\pip_requirements.txt
CALL python -x "%~f0" %
exit /b %errorlevel%
"""
import os
from os.path import join, exists, dirname
import shutil
import json
import stat
from menuinst import install
from jupyterthemes import install_theme
from git import Git
import requests
from requests.exceptions import ConnectionError

base_path = os.environ['USERPROFILE']
conda_path = join(base_path,'AAPS-LAB')
notebook_json_path = join(conda_path,'Menu','notebook.json')
home_directory = join(base_path,'aapslab')
profile_json_path = join(home_directory,'.profile','profile.json')
data_path = join(home_directory,'datos')

def rmtree(top):
    for root, dirs, files in os.walk(top, topdown=False):
        for name in files:
            filename = os.path.join(root, name)
            os.chmod(filename, stat.S_IWUSR)
            os.remove(filename)
        for name in dirs:
            os.rmdir(os.path.join(root, name))
    os.rmdir(top)

def move_or_replace(filename,src,dst):
    if exists(join(src,filename)):
        if exists(join(dst,filename)):
            os.remove(join(dst,filename))
        if not exists(dst):
            os.makedirs(dst)
        os.rename(join(src,filename),join(dst,filename))

def copy_or_replace(filename,src,dst):
    if exists(join(src,filename)):
        if exists(join(dst,filename)):
            os.remove(join(dst,filename))
        if not exists(dst):
            os.makedirs(dst)
        shutil.copy(join(src,filename),join(dst,filename))


# 0. Check Internet Connection

try:
    requests.head('http://www.google.com', verify=False, timeout=5)
    NETWORK_CONNECTED = True
except ConnectionError:
    NETWORK_CONNECTED = False

# 2. Setup Home Directory

def insert_proxy_version():
    if not exists(dirname(profile_json_path)):
        os.makedirs(dirname(profile_json_path))
    with open(profile_json_path,'w') as f:
        json.dump(dict(version='0.0.0'),f)

def clone_and_cleanup():
    install_theme(
        theme='grade3',
        monofont=None,
        tcfontsize=11,
        dffontsize=95,
        cellwidth='88%',
        altprompt=True,
        toolbar=True,
        nbname=True,
        kernellogo=True
    )
    tmp_data_path = join(base_path,'tmp_datos_tmp')

    if exists(tmp_data_path):
        rmtree(tmp_data_path)

    if exists(data_path):
        shutil.copytree(data_path, tmp_data_path)

    with open(profile_json_path,'r') as f:
        profile_json = json.load(f)

    if exists(home_directory):
        rmtree(home_directory)

    Git(dirname(home_directory)).clone('https://github.com/sergio-chumacero/aapslab.git')

    static_path = join(home_directory,'.static')
    i18n_path = join(conda_path,'Lib','site-packages','notebook','i18n','es','LC_MESSAGES')
    custom_path = join(base_path,'.jupyter','custom')

    static_files = ['logo.png','custom.css','nbui.mo','nbui.po','nbjs.json','nbjs.po']
    dst_paths = [custom_path]*2+[i18n_path]*4

    for file,dst in zip(static_files,dst_paths):
        move_or_replace(file,static_path,dst)

    if exists(join(home_directory,'.static')):
        rmtree(join(home_directory,'.static'))

    if exists(join(home_directory,'.gitignore')):
        os.remove(join(home_directory,'.gitignore'))

    if exists(join(home_directory,'version.json')):
        with open(join(home_directory,'version.json'), 'r') as f:
            version = json.load(f).get('version')

        if version:
            if not exists(dirname(profile_json_path)):
                os.makedirs(dirname(profile_json_path))
            
            profile_json['version'] = version
            
            with open(profile_json_path,'w') as f:
                json.dump(profile_json,f)
        else:
            insert_proxy_version()

        os.remove(os.path.join(home_directory,'version.json'))
    else:
        insert_proxy_version()
    
    if exists(data_path):
        rmtree(data_path)

    if exists(tmp_data_path):
        shutil.copytree(tmp_data_path, data_path)
        rmtree(tmp_data_path)

if not os.path.exists(home_directory):
    insert_proxy_version()

    if NETWORK_CONNECTED:
        clone_and_cleanup()
else:
    if NETWORK_CONNECTED:
        r = requests.get('https://raw.githubusercontent.com/sergio-chumacero/aapslab/master/version.json')

        if not os.path.exists(profile_json_path):
            insert_proxy_version()

        with open(profile_json_path, 'r') as f:
            current_version = json.load(f)['version']

        if current_version < r.json()['version']:
            clone_and_cleanup()

        
        
# 3. Setup Menu Shortcut

if exists(join(os.getcwd(),'aapslab.ico')):
    copy_or_replace('aapslab.ico',os.getcwd(),dirname(notebook_json_path))

aapslab_json_path = join(dirname(notebook_json_path),'aapslab.json')
git_json_path = join(dirname(notebook_json_path),'menu-windows.json')

if exists(git_json_path):
    install(git_json_path, remove=True)

if exists(notebook_json_path):
    install(notebook_json_path, remove=True)
    
    with open(notebook_json_path,'r') as f:
        notebook_json = json.load(f)     
        
    notebook_json['menu_items'][0]['name'] = 'AAPS-LAB'
    notebook_json['menu_items'][0]['pyscript'] = '${PYTHON_SCRIPTS}/jupyter-notebook-script.py ' + f'"{home_directory}"'
    notebook_json['menu_items'][0]['icon'] = '${MENU_DIR}/aapslab.ico'
    
    with open(notebook_json_path,'w') as f:
        json.dump(notebook_json, f)
    
    install(notebook_json_path)

elif not exists(aapslab_json_path):
    aapslab_menu_json = {
        'menu_name': 'AAPS-LAB',
        'menu_items': [{
            'name': 'AAPS-LAB',
            'pyscript': '${PYTHON_SCRIPTS}/jupyter-notebook-script.py ' + f'"{home_directory}"',
            'icon': '${MENU_DIR}/aapslab.ico'
        }]
    }

    if exists(dirname(notebook_json_path)):
        with open(aapslab_json_path,'w') as f:
            json.dump(aapslab_menu_json,f)

        install(aapslab_json_path)


# 4. Setup the Jupyter Server Startup Script

server_startup_script = '''
# -*- coding: utf-8 -*-
import re
import sys
import os
from os.path import join, exists, dirname
import shutil
import requests
import json
import stat
from git import Git
from requests.exceptions import ConnectionError
from jupyterthemes import install_theme

base_path = os.environ['USERPROFILE']
conda_path = join(base_path,'AAPS-LAB')
json_path = join(conda_path,'Menu','notebook.json')
home_directory = join(base_path,'aapslab')
profile_json_path = join(home_directory,'.profile','profile.json')
data_path = join(home_directory,'datos')

from notebook.notebookapp import main

def rmtree(top):
    for root, dirs, files in os.walk(top, topdown=False):
        for name in files:
            filename = os.path.join(root, name)
            os.chmod(filename, stat.S_IWUSR)
            os.remove(filename)
        for name in dirs:
            os.rmdir(os.path.join(root, name))
    os.rmdir(top)

def move_or_replace(filename,src,dst):
    if exists(join(src,filename)):
        if exists(join(dst,filename)):
            os.remove(join(dst,filename))
        if not exists(dst):
            os.makedirs(dst)
        os.rename(join(src,filename),join(dst,filename))

try:
    requests.head('http://www.google.com', verify=False, timeout=5)
    NETWORK_CONNECTED = True
except ConnectionError:
    NETWORK_CONNECTED = False

def insert_proxy_version():
    if not exists(dirname(profile_json_path)):
        os.makedirs(dirname(profile_json_path))
    with open(profile_json_path,'w') as f:
        json.dump(dict(version='0.0.0'),f)

def clone_and_cleanup():

    install_theme(
        theme='grade3',
        monofont=None,
        tcfontsize=11,
        dffontsize=95,
        cellwidth='88%',
        altprompt=True,
        toolbar=True,
        nbname=True,
        kernellogo=True
    )

    tmp_data_path = join(base_path,'tmp_datos_tmp')

    if exists(tmp_data_path):
        rmtree(tmp_data_path)

    if exists(data_path):
        shutil.copytree(data_path, tmp_data_path)

    with open(profile_json_path,'r') as f:
        profile_json = json.load(f)

    if exists(home_directory):
        rmtree(home_directory)

    Git(dirname(home_directory)).clone('https://github.com/sergio-chumacero/aapslab.git')

    static_path = join(home_directory,'.static')
    i18n_path = join(conda_path,'Lib','site-packages','notebook','i18n','es','LC_MESSAGES')
    custom_path = join(base_path,'.jupyter','custom')

    static_files = ['logo.png','custom.css','nbui.mo','nbui.po','nbjs.json','nbjs.po']
    dst_paths = [custom_path]*2+[i18n_path]*4

    for file,dst in zip(static_files,dst_paths):
        move_or_replace(file,static_path,dst) 

    if exists(join(home_directory,'.static')):
        rmtree(join(home_directory,'.static'))

    if exists(join(home_directory,'.gitignore')):
        os.remove(join(home_directory,'.gitignore'))

    if exists(join(home_directory,'version.json')):
        with open(join(home_directory,'version.json'), 'r') as f:
            version = json.load(f).get('version')

        if version:
            if not exists(dirname(profile_json_path)):
                os.makedirs(dirname(profile_json_path))
            
            profile_json['version'] = version
            
            with open(profile_json_path,'w') as f:
                json.dump(profile_json,f)
        else:
            insert_proxy_version()

        os.remove(os.path.join(home_directory,'version.json'))
    else:
        insert_proxy_version()
    
    if exists(data_path):
        rmtree(data_path)

    if exists(tmp_data_path):
        shutil.copytree(tmp_data_path, data_path)
        rmtree(tmp_data_path)

if not os.path.exists(home_directory):
    insert_proxy_version()
    if NETWORK_CONNECTED:
        clone_and_cleanup()
else:
    if NETWORK_CONNECTED:
        r = requests.get('https://raw.githubusercontent.com/sergio-chumacero/aapslab/master/version.json')

        with open(profile_json_path, 'r') as f:
            current_version = json.load(f)['version']

        if current_version < r.json()['version']:
            clone_and_cleanup()

os.environ['LANG'] = 'es'

if __name__ == '__main__':
    sys.argv[0] = re.sub(r'(-script\.pyw?|\.exe)?$', '', sys.argv[0])
    sys.exit(main())     
'''

with open(join(conda_path,'Scripts','jupyter-notebook-script.py'), 'w') as f:
    f.write(server_startup_script)

# 5. Setup Kernel Startup Script

kernel_startup_script = '''
import os
from os.path import join
import sys

local_lib = join(os.environ['USERPROFILE'],'aapslab','.lib')
sys.path.insert(0,local_lib)

import tools.widgets as aaps_widgets
'''

if not exists(join(base_path,'.ipython','profile_default','startup')):
    os.makedirs(join(base_path,'.ipython','profile_default','startup'))

with open(join(base_path,'.ipython','profile_default','startup','00_startup.py'),'w') as f:
    f.write(kernel_startup_script)


