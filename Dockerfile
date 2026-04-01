FROM perl:5.42

COPY . /usr/src/fatpub

WORKDIR /data
ENTRYPOINT [ "perl", "/usr/src/fatpub/bin/fatpub" ]
