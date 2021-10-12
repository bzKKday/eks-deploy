FROM python:3.8-alpine

RUN apk --no-cache add curl ca-certificates bash jq groff less
RUN pip --no-cache-dir install awscli deepmerge

ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.15.10/2020-02-22/bin/linux/amd64/aws-iam-authenticator /usr/bin/aws-iam-authenticator
RUN chmod +x /usr/bin/aws-iam-authenticator

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["help"]
