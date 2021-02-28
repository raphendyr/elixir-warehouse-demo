FROM debian:bullseye-slim AS build

# install build dependencies
RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update -qqy \
 && apt-get install -qqy \
    build-essential \
    curl \
    git \
    \
    elixir \
    erlang-dev \
    erlang-inets \
    \
    inotify-tools \
    nodejs \
    npm \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
 && mix archive.install hex phx_new 1.5.6 --force \
 && mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix do deps.get, deps.compile

# build assets
COPY priv priv
COPY assets assets

RUN rm -rf ./assets/node_modules && mkdir -p ./assets/node_modules \
 && npm --prefix ./assets ci --progress=false --no-audit --loglevel=error

RUN npm --prefix ./assets run deploy \
 && mix phx.digest

# compile and build release
COPY lib lib
# uncomment COPY if rel/ exists
# COPY rel rel
RUN mix do compile, release


# prepare release image
FROM debian:bullseye-slim AS app

RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update -qqy \
 && apt-get install -qqy \
    openssl \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

WORKDIR /app

RUN chown nobody:nogroup /app

USER nobody:nogroup

COPY --from=build --chown=65534:65534 /app/_build/prod/rel/warehouse ./

ENV HOME=/app

CMD ["bin/warehouse", "start"]
