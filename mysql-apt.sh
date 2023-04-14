#!/bin/bash

cat <<EOF> /etc/apt/apt.conf
Acquire::http::Proxy "http://127.0.0.1:10080";
Acquire::https::Proxy "https://127.0.0.1:10080";
EOF