FROM postgres:17

WORKDIR APP

COPY ./init_database_for_zitadel.sh ./init_database_for_zitadel.sh

ENTRYPOINT ["sh", "./init_database_for_zitadel.sh"]
CMD ["exit", "0"]
