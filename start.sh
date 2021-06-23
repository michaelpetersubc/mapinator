#! /bin/bash
gunicorn -w 4 -b 0.0.0.0:8025 -D jobmarket:server
