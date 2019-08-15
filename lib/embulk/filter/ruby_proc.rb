require 'thread'
require 'securerandom'

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
          "pages" => config.param("pages", :array, default: []),
          "skip_rows" => config.param("skip_rows", :array, default: []),
          "before" => config.param("before", :array, default: []),
          "after" => config.param("after", :array, default: []),
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

        @proc_store ||= {}
        @row_proc_store ||= {}
        @page_proc_store ||= {}
        @skip_row_proc_store ||= {}
        transaction_id = rand(100000000)
        until !@proc_store.has_key?(transaction_id)
          transaction_id = rand(100000000)
        end
        evaluator_binding = Evaluator.new(task["variables"]).get_binding

        # In order to avoid multithread probrem, initialize procs here
        before_procs = task["before"].map {|before|
          if before["proc"]
            eval(before["proc"], evaluator_binding)
          else
            eval(File.read(before["proc_file"]), evaluator_binding, File.expand_path(before["proc_file"]))
          end
        }
        @proc_store[transaction_id] = procs = Hash[task["columns"].map {|col|
          if col["proc"]
            [col["name"], eval(col["proc"], evaluator_binding)]
          else
            [col["name"], eval(File.read(col["proc_file"]), evaluator_binding, File.expand_path(col["proc_file"]))]
          end
        }]
        @row_proc_store[transaction_id] = row_procs = task["rows"].map {|rowdef|
          if rowdef["proc"]
            eval(rowdef["proc"], evaluator_binding)
          else
            eval(File.read(rowdef["proc_file"]), evaluator_binding, File.expand_path(rowdef["proc_file"]))
          end
        }.compact
        @page_proc_store[transaction_id] = page_procs = task["pages"].map {|page|
          if page["proc"]
            eval(page["proc"], evaluator_binding)
          else
            eval(File.read(page["proc_file"]), evaluator_binding, File.expand_path(page["proc_file"]))
          end
        }.compact
        @skip_row_proc_store[transaction_id] = skip_row_procs = task["skip_rows"].map {|rowdef|
          if rowdef["proc"]
            eval(rowdef["proc"], evaluator_binding)
          else
            eval(File.read(rowdef["proc_file"]), evaluator_binding, File.expand_path(rowdef["proc_file"]))
          end
        }.compact
        task["transaction_id"] = transaction_id
        if procs.empty? && row_procs.empty? && page_procs.empty? && skip_row_procs.empty?
          raise "Need columns or rows or pages parameter"
        end

        before_procs.each do |pr|
          pr.call
        end

        yield(task, out_columns)

        after_procs = task["after"].map {|after|
          if after["proc"]
            eval(after["proc"], evaluator_binding)
          else
            eval(File.read(after["proc_file"]), evaluator_binding, File.expand_path(after["proc_file"]))
          end
        }

        after_procs.each do |pr|
          pr.call
        end
      end

      def self.proc_store
        @proc_store
      end

      def self.row_proc_store
        @row_proc_store
      end

      def self.page_proc_store
        @page_proc_store
      end

      def self.skip_row_proc_store
        @skip_row_proc_store
      end

      def self.parse_col_procs(columns, evaluator_binding)
        Hash[columns.map {|col|
          if col["proc"]
            [col["name"], eval(col["proc"], evaluator_binding)]
          else
            [col["name"], eval(File.read(col["proc_file"]), evaluator_binding, File.expand_path(col["proc_file"]))]
          end
        }]
      end

      def self.parse_row_procs(rows, evaluator_binding)
        rows.map {|rowdef|
          if rowdef["proc"]
            eval(rowdef["proc"], evaluator_binding)
          else
            eval(File.read(rowdef["proc_file"]), evaluator_binding, File.expand_path(rowdef["proc_file"]))
          end
        }.compact
      end

      def self.parse_page_procs(pages, evaluator_binding)
        pages.map {|page|
          if page["proc"]
            eval(page["proc"], evaluator_binding)
          else
            eval(File.read(page["proc_file"]), evaluator_binding, File.expand_path(page["proc_file"]))
          end
        }.compact
      end

      def init
        task["requires"].each do |lib|
          require lib
        end

        if self.class.proc_store.nil? || self.class.row_proc_store.nil? || self.class.page_proc_store.nil? || self.class.skip_row_proc_store.nil?
          evaluator_binding = Evaluator.new(task["variables"]).get_binding
          @procs = self.class.parse_col_procs(task["columns"], evaluator_binding)
          @row_procs = self.class.parse_row_procs(task["rows"], evaluator_binding)
          @page_procs = self.class.parse_page_procs(task["pages"], evaluator_binding)
          @skip_row_procs = self.class.parse_row_procs(task["skip_rows"], evaluator_binding)
        else
          @procs = self.class.proc_store[task["transaction_id"]]
          @row_procs = self.class.row_proc_store[task["transaction_id"]]
          @page_procs = self.class.page_proc_store[task["transaction_id"]]
          @skip_row_procs = self.class.skip_row_proc_store[task["transaction_id"]]
        end
        @skip_nils = Hash[task["columns"].map {|col|
          [col["name"], col["skip_nil"].nil? ? true : !!col["skip_nil"]]
        }]
      end

      def close
      end

      def add(page)
        proc_records = []
        page.each do |record|
          if row_procs.empty?
            record_hashes = [hashrize(record)]
          else
            record_hashes = row_procs.each_with_object([]) do |pr, arr|
              catch :skip_record do
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
          end

          record_hashes.each do |record_hash|
            catch :skip_record do
              skip_row_procs.each do |pr|
                throw :skip_record if pr.call(record_hash)
              end

              procs.each do |col, pr|
                next unless record_hash.has_key?(col)
                next if record_hash[col].nil? && skip_nils[col]

                if pr.arity == 1
                  record_hash[col] = pr.call(record_hash[col])
                else
                  record_hash[col] = pr.call(record_hash[col], record_hash)
                end
              end
              if page_procs.empty?
                page_builder.add(record_hash.values)
              else
                proc_records << record_hash
              end
            end
          end
        end

        unless page_procs.empty?
          tmp_records = page_procs.each_with_object([]) do |pr, arr|
            result = pr.call(proc_records)
            result.each { |r| arr << r }
          end
          tmp_records.each { |record| page_builder.add(record.values) }
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
        @procs
      end

      def row_procs
        @row_procs
      end

      def page_procs
        @page_procs
      end

      def skip_row_procs
        @skip_row_procs
      end

      def skip_nils
        @skip_nils
      end
    end

  end
end
