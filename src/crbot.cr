require "socket"
require "openssl"
require "./confs_parser.cr"

module Irc
  VERSION           = "0.1.0"
  IRC_MESSAGE_REGEX = /(:(?<prefix>[\S]+)\s+)?(?<command>[A-z]+|[0-9]{3}) (?<params>[^:]*)(:(?<trailing>.*))?/

  record IrcMessage,
    raw : String,
    prefix : String?,
    command : String,
    params : Array(String) do
    def privmsg?
      @command == "PRIVMSG"
    end
  end
  record Handler, block : IrcMessage ->

  class PrivMsg
    def initialize(msg : IrcMessage)
      if msg.privmsg?
        @msg = msg
      else
        raise "can't make PrivMsg out of something other than PRIVMSG"
      end
    end

    def sender
      @msg.prefix.not_nil!.split('!', 2).first
    end

    def channel
      @msg.params.first
    end

    def content
      @msg.params.last
    end

    def to_s(io)
      io << "#{channel} | <#{sender}> #{content}"
    end
  end

  class Client
    def initialize(@server : String, @port : Int32, @user : String, @nick : String)
      @listening = false
      @channels = [] of String
      @handlers = Hash(String, Array(Handler)).new { |h, k| h[k] = Array(Handler).new }

      # Connect to IRC
      sock = TCPSocket.new(@server, @port)
      @conn = OpenSSL::SSL::Socket::Client.new(sock)
      send("PASS #{ENV["BOT_PASS"]}", silent: true)
      send("USER #{@user}")
      send("NICK #{@nick}")

      on("PING") do |ircmsg|
        send(ircmsg.raw.sub("PING", "PONG"))
      end

      listen
    end

    def listen
      @listening = true
      spawn do
        while @listening
          sleep(10.milliseconds)
          msg = @conn.gets
          next if msg.nil?
          puts ">> #{msg}" unless msg.empty?
          handle_msg(msg)
        end
        puts "stopped listening!"
      end
    end

    def handle_msg(msg)
      if groups = msg.match(IRC_MESSAGE_REGEX)
        prefix = groups["prefix"]?
        command = groups["command"]
        params = groups["params"].split
        params << groups["trailing"] if groups["trailing"]?

        parsed_message = IrcMessage.new(msg, prefix, command, params)
        @handlers[command].each(&.block.call(parsed_message))
      else
        STDERR.puts("ERROR: Couldn't handle message:\n#{msg}")
      end
    end

    def on(command : String, &block : IrcMessage ->)
      @handlers[command] << Handler.new(block)
    end

    def clear_handlers!
      @handlers.clear
    end

    def quit
      send("QUIT")
      @listening = false
    end

    def join(chan : String)
      send("JOIN #{chan}")
    end

    def part(chan : String)
      send("PART #{chan}")
    end

    def say(ch, msg : String)
      send("PRIVMSG #{ch} :#{msg}")
    end

    def send(s : String, silent : Bool = false)
      puts "<< #{s}" unless silent
      @conn.puts(s)
      @conn.flush
    end
  end
end

def add_handlers(bot, commands)
  bot.on("PRIVMSG") do |ircmsg|
    msg = Irc::PrivMsg.new(ircmsg)
    commands.each do |cmdname, cmd|
      if msg.content.starts_with?(cmd["pattern"])
        bot.say(msg.channel, cmd["response"])
      end
    end
  end
end

config = BotConfig.from_file("bot.confs")
bot = Irc::Client.new(
  server: config.server,
  port: config.port,
  user: config.username,
  nick: config.nickname,
)

add_handlers(bot, config.commands)

config.channels.each do |channel_name|
  bot.join(channel_name)
end

# allow user to type instructions in terminal to manually do things
while g = gets
  if g.starts_with?('q')
    bot.quit
    break
  elsif g.starts_with?("reload")
    bot.clear_handlers!
    config = BotConfig.from_file("bot.confs")
    add_handlers(bot, config.commands)
    puts "commands reloaded!"
  elsif g.starts_with?('>')
    bot.say(config.channels[0], g[1..])
  else
    bot.send(g)
  end
end
