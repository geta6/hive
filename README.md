# hive

  fast media broadcaster.

## requirement

* imagemagick
* ffmpeg
* pdftk
* nodectl

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

