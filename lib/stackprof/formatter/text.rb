module StackProf
  module Formatter
    module Text
      def print_text(sort_by_total=false, limit=nil, select_files= nil, reject_files=nil, select_names=nil, reject_names=nil, f = STDOUT)
        f.puts "=================================="
        f.printf "  Mode: #{modeline}\n"
        f.printf "  Samples: #{@data[:samples]} (%.2f%% miss rate)\n", 100.0*@data[:missed_samples]/(@data[:missed_samples]+@data[:samples])
        f.printf "  GC: #{@data[:gc_samples]} (%.2f%%)\n", 100.0*@data[:gc_samples]/@data[:samples]
        f.puts "=================================="
        f.printf "% 10s    (pct)  % 10s    (pct)     FRAME\n" % ["TOTAL", "SAMPLES"]
        list = frames(sort_by_total)
        list.select!{|_, info| select_files.any?{|path| info[:file].start_with?(path)}} if select_files
        list.select!{|_, info| select_names.any?{|reg| info[:name] =~ reg}} if select_names
        list.reject!{|_, info| reject_files.any?{|path| info[:file].start_with?(path)}} if reject_files
        list.reject!{|_, info| reject_names.any?{|reg| info[:name] =~ reg}} if reject_names
        list = list.first(limit) if limit
        list.each do |frame, info|
          call, total = info.values_at(:samples, :total_samples)
          f.printf "% 10d % 8s  % 10d % 8s     %s\n", total, "(%2.1f%%)" % (total*100.0/overall_samples), call, "(%2.1f%%)" % (call*100.0/overall_samples), info[:name]
        end
      end


      def print_method(name, f = STDOUT)
        name = /#{name}/ unless Regexp === name
        frames.each do |frame, info|
          next unless info[:name] =~ name
          file, line = info.values_at(:file, :line)
          line ||= 1

          lines = info[:lines]
          maxline = lines ? lines.keys.max : line + 5
          f.printf "%s (%s:%d)\n", info[:name], file, line
          f.printf "  samples: % 5d self (%2.1f%%)  /  % 5d total (%2.1f%%)\n", info[:samples], 100.0*info[:samples]/overall_samples, info[:total_samples], 100.0*info[:total_samples]/overall_samples

          if (callers = callers_for(frame)).any?
            f.puts "  callers:"
            callers = callers.sort_by(&:last).reverse
            callers.each do |name, weight|
              f.printf "   % 5d  (% 8s)  %s\n", weight, "%3.1f%%" % (100.0*weight/info[:total_samples]), name
            end
          end

          if callees = info[:edges]
            f.printf "  callees (%d total):\n", info[:total_samples]-info[:samples]
            callees = callees.map{ |k, weight| [data[:frames][k][:name], weight] }.sort_by{ |k,v| -v }
            callees.each do |name, weight|
              f.printf "   % 5d  (% 8s)  %s\n", weight, "%3.1f%%" % (100.0*weight/(info[:total_samples]-info[:samples])), name
            end
          end

          f.puts "  code:"
          source_display(f, file, lines, line-1..maxline)
        end
      end
    end
  end
end
