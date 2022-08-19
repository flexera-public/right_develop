FROM ruby:2.1.10 AS right_develop

RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libxml2 \
    libxslt-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

LABEL Name=right_develop Version=0.0.1

EXPOSE 3000

# throw errors if Gemfile has been modified since Gemfile.lock
# RUN bundle config --global frozen 1

WORKDIR /right_develop
# COPY . /right_develop
# COPY Gemfile Gemfile.lock /right_develop/

RUN bundle install


