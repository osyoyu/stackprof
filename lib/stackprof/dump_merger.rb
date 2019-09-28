require 'digest/md5'

module StackProf
  class DumpMerger
    class << self
      def merge_raw_dumps(dumps)
        self.new.merge_raw_dumps(dumps)
      end
    end

    def merge_raw_dumps(dumps, aggressive: true)
      # sanity checks
      raise ArgumentError, "cannot combine different versions of dumps" if dumps.map {|r| r[:version]}.uniq.size > 1
      raise ArgumentError, "cannot combine different modes" if dumps.map {|r| r[:mode]}.uniq.size > 1

      frames = dumps.map {|r| r[:frames]}.inject(&:merge)
      raws = dumps.map {|r| r[:raw]}.concat.flatten.compact
      if aggressive
        frames, raws = aggressive_merge(frames, raws)
      end
      raws = merge_duplicate_raw_segments(raws)

      data = {
        version: dumps[0][:version],
        mode: dumps[0][:mode],
        interval: dumps[0][:interval],
        samples: dumps.map {|r| r[:samples]}.sum,
        gc_samples: dumps.map {|r| r[:gc_samples]}.sum,
        missed_samples: dumps.map {|r| r[:missed_samples]}.sum,
        frames: frames,
        raw: raws,
        # raw_timestamp_deltas: dumps.map {|r| r[:raw_timestamp_deltas]}.concat.flatten.compact,  # is this correct?
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

    def normalized_frame_name(frame)
      Digest::MD5.hexdigest("#{frame[:name]}@#{frame[:file]}:#{frame[:line]}")
    end

    # The 'aggressive' merge mode allows merging dumps coming from different processes.
    # In this mode, stackframes are aggregated by their method names only, and ISeq pointers will be
    # overwritten as if they came from a single process.
    def aggressive_merge(frames, raw_array = [])
      seen_frames = {}
      rename_table = {}

      frames.each do |iseq_ptr, frame|
        normalized_name = normalized_frame_name(frame)
        if !seen_frames.key?(normalized_name)
          # first time, record
          seen_frames[normalized_name] = iseq_ptr
        else
          # merge!
          rename_table[iseq_ptr] = seen_frames[normalized_name]
        end
      end

      # Merge & remove duplicate frames
      rename_table.each do |iseq_from, iseq_to|
        frames[iseq_from][:samples] += frames[iseq_to][:samples]
        frames[iseq_from][:total_samples] += frames[iseq_to][:total_samples]
        frames.delete(iseq_from)
      end

      # Rewrite ISeq pointers in raw stacks
      res_raw = []
      while len = raw_array.shift
        res_raw << len
        callstack = raw_array.slice!(0, len)
        res_raw << callstack.map do |iseq_ptr|
          rename_table.key?(iseq_ptr) ? rename_table[iseq_ptr] : iseq_ptr
        end
        res_raw << raw_array.shift
      end

      [frames, res_raw.flatten]
    end
  end
end
