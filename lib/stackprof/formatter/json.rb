module StackProf
  module Formatter
    module Json
    def print_json(f=STDOUT)
      require "json"
      f.puts JSON.generate(@data, max_nesting: false)
    end
    end
  end
end
