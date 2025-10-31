FROM elixir:1.19-slim

WORKDIR /app
COPY . .

RUN apt-get update \
    && apt-get install -y build-essential libssl-dev libncurses5 libstdc++6 ca-certificates wget git \
    && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get && MIX_ENV=prod mix release

ENV ERL_FLAGS="+P 65536 +hms 8M +hmbs 32M"

CMD ["_build/prod/rel/rclip/bin/rclip", "start","+P", "65536", "+hms", "8M", "+hmbs", "32M"]
