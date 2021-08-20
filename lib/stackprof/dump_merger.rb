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

      # (frame.merge!({ iseq_ptr: Integer }))[]
      frames_master_by_name = {}

      raws = dumps.map {|d| aggressively_renamed_raws(frames_master_by_name, d[:frames], d[:raw] || [])}.flatten
      frames = convert_frames_to_hash(frames_master_by_name)

      data = {
        version: dumps[0][:version],
        mode: dumps[0][:mode],
        interval: dumps[0][:interval],
        samples: dumps.map {|r| r[:samples]}.sum,
        gc_samples: dumps.map {|r| r[:gc_samples]}.sum,
        missed_samples: dumps.map {|r| r[:missed_samples]}.sum,
        frames: frames,
        raw: raws,
        raw_timestamp_deltas: dumps.map {|r| r[:raw_timestamp_deltas]}.concat.flatten.compact,  # is this correct?
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

    # Merge dumps from multiple processes, without fear of bugs.
    #
    # @param [Hash] frames_master Canonicalized frames
    # @param [Hash] frames_single Frames from a single dump
    # @param [Array<Number>] raws_single Raws from a single dump
    # @return
    def aggressively_renamed_raws(frames_master_by_name, frames_single, raws_single)
      frames = convert_frames_to_array(frames_single)

      # TODO: Kuso code; this block shouldn't be here
      frames.each do |frame|
        frame_name = normalized_frame_name(frame)
        if !frames_master_by_name.key?(frame_name)
          # first time, record
          frames_master_by_name[frame_name] = frame
        else
          # Merge `samples` count and `total_samples` count
          frames_master_by_name[frame_name][:samples] += frame[:samples]
          frames_master_by_name[frame_name][:total_samples] += frame[:total_samples]
        end
      end

      res_raw = []
      while len = raws_single.shift
        res_raw << len
        callstack = raws_single.slice!(0, len)
        res_raw << callstack.map do |iseq_ptr|
          # Rewrite iseq_ptr based on name
          frame_name = normalized_frame_name(frames_single[iseq_ptr])
          frames_master_by_name[frame_name][:iseq_ptr]
        end
        res_raw << raws_single.shift
      end

      res_raw
    end

    # { [iseq_ptr: Number] => Hash } to Hash[]
    def convert_frames_to_array(frames)
      frames.map do |iseq_ptr, frame|
        frame.merge!({ iseq_ptr: iseq_ptr })
      end
    end

    # Hash[] to { [iseq_ptr: Number] => Hash }
    def convert_frames_to_hash(frames)
      f = frames.map {|frame_name, frame|
        f = frame.dup
        iseq_ptr = f.delete(:iseq_ptr)
        [iseq_ptr, f]
      }
      f.to_h
    end
  end
end
