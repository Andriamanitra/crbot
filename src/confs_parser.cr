require "string_scanner"

module Confs
  alias Primitive = String | Int64
  alias Val = Hash(String, Val) | Array(Primitive) | Primitive

  class Error < Exception
  end

  # Parser for a subset of confs (https://github.com/Andriamanitra/confs)
  # syntax. Does not currently support multiline strings or enums.
  class Parser < StringScanner
    NEWLINE = /\s*(#[^\n]*)?\n/

    def initialize(src : String)
      super(src)
      @lineno = 1
      @conf = Hash(String, Val).new
    end

    def parse : Hash(String, Val)
      while section()
        newlines()
        break if eos?
      end
      @conf
    end

    protected def error(reason : String)
      raise Error.new("#{reason} (on line #{@lineno})")
    end

    protected def section
      loc : Hash(String, Val) = @conf
      header.each do |key|
        case v = loc[key]?
        in nil
          new_loc = Hash(String, Val).new
          loc[key] = new_loc
          loc = new_loc
        in Hash(String, Val)
          loc = v
        in Array(Primitive)
        in Primitive
          error("Can't have header with the same name as a value")
        end
      end
      error("Missing a newline after header") if newlines.zero?

      while key = identifier()
        scan(/ *= */).not_nil!
        loc[key] = value.not_nil!
        newlines()
      end
      loc
    end

    protected def header : Array(String)
      scan(/\[/).not_nil!
      res = [] of String
      res << identifier().not_nil!
      while scan(/\./)
        res << identifier().not_nil!
      end
      scan(/\]/).not_nil!
      res
    rescue
      error("Invalid header")
    end

    protected def identifier : String?
      scan(/[a-z_]+/)
    end

    protected def newline
      m = scan(NEWLINE)
      @lineno += 1 if m
      m
    end

    protected def newlines : Int
      count = 0
      while m = scan(NEWLINE)
        count += 1
      end
      @lineno += count
      count
    end

    protected def value : Primitive | Array(Primitive)
      if newline()
        list().not_nil!
      else
        (int() || str()).not_nil!
      end
    end

    protected def int : Int64?
      if num = scan(/[+-]?[0-9]+/)
        error("Missing a newline after number") unless newline()
        num.to_i64
      end
    end

    protected def str : String?
      if scan(/"/)
        res = scan(/[^"]*/)
        error("Unclosed string") unless scan(/"/)
        error("Missing a newline after string") unless newline()
        res
      end
    end

    protected def multiline_string : String?
      nil
    end

    protected def list : Array(Primitive)?
      lst = [] of Primitive
      while scan(/- ?/)
        elem = int() || str()
        error("Invalid list element") if elem.nil?
        lst.push(elem)
      end
      lst.empty? ? nil : lst
    end
  end
end

struct BotConfig
  getter server, port, username, nickname, channels, commands

  def initialize(
    @server : String,
    @port : Int32,
    @username : String,
    @nickname : String,
    @channels : Array(String),
    @commands : Hash(String, Hash(String, String))
  )
  end

  def self.from_file(fname : String)
    s = File.read(fname)
    confs = Confs::Parser.new(s).parse
    # this is pretty hacky to work around the type system...
    connection_conf = confs["connection"].as(Hash(String, Confs::Val))
    channels = connection_conf["channels"].as(Array).map(&.as(String))
    commands = confs["commands"].as(Hash(String, Confs::Val))
      .transform_values { |v| v.as(Hash(String, Confs::Val))
        .transform_values { |w| w.as(String) } }
    new(
      connection_conf["server"].as(String),
      connection_conf["port"].as(Int64).to_i32,
      connection_conf["username"].as(String),
      connection_conf["nickname"].as(String),
      channels,
      commands,
    )
  end
end
