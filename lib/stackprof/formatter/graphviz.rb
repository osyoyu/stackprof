module StackProf
  module Formatter
    module Graphviz
      def print_graphviz(options = {}, f = STDOUT)
        if filter = options[:filter]
          mark_stack = []
          list = frames(true)
          list.each{ |addr, frame| mark_stack << addr if frame[:name] =~ filter }
          while addr = mark_stack.pop
            frame = list[addr]
            unless frame[:marked]
              mark_stack += frame[:edges].map{ |addr, weight| addr if list[addr][:total_samples] <= weight*1.2 }.compact if frame[:edges]
              frame[:marked] = true
            end
          end
          list = list.select{ |addr, frame| frame[:marked] }
          list.each{ |addr, frame| frame[:edges] && frame[:edges].delete_if{ |k,v| list[k].nil? } }
          list
        else
          list = frames(true)
        end


        limit = options[:limit]
        fraction = options[:node_fraction]

        included_nodes = {}
        node_minimum = fraction ? (fraction * overall_samples).ceil : 0

        f.puts "digraph profile {"
        f.puts "Legend [shape=box,fontsize=24,shape=plaintext,label=\""
        f.print "Total samples: #{overall_samples}\\l"
        f.print "Showing top #{limit} nodes\\l" if limit
        f.print "Dropped nodes with < #{node_minimum} samples\\l" if fraction
        f.puts "\"];"

        list.each_with_index do |(frame, info), index|
          call, total = info.values_at(:samples, :total_samples)
          break if total < node_minimum || (limit && index >= limit)

          sample = ''
          sample << "#{call} (%2.1f%%)\\rof " % (call*100.0/overall_samples) if call < total
          sample << "#{total} (%2.1f%%)\\r" % (total*100.0/overall_samples)
          fontsize = (1.0 * call / max_samples) * 28 + 10
          size = (1.0 * total / overall_samples) * 2.0 + 0.5

          f.puts "  \"#{frame}\" [size=#{size}] [fontsize=#{fontsize}] [penwidth=\"#{size}\"] [shape=box] [label=\"#{info[:name]}\\n#{sample}\"];"
          included_nodes[frame] = true
        end

        list.each do |frame, info|
          next unless included_nodes[frame]

          if edges = info[:edges]
            edges.each do |edge, weight|
              next unless included_nodes[edge]

              size = (1.0 * weight / overall_samples) * 2.0 + 0.5
              f.puts "  \"#{frame}\" -> \"#{edge}\" [label=\"#{weight}\"] [weight=\"#{weight}\"] [penwidth=\"#{size}\"];"
            end
          end
        end
        f.puts "}"
      end
    end
  end
end
