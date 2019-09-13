import %../httpd.reb
wait srv: open [scheme: 'httpd 8000 [render "Hello"]]
