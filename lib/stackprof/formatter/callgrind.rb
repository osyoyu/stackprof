module StackProf
  module Formatter
    module Callgrind
      def print_callgrind(f = STDOUT)
        f.puts "version: 1"
        f.puts "creator: stackprof"
        f.puts "pid: 0"
        f.puts "cmd: ruby"
        f.puts "part: 1"
        f.puts "desc: mode: #{modeline}"
        f.puts "desc: missed: #{@data[:missed_samples]})"
        f.puts "positions: line"
        f.puts "events: Instructions"
        f.puts "summary: #{@data[:samples]}"

        list = frames
        list.each do |addr, frame|
          f.puts "fl=#{frame[:file]}"
          f.puts "fn=#{frame[:name]}"
          frame[:lines].each do |line, weight|
            f.puts "#{line} #{weight.is_a?(Array) ? weight[1] : weight}"
          end if frame[:lines]
          frame[:edges].each do |edge, weight|
            oframe = list[edge]
            f.puts "cfl=#{oframe[:file]}" unless oframe[:file] == frame[:file]
            f.puts "cfn=#{oframe[:name]}"
            f.puts "calls=#{weight} #{frame[:line] || 0}\n#{oframe[:line] || 0} #{weight}"
          end if frame[:edges]
          f.puts
        end

        f.puts "totals: #{@data[:samples]}"
      end
    end
  end
end
