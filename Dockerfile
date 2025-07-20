# syntax = docker/dockerfile:1
ARG RUBY_VERSION=3.2.8
FROM registry.docker.com/library/ruby:${RUBY_VERSION}-slim AS build

# Install build-time dependencies (including libyaml-dev for psych)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libyaml-dev \
      libpq-dev \
      libvips-dev pkg-config \
      nodejs \
      yarn && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Copy and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' && \
    bundle config set without 'development test' && \
    bundle install --jobs=4 --retry=3 && \
    rm -rf /usr/local/bundle/cache/*.gem

# Copy the rest of the app
COPY . .

# Precompile assets (needs nodejs & yarn installed above)
ENV RAILS_ENV=production \
    SECRET_KEY_BASE=dummy
RUN bin/rails assets:precompile

# Precompile bootsnap for faster boot (optional)
RUN bundle exec bootsnap precompile --gemfile

# ------------------------------------------------------------------------------

FROM registry.docker.com/library/ruby:${RUBY_VERSION}-slim AS runtime

# Install only runtime deps
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libvips \
      postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /rails

COPY Gemfile Gemfile.lock ./

# Copy in gems and app code from build stage
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails        /rails

# Environment for runtime
ENV RAILS_ENV="production" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# Create a non-root user and fix permissions
RUN useradd --create-home --shell /bin/bash rails && \
    chown -R rails:rails /rails /usr/local/bundle

USER rails

EXPOSE 3000

# Use Rails’ default Docker entrypoint (handles db setup, etc.)
ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
