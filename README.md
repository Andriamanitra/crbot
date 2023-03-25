# crbot

just another irc bot


## Usage

1. `shards build`
1. Edit configuration file (`bot.confs`) to add commands and specify server and nickname etc.
1. `BOT_PASS=hunter2 ./bin/crbot`

Or if you have [just](https://github.com/casey/just), you can
build & run with `just build run`. `just` will automatically read the BOT_PASS
environment variable from `.env` file if it exists.
