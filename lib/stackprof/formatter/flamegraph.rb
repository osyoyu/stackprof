module StackProf
  module Formatter
    module Flamegraph
      def print_timeline_flamegraph(f=STDOUT, skip_common=true)
        print_flamegraph(f, skip_common, false)
      end

      def print_alphabetical_flamegraph(f=STDOUT, skip_common=true)
        print_flamegraph(f, skip_common, true)
      end

      def print_flamegraph(f, skip_common, alphabetical=false)
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

        stacks.sort! if alphabetical

        f.puts 'flamegraph(['
        max_y.times do |y|
          row_prev = nil
          row_width = 0
          x = 0

          stacks.each do |stack|
            weight = stack.last
            cell = stack[y] unless y == stack.length-1

            if cell.nil?
              if row_prev
                flamegraph_row(f, x - row_width, y, row_width, row_prev)
              end

              row_prev = nil
              x += weight
              next
            end

            if row_prev.nil?        # start new row with this cell
              row_width = weight
              row_prev = cell
              x += weight

            elsif row_prev == cell  # grow current row along x-axis
              row_width += weight
              x += weight

            else                    # end current row and start new row
              flamegraph_row(f, x - row_width, y, row_width, row_prev)
              x += weight
              row_prev = cell
              row_width = weight
            end

            row_prev = cell
          end

          if row_prev
            next if skip_common && row_width == max_x

            flamegraph_row(f, x - row_width, y, row_width, row_prev)
          end
        end
        f.puts '])'
      end

      def flamegraph_row(f, x, y, weight, addr)
        frame = frames[addr]
        f.print ',' if @rows_started
        @rows_started = true
        f.puts %{{"x":#{x},"y":#{y},"width":#{weight},"frame_id":#{addr},"frame":#{frame[:name].dump},"file":#{frame[:file].dump}}}
      end
    end
  end
end
