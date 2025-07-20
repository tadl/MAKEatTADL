# syntax = docker/dockerfile:1

########################################
# 1) Build Stage
########################################
ARG RUBY_VERSION=3.2.8
FROM registry.docker.com/library/ruby:${RUBY_VERSION}-slim AS build

# Install build-time packages (including libyaml-dev for psych)
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

# Copy Gemfiles and install gems in deployment mode
COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment 'true' && \
    bundle config set without 'development test' && \
    bundle install --jobs=4 --retry=3 && \
    rm -rf /usr/local/bundle/cache/*.gem

# Copy the rest of the application code
COPY . .

# Precompile assets (needs NODE and YARN)
ENV RAILS_ENV=production \
    SECRET_KEY_BASE=dummy
RUN bin/rails assets:precompile

# Precompile Bootsnap cache for faster startup
RUN bundle exec bootsnap precompile --gemfile

########################################
# 2) Runtime Stage
########################################
FROM registry.docker.com/library/ruby:${RUBY_VERSION}-slim AS runtime

# Install only runtime packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      libvips \
      postgresql-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Copy Gemfiles so Bundler can load the spec
COPY Gemfile Gemfile.lock ./

# Copy over the bundled gems and application code
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails        /rails

# Configure Bundler to use the vendored gems
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development test" \
    GEM_HOME=/usr/local/bundle

# Create a non-root user and fix permissions
RUN useradd --create-home --shell /bin/bash rails && \
    chown -R rails:rails /rails /usr/local/bundle

USER rails

EXPOSE 3000

# Use Rails’ default Docker entrypoint (handles DB setup, migrations, etc.)
ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
