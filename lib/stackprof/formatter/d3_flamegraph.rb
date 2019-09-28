require 'erb'

module StackProf
  module Formatter
    module D3Flamegraph
      def print_d3_flamegraph(f=STDOUT, skip_common=true)
        raise "profile does not include raw samples (add `raw: true` to collecting StackProf.run)" unless raw = data[:raw]

        stacks = []
        max_x = 0
        max_y = 0
        while len = raw.shift
          max_y = len if len > max_y
          stack = raw.slice!(0, len+1)
          stacks << stack
          max_x += stack.last
        end

        # d3-flame-grpah supports only alphabetical flamegraph
        stacks.sort!

        require "json"
        json = JSON.generate(convert_to_d3_flame_graph_format("<root>", stacks, 0), max_nesting: false)

        # This html code is almost copied from d3-flame-graph sample code.
        # (Apache License 2.0)
        # https://github.com/spiermar/d3-flame-graph/blob/gh-pages/index.html

        erb = ERB.new(File.read(__dir__ + '/d3_flamegraph.html.erb'))
        puts erb.result(binding)
      end

      def convert_to_d3_flame_graph_format(name, stacks, depth)
        weight = 0
        children = []
        stacks.chunk do |stack|
          if depth == stack.length - 1
            :leaf
          else
            stack[depth]
          end
        end.each do |val, child_stacks|
          if val == :leaf
            child_stacks.each do |stack|
              weight += stack.last
            end
          else
            frame = frames[val]
            child_name = "#{ frame[:name] } : #{ frame[:file] }:#{ frame[:line] }"
            child_data = convert_to_d3_flame_graph_format(child_name, child_stacks, depth + 1)
            weight += child_data["value"]
            children << child_data
          end
        end

        {
          "name" => name,
          "value" => weight,
          "children" => children,
        }
      end
    end
  end
end
