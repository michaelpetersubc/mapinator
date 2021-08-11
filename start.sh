#! /bin/bash
gunicorn -w 4 -b 0.0.0.0:8025 -D jobmarket:server --access-logfile /home/peters/dash_logs/access_log --error-logfile /home/peters/dash_logs/error_log 
