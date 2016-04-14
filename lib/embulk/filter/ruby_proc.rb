require 'thread'

module Embulk
  module Filter

    class RubyProc < FilterPlugin

      class Evaluator
        attr_reader :variables
        @mutex = Mutex.new

        def self.mutex
          @mutex
        end

        def initialize(variables)
          @variables = variables
        end

        def get_binding
          binding
        end

        def mutex
          self.class.mutex
        end
      end

      Plugin.register_filter("ruby_proc", self)

      def self.transaction(config, in_schema, &control)
        task = {
          "columns" => config.param("columns", :array, default: []),
          "rows" => config.param("rows", :array, default: []),
          "requires" => config.param("requires", :array, default: []),
          "variables" => config.param("variables", :hash, default: {}),
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

        task["requires"].each do |lib|
          require lib
        end

        evaluator_binding = Evaluator.new(task["variables"]).get_binding

        # In order to avoid multithread probrem, initialize procs here
        @procs = Hash[task["columns"].map {|col|
          if col["proc"]
            [col["name"], eval(col["proc"], evaluator_binding)]
          else
            [col["name"], eval(File.read(col["proc_file"]), evaluator_binding, File.expand_path(col["proc_file"]))]
          end
        }]
        @row_procs = task["rows"].map {|rowdef|
          if rowdef["proc"]
            eval(rowdef["proc"], evaluator_binding)
          else
            eval(File.read(rowdef["proc_file"]), evaluator_binding, File.expand_path(rowdef["proc_file"]))
          end
        }.compact
        raise "Need columns or rows parameter" if @row_procs.empty? && @procs.empty?

        yield(task, out_columns)
      end

      def self.procs
        @procs
      end

      def self.row_procs
        @row_procs
      end

      def init
        @skip_nils = Hash[task["columns"].map {|col|
          [col["name"], col["skip_nil"].nil? ? true : !!col["skip_nil"]]
        }]
      end

      def close
      end

      def add(page)
        page.each do |record|
          if row_procs.empty?
            record_hashes = [hashrize(record)]
          else
            record_hashes = row_procs.each_with_object([]) do |pr, arr|
              result = pr.call(hashrize(record))
              case result
              when Array
                result.each do |r|
                  arr << r
                end
              when Hash
                arr << result
              else
                raise "row proc return value must be a Array or Hash"
              end
            end
          end

          record_hashes.each do |record_hash|
            procs.each do |col, pr|
              next unless record_hash.has_key?(col)
              next if record_hash[col].nil? && skip_nils[col]

              if pr.arity == 1
                record_hash[col] = pr.call(record_hash[col])
              else
                record_hash[col] = pr.call(record_hash[col], record_hash)
              end
            end
            page_builder.add(record_hash.values)
          end
        end
      end

      def finish
        page_builder.finish
      end

      private

      def hashrize(record)
        Hash[in_schema.names.zip(record)]
      end

      def procs
        self.class.procs
      end

      def row_procs
        self.class.row_procs
      end

      def skip_nils
        @skip_nils
      end
    end

  end
end
