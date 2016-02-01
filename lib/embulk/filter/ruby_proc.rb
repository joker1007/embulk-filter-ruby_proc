module Embulk
  module Filter

    class RubyProc < FilterPlugin
      Plugin.register_filter("ruby_proc", self)

      def self.transaction(config, in_schema, &control)
        task = {
          "columns" => config.param("columns", :array),
          "requires" => config.param("requires", :array, default: []),
        }

        out_columns = in_schema.map do |col|
          target = task["columns"].find { |filter_col| filter_col["name"] == col.name }
          if target
            type = target["type"] ? target["type"].to_sym : col.type
            Embulk::Column.new(index: col.index, name: col.name, type: type || col.type, format: target["format"] || col.format)
          else
            col
          end
        end

        yield(task, out_columns)
      end

      def init
        task["requires"].each do |lib|
          require lib
        end
        @procs = Hash[task["columns"].map {|col|
          [col["name"], eval(col["proc"])]
        }]
        @skip_nils = Hash[task["columns"].map {|col|
          [col["name"], col["skip_nil"].nil? ? true : !!col["skip_nil"]]
        }]
      end

      def close
      end

      def add(page)
        page.each do |record|
          record_hash = hashrize(record)
          @procs.each do |col, pr|
            next unless record_hash.has_key?(col)
            next if record_hash[col].nil? && @skip_nils[col]

            if pr.arity == 1
              record_hash[col] = pr.call(record_hash[col])
            else
              record_hash[col] = pr.call(record_hash[col], record_hash)
            end
          end
          page_builder.add(record_hash.values)
        end
      end

      def finish
        page_builder.finish
      end

      private

      def hashrize(record)
        Hash[in_schema.names.zip(record)]
      end
    end

  end
end
