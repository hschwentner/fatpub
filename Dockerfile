FROM perl:5.34

COPY . /usr/src/markua2aw

WORKDIR /data
ENTRYPOINT [ "perl", "/usr/src/markua2aw/bin/fatpub" ]
