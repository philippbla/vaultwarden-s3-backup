FROM alpine:3.20

RUN apk -v --update add \
        python3 \
        py3-pip \
        groff \
        less \
        curl \
        py3-crcmod \
        bash \
        libc6-compat \
        gnupg \
        coreutils \
        gzip \
        sqlite \
        && \
    pip3 install --break-system-packages --upgrade awscli s3cmd python-magic six && \
    rm /var/cache/apk/*

RUN addgroup -S cloudbackup && adduser -S cloudbackup -G cloudbackup -u 1000
RUN mkdir /cloudbackup && chown -Rf cloudbackup:cloudbackup /cloudbackup
RUN mkdir /app && chown -Rf cloudbackup:cloudbackup /app

ENV DATA_DIR='/data' \
    S3_ACCESS_KEY_ID=NONE \
    S3_SECRET_ACCESS_KEY=NONE \
    S3_BUCKET=NONE \
    S3_PREFIX='backup' \
    S3_S3V4=no \
    RETENTION_DAYS=30 \
    BACKUP_FILE_DATE_FORMAT='%Y-%m-%dT%H_%M_%SZ' \
    SKIP_SENDS='true'

WORKDIR /app

ADD lifecycle.json.tmpl lifecycle.json.tmpl
ADD run.sh run.sh
ADD includes.sh includes.sh
ADD backup.sh backup.sh
ADD restore.sh restore.sh

USER cloudbackup

CMD ["sh", "run.sh"]