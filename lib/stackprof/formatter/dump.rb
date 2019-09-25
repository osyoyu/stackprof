module StackProf
  module Formatter
    module Dump
      def print_dump(f=STDOUT)
        f.puts Marshal.dump(@data.reject{|k,v| k == :files })
      end
    end
  end
end
