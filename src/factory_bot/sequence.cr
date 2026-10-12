# Sequence — порт factory_bot/sequence.rb.
#
# EnumeratorAdapter порта знает два вида начальных значений: Int64
# (целочисленный счётчик) и Array (перечислимое). set_value/seek-поиск
# поддержаны для целых напрямую, для массивов — перемоткой по индексу.
# Scope-семантика (`sequence.next(scope)` с instance_exec) неприменима:
# блок захвачен как Proc(Int64, FBValue) и выполняется без смены self.

module FactoryBot
  # Порт factory_bot/uri_manager.rb (упрощён): URI последовательности —
  # путь определения, склеенный "/" (":factory/:trait/:sequence"), пробелы
  # заменяются на "_". Нужен для rewind_sequence/set_sequence и для
  # дедупликации inline-последовательностей в иерархии фабрик.
  module UriManager
    def self.build_uri(*parts : String | Symbol) : String?
      return nil if parts.empty?
      joined = parts.map(&.to_s).join("/")
        .sub(/\A\/+/, "")
        .sub(/\/+\z/, "")
        .tr(" ", "_")
      joined.empty? ? nil : joined
    end

    def self.build_uri_list(endpoints : Array(String), paths : Array(String) = [] of String) : Array(String)
      out = [] of String
      endpoints.each do |endpoint|
        if paths.any?
          paths.each { |path| out << "#{path}/#{endpoint}" }
        else
          out << endpoint
        end
      end
      out
    end
  end

  class Sequence
    getter name : String
    getter aliases : Array(String)

    @proc : Proc(Int64, FBValue)?
    @initial : Int64 | Array(FBValue)
    @value : Int64 | Array(FBValue)
    @index : Int32

    def self.find_by_uri(uri : String) : Sequence?
      Internal.sequences.to_a.find { |seq| seq.has_uri?(uri) } ||
        Internal.inline_sequences.find { |seq| seq.has_uri?(uri) }
    end

    def initialize(name : String | Symbol, initial : Int64 | Int32 | Array(String) | Array(Symbol) = 1_i64,
                   *, aliases : Array(String | Symbol) = [] of String, uri_paths : Array(String)? = nil)
      @name = name.to_s
      @aliases = aliases.map(&.to_s)
      @proc = nil
      @initial = initial.is_a?(Array) ? initial.map { |v| v.as(FBValue) } : initial.to_i64
      @value = @initial
      @index = 0
    end

    def sequence(&block : Proc(Int64, FBValue)) : Nil
      @proc = block
    end

    def with_proc(&block : Proc(Int64, FBValue)) : self
      @proc = block
      self
    end

    def next_value : FBValue
      current = peek
      increment
      if (proc = @proc) && current.is_a?(Int64)
        proc.call(current)
      else
        current
      end
    end

    def names : Array(String)
      [@name] + @aliases
    end

    def has_name?(test_name : String | Symbol) : Bool
      names.includes?(test_name.to_s)
    end

    def has_uri?(uri : String) : Bool
      uris.includes?(uri)
    end

    def uris : Array(String)
      UriManager.build_uri_list(names)
    end

    def rewind : Nil
      @value = @initial
      @index = 0
    end

    def set_value(new_value : FBValue) : Nil
      if new_value.is_a?(Int64) && @initial.is_a?(Int64)
        if new_value >= @initial
          @value = new_value
        else
          raise ArgumentError.new("Value cannot be less than: #{@initial}")
        end
      elsif @initial.is_a?(Array)
        @index = 0
        arr = @initial.as(Array(FBValue))
        idx = arr.index(new_value)
        raise ArgumentError.new("Unable to find '#{new_value}' in the sequence.") if idx.nil?
        @index = idx
        @value = @initial
      else
        raise ArgumentError.new("Unable to find '#{new_value}' in the sequence.")
      end
    end

    private def peek : FBValue
      case (value = @value)
      when Int64
        value
      when Array(FBValue)
        value[@index]? || value.last?
      else
        nil
      end
    end

    private def increment : Nil
      case (value = @value)
      when Int64
        @value = value + 1
      when Array(FBValue)
        @index += 1
      end
    end
  end
end
