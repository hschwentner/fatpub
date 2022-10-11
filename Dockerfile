FROM perl:5.36

COPY . /usr/src/fatpub

WORKDIR /data
ENTRYPOINT [ "perl", "/usr/src/fatpub/bin/fatpub" ]
