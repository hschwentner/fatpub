FROM perl:5.34

COPY . /usr/src/fatpub

WORKDIR /data
ENTRYPOINT [ "perl", "/usr/src/fatpub/bin/fatpub" ]
