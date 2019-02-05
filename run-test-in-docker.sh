#!/bin/sh

# Preparation
docker build -t pg_web_stats_test .
docker run \
   -e POSTGRES_PASSWORD=secret \
   -e POSTGRES_USER=postgres \
   -e POSTGRES_DB=pgwebstats \
   --name pg_web_stats_postgres \
   --health-cmd 'pg_isready -U postgres -d pgwebstats' \
   --health-start-period 15s \
   --health-interval 1s \
   -d \
   postgres:9.6-alpine \
       -c shared_preload_libraries='pg_stat_statements' \
       -c pg_stat_statements.max=10000 \
       -c pg_stat_statements.track=all
echo "Waiting for postgres to be ready"
docker logs pg_web_stats_postgres > /tmp/pwslogs
C=`grep -c 'ready for start up' /tmp/pwslogs`
while [ $C != "1" ]; do
    sleep 1
    docker logs pg_web_stats_postgres > /tmp/pwslogs
    C=`grep -c 'ready for start up' /tmp/pwslogs`
done

STATUS=`docker inspect -f {{.State.Health.Status}} pg_web_stats_postgres`
while [ $STATUS != "healthy" ]; do
    sleep 1;
    STATUS=`docker inspect -f {{.State.Health.Status}} pg_web_stats_postgres`
done
IP=$(docker inspect pg_web_stats_postgres | jq -r '.[0].NetworkSettings.IPAddress')

# Run the tests
docker run --rm \
   -e POSTGRES_DB_NAME=pgwebstats \
   -e POSTGRES_DB_HOST=${IP} \
   -e POSTGRES_DB_USER=postgres \
   -e POSTGRES_DB_PASSWORD=secret \
   -e POSTGRES_DB_PORT=5432 \
   pg_web_stats_test \
       bundle exec rake

# Cleanup
docker stop pg_web_stats_postgres
docker rm pg_web_stats_postgres
docker rmi pg_web_stats_test
