FROM perl:5.38

COPY . /usr/src/fatpub

WORKDIR /data
ENTRYPOINT [ "perl", "/usr/src/fatpub/bin/fatpub" ]
