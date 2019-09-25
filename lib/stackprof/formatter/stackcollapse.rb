module StackProf
  module Formatter
    module Stackcollapse
      def print_stackcollapse
        raise "profile does not include raw samples (add `raw: true` to collecting StackProf.run)" unless raw = data[:raw]

        while len = raw.shift
          frames = raw.slice!(0, len)
          weight = raw.shift

          print frames.map{ |a| data[:frames][a][:name] }.join(';')
          puts " #{weight}"
        end
      end
    end
  end
end
