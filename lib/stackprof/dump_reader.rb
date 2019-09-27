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

      data = {
        version: reports[0][:version],
        mode: reports[0][:mode],
        interval: reports[0][:interval],
        samples: reports.map {|r| r[:samples]}.sum,
        gc_samples: reports.map {|r| r[:gc_samples]}.sum,
        missed_samples: reports.map {|r| r[:missed_samples]}.sum,
        frames: reports.map {|r| r[:frames]}.inject(&:merge),
        raw: reports.map {|r| r[:raw]}.concat.flatten.compact,
        raw_timestamp_deltas: reports.map {|r| r[:raw_timestamp_deltas]}.concat.flatten.compact,
      }

      data
    end
  end
end
