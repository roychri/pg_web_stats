FROM ruby:2.5

WORKDIR /pg_web_stats

ENV RACK_ENV=production
COPY Gemfile Gemfile.lock pg_web_stats.gemspec /pg_web_stats/
RUN bundle install

COPY . /pg_web_stats/

EXPOSE 9292
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "9292"]
