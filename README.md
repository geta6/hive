# hive

  fast media broadcaster.

## requirement

* nginx (>= 1.4.0 or TCP proxy patched)
* imagemagick
* ffmpeg
* pdftk
* python draxoft.auth.pam
* nodectl

```
pip install draxoft.auth.pam
npm -g install nodectl
```

### debian

```
apt-get install imagemagick ffmpeg pdftk
```

### osx
```
brew install imagemagick ffmpeg
```

[pdftk](http://www.pdflabs.com/tools/pdftk-the-pdf-toolkit/) is only GUI installer.


## usage

```
npm i -g nodectl
npm i
mv config/nodectl.json.sample .nodectl.json
nodectl
```

## nginx setup

hive not includes static supplier.

```
upstream nodejs {
  server  127.0.0.1:3000;
}

server {
  listen       80 default_server;
  charset      UTF-8;
  server_name  _;
  root         /path/to/hive/public;
  index        index.html;

  location ~* ^(\/css|\/js|\/img|\/lib) {
    access_log  off;
    expires     max;
  }

  location ~* (\.html|\.txt|\.ico)$ {
    access_log  off;
    expires     max;
  }

  location ~* ^(\/.+)$ {
    proxy_read_timeout     300;
    proxy_connect_timeout  300;
    proxy_set_header       Host               $host;
    proxy_set_header       X-Real-IP          $remote_addr;
    proxy_set_header       X-Forwarded-Host   $host;
    proxy_set_header       X-Forwarded-Server $host;
    proxy_set_header       X-Forwarded-For    $proxy_add_x_forwarded_for;
    proxy_set_header       X-Document-Root    $document_root;
    proxy_set_header       X-Document-URI     $document_uri;
    proxy_set_header       Upgrade            $http_upgrade;
    proxy_set_header       Connection         "Upgrade";
    proxy_pass             http://nodejs;
  }
}
```

## config

edit `.nodectl.json`

```
"port" : port
"env"  : development or production
"setenv": {
  "ROOTDIR"        : media root directory
  "SESSION_SECRET" : random text for session value encrypt/decrypt
  "SITENAME"       : site name
}
```

## user authentication

PAM authentication.

Use localuser username and password.
