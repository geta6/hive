# hive

  fast media broadcaster.

## requirement

* nginx (>= 1.4.0 or TCP proxy patched)
* imagemagick
* ffmpeg
* pdftk
* python draxoft.auth.pam
* nodectl (>= 0.3.7)

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
cp config/nodectl.json.sample .nodectl.json
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

  location ~* \.html$ {
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
{
  "name": "Your app name",
  "port": 3000,
  "env": "production",
  "assets": "assets",
  "output": "public",
  "minify": true,
  "main": "config/app.coffee",
  "exec": "config/ini.coffee",
  "setenv": {
    "ROOTDIR": "root directory for content",
    "MONGODB": "mongodb uri"
    "SESSION_SECRET": "session secret string",
  }
}
```

## user authentication

PAM authentication.

Use localuser username and password.

