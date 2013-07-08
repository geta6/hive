# hive

  fast media broadcaster.

## requirement

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

PAM auth
