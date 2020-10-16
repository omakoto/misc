#!/usr/bin/python3

import sys
import signal
import socket
import time
from datetime import datetime
import argparse

parser = argparse.ArgumentParser(description='Simple time serve')
parser.add_argument('-p', '--port', metavar='P', type=int, default=8000, help='Listening port')
args = parser.parse_args()

HOST = '0.0.0.0'
PORT = args.port

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    def signal_handler(sig, frame):
        print('Terminating...')
        s.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    s.bind((HOST, PORT))
    s.listen()
    soc = s
    while True:
        print(f'Listening on http://{HOST}:{PORT}/ ...')
        conn, addr = s.accept()
        with conn:
            try:
                print('Connected by', addr)
                conn.sendall(b'HTTP/1.0 200\r\n\r\n')
                while True:
                    now = datetime.now()
                    conn.sendall(bytes(now.strftime("%Y-%m-%d %H:%M:%S\n"), 'utf-8'))
                    time.sleep(1)
            except ConnectionError:
                print('Client gone')
