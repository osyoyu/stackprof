require 'pp'
require 'digest/md5'

require_relative 'formatter/callgrind'
require_relative 'formatter/d3_flamegraph'
require_relative 'formatter/debug'
require_relative 'formatter/dump'
require_relative 'formatter/flamegraph'
require_relative 'formatter/graphviz'
require_relative 'formatter/json'
require_relative 'formatter/stackcollapse'
require_relative 'formatter/text'

module StackProf
  class Report
    include Formatter::Callgrind
    include Formatter::D3Flamegraph
    include Formatter::Debug
    include Formatter::Dump
    include Formatter::Flamegraph
    include Formatter::Graphviz
    include Formatter::Json
    include Formatter::Stackcollapse
    include Formatter::Text

    def initialize(data)
      @data = data
    end
    attr_reader :data

    def frames(sort_by_total=false)
      @data[:"sorted_frames_#{sort_by_total}"] ||=
        @data[:frames].sort_by{ |iseq, stats| -stats[sort_by_total ? :total_samples : :samples] }.inject({}){|h, (k, v)| h[k] = v; h}
    end

    def normalized_frames
      id2hash = {}
      @data[:frames].each do |frame, info|
        id2hash[frame.to_s] = info[:hash] = Digest::MD5.hexdigest("#{info[:name]}#{info[:file]}#{info[:line]}")
      end
      @data[:frames].inject(Hash.new) do |hash, (frame, info)|
        info = hash[id2hash[frame.to_s]] = info.dup
        info[:edges] = info[:edges].inject(Hash.new){ |edges, (edge, weight)| edges[id2hash[edge.to_s]] = weight; edges } if info[:edges]
        hash
      end
    end

    def version
      @data[:version]
    end

    def modeline
      "#{@data[:mode]}(#{@data[:interval]})"
    end

    def overall_samples
      @data[:samples]
    end

    def max_samples
      @data[:max_samples] ||= frames.max_by{ |addr, frame| frame[:samples] }.last[:samples]
    end

    def files
      @data[:files] ||= @data[:frames].inject(Hash.new) do |hash, (addr, frame)|
        if file = frame[:file] and lines = frame[:lines]
          hash[file] ||= Hash.new
          lines.each do |line, weight|
            hash[file][line] = add_lines(hash[file][line], weight)
          end
        end
        hash
      end
    end

    def add_lines(a, b)
      return b if a.nil?
      return a+b if a.is_a? Integer
      return [ a[0], a[1]+b ] if b.is_a? Integer
      [ a[0]+b[0], a[1]+b[1] ]
    end

    # Walk up and down the stack from a given starting point (name).  Loops
    # until `:exit` is selected
    def walk_method(name)
      method_choice  = /#{Regexp.escape name}/
      invalid_choice = false

      # Continue walking up and down the stack until the users selects "exit"
      while method_choice != :exit
        print_method method_choice unless invalid_choice
        STDOUT.puts "\n\n"

        # Determine callers and callees for the current frame
        new_frames  = frames.select  {|_, info| info[:name] =~ method_choice }
        new_choices = new_frames.map {|frame, info| [
          callers_for(frame).sort_by(&:last).reverse.map(&:first),
          (info[:edges] || []).map{ |k, w| [data[:frames][k][:name], w] }.sort_by{ |k,v| -v }.map(&:first)
        ]}.flatten + [:exit]

        # Print callers and callees for selection
        STDOUT.puts "Select next method:"
        new_choices.each_with_index do |method, index|
          STDOUT.printf "%2d)  %s\n", index + 1, method.to_s
        end

        # Pick selection
        STDOUT.printf "> "
        selection = STDIN.gets.chomp.to_i - 1
        STDOUT.puts "\n\n\n"

        # Determine if it was a valid choice
        # (if not, don't re-run .print_method)
        if new_choice = new_choices[selection]
          invalid_choice = false
          method_choice = new_choice == :exit ? :exit : %r/^#{Regexp.escape new_choice}$/
        else
          invalid_choice = true
          STDOUT.puts "Invalid choice.  Please select again..."
        end
      end
    end

    def print_files(sort_by_total=false, limit=nil, f = STDOUT)
      list = files.map{ |file, vals| [file, vals.values.inject([0,0]){ |sum, n| add_lines(sum, n) }] }
      list = list.sort_by{ |file, samples| -samples[1] }
      list = list.first(limit) if limit
      list.each do |file, vals|
        total_samples, samples = *vals
        f.printf "% 5d  (%5.1f%%) / % 5d  (%5.1f%%)   %s\n", total_samples, (100.0*total_samples/overall_samples), samples, (100.0*samples/overall_samples), file
      end
    end

    def print_file(filter, f = STDOUT)
      filter = /#{Regexp.escape filter}/ unless Regexp === filter
      list = files.select{ |name, lines| name =~ filter }
      list.sort_by{ |file, vals| -vals.values.inject(0){ |sum, n| sum + (n.is_a?(Array) ? n[1] : n) } }.each do |file, lines|
        source_display(f, file, lines)
      end
    end

    def merge(other)
      raise ArgumentError, "cannot combine #{other.class}" unless self.class == other.class
      raise ArgumentError, "cannot combine #{modeline} with #{other.modeline}" unless modeline == other.modeline
      raise ArgumentError, "cannot combine v#{version} with v#{other.version}" unless version == other.version

      f1, f2 = normalized_frames, other.normalized_frames
      frames = (f1.keys + f2.keys).uniq.inject(Hash.new) do |hash, id|
        if f1[id].nil?
          hash[id] = f2[id]
        elsif f2[id]
          hash[id] = f1[id]
          hash[id][:total_samples] += f2[id][:total_samples]
          hash[id][:samples] += f2[id][:samples]
          if f2[id][:edges]
            edges = hash[id][:edges] ||= {}
            f2[id][:edges].each do |edge, weight|
              edges[edge] ||= 0
              edges[edge] += weight
            end
          end
          if f2[id][:lines]
            lines = hash[id][:lines] ||= {}
            f2[id][:lines].each do |line, weight|
              lines[line] = add_lines(lines[line], weight)
            end
          end
        else
          hash[id] = f1[id]
        end
        hash
      end

      d1, d2 = data, other.data
      data = {
        version: version,
        mode: d1[:mode],
        interval: d1[:interval],
        samples: d1[:samples] + d2[:samples],
        gc_samples: d1[:gc_samples] + d2[:gc_samples],
        missed_samples: d1[:missed_samples] + d2[:missed_samples],
        frames: frames
      }

      self.class.new(data)
    end

    alias_method :+, :merge

    private
    def root_frames
      frames.select{ |addr, frame| callers_for(addr).size == 0  }
    end

    def callers_for(addr)
      @callers_for ||= {}
      @callers_for[addr] ||= data[:frames].map{ |id, other| [other[:name], other[:edges][addr]] if other[:edges] && other[:edges].include?(addr) }.compact
    end

    def source_display(f, file, lines, range=nil)
      File.readlines(file).each_with_index do |code, i|
        next unless range.nil? || range.include?(i)
        if lines and lineinfo = lines[i+1]
          total_samples, samples = lineinfo
          if version == 1.0
            samples = total_samples
            f.printf "% 5d % 7s  | % 5d  | %s", samples, "(%2.1f%%)" % (100.0*samples/overall_samples), i+1, code
          elsif samples > 0
            f.printf "% 5d  % 8s / % 5d  % 7s  | % 5d  | %s", total_samples, "(%2.1f%%)" % (100.0*total_samples/overall_samples), samples, "(%2.1f%%)" % (100.0*samples/overall_samples), i+1, code
          else
            f.printf "% 5d  % 8s                   | % 5d  | %s", total_samples, "(%3.1f%%)" % (100.0*total_samples/overall_samples), i+1, code
          end
        else
          if version == 1.0
            f.printf "               | % 5d  | %s", i+1, code
          else
            f.printf "                                  | % 5d  | %s", i+1, code
          end
        end
      end
    end

  end
end
