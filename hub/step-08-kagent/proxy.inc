proxy_pass http://kagent_controller;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-User-Id $guard_user;
# Agent answers stream back as server-sent events over tens of seconds.
proxy_buffering off;
proxy_cache off;
proxy_read_timeout 1800s;
proxy_send_timeout 1800s;
