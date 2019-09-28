require 'digest/md5'

module StackProf
  class DumpReader
    class << self
      def read(path)
        self.new.batch_read([path])
      end

      def batch_read(paths)
        self.new.batch_read(paths)
      end
    end

    def batch_read(paths)
      raw_reports = paths.map do |path|
        begin
          Marshal.load(IO.binread(path))
        rescue TypeError => e
          STDERR.puts "** error parsing #{file}: #{e.inspect}"
        end
      end

      raw_merged = merge_raw_reports(raw_reports)
      StackProf::Report.new(raw_merged)
    end

    def merge_raw_reports(reports, aggressive: false)
      # sanity checks
      raise ArgumentError, "cannot combine different versions of dumps" if reports.map {|r| r[:version]}.uniq.size > 1
      raise ArgumentError, "cannot combine different modes" if reports.map {|r| r[:mode]}.uniq.size > 1

      concatenated_raw = reports.map {|r| r[:raw]}.concat.flatten.compact
      # raw = merge_duplicate_raw_segments(concatenated_raw)
      raw = concatenated_raw

      data = {
        version: reports[0][:version],
        mode: reports[0][:mode],
        interval: reports[0][:interval],
        samples: reports.map {|r| r[:samples]}.sum,
        gc_samples: reports.map {|r| r[:gc_samples]}.sum,
        missed_samples: reports.map {|r| r[:missed_samples]}.sum,
        frames: reports.map {|r| r[:frames]}.inject(&:merge),
        raw: raw,
        raw_timestamp_deltas: reports.map {|r| r[:raw_timestamp_deltas]}.concat.flatten.compact,  # is this correct?
      }

      data
    end

    def merge_duplicate_raw_segments(raw_array)
      stacks = {}
      while len = raw_array.shift
        callstack = raw_array.slice!(0, len)
        appearance_count = raw_array.shift
        hashcode = callstack.hash

        if !stacks.key?(hashcode)
          stacks[hashcode] = {
            callstack: callstack,
            appearance_count: appearance_count
          }
        else
          # merge
          stacks[hashcode][:appearance_count] += appearance_count
        end
      end

      # flatten to the original format
      merged_raw = stacks.map do |hashcode, stack|
        r = []
        r << stack[:callstack].size
        r.append(stack[:callstack])
        r << stack[:appearance_count]
        r
      end.flatten

      merged_raw
    end
  end
end
